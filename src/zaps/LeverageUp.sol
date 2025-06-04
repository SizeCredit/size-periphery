// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DepositParams} from "@size/src/market/interfaces/ISize.sol";
import {WithdrawParams} from "@size/src/market/interfaces/ISize.sol";
import {DepositOnBehalfOfParams, WithdrawOnBehalfOfParams} from "@size/src/market/interfaces/v1.7/ISizeV1_7.sol";
import {
    SellCreditMarketParams,
    SellCreditMarketOnBehalfOfParams
} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {
    SetUserConfigurationParams,
    SetUserConfigurationOnBehalfOfParams
} from "@size/src/market/libraries/actions/SetUserConfiguration.sol";
import {Math, PERCENT} from "@size/src/market/libraries/Math.sol";
import {DataView, UserView} from "@size/src/market/SizeViewData.sol";
import {InitializeRiskConfigParams} from "@size/src/market/libraries/actions/Initialize.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPriceFeed} from "@size/src/oracle/IPriceFeed.sol";
import {DexSwap, SwapParams} from "src/liquidator/DexSwap.sol";
import {IRequiresAuthorization} from "src/authorization/IRequiresAuthorization.sol";
import {Action, ActionsBitmap, Authorization} from "@size/src/factory/libraries/Authorization.sol";

contract LeverageUp is DexSwap, IRequiresAuthorization {
    using SafeERC20 for IERC20Metadata;

    error InvalidLeveragePercent(uint256 leveragePercent, uint256 minLeveragePercent, uint256 maxLeveragePercent);

    struct CurrentLeverage {
        uint256 totalCollateral;
        uint256 totalDebt;
        uint256 currentLeveragePercent;
    }

    constructor(address _1inchAggregator, address _unoswapRouter, address _uniswapRouter, address _uniswapV3Router)
        DexSwap(_1inchAggregator, _unoswapRouter, _uniswapRouter, _uniswapV3Router)
    {}

    function leverageUpWithSwap(
        ISize size,
        SellCreditMarketParams[] memory sellCreditMarketParamsArray,
        uint256 collateralAmount,
        uint256 leveragePercent,
        uint256 maxIterations,
        SwapParams memory swapParams
    ) external {
        if (leveragePercent < PERCENT || leveragePercent > maxLeveragePercent(size)) {
            revert InvalidLeveragePercent(leveragePercent, PERCENT, maxLeveragePercent(size));
        }

        DataView memory dataView = size.data();
        InitializeRiskConfigParams memory riskConfig = size.riskConfig();
        uint256 price = IPriceFeed(size.oracle().priceFeed).getPrice();

        dataView.underlyingCollateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        size.deposit(
            DepositParams({token: address(dataView.underlyingCollateralToken), amount: collateralAmount, to: msg.sender})
        );

        dataView.underlyingCollateralToken.forceApprove(address(size), type(uint256).max);
        for (uint256 i = 0; i < maxIterations; i++) {
            CurrentLeverage memory currentLeverage = _currentLeverage(dataView, msg.sender);

            if (currentLeverage.currentLeveragePercent >= leveragePercent) break;

            _sellCreditMarket(
                size, riskConfig, dataView, currentLeverage, sellCreditMarketParamsArray, price, leveragePercent
            );

            size.withdrawOnBehalfOf(
                WithdrawOnBehalfOfParams({
                    params: WithdrawParams({
                        token: address(dataView.underlyingBorrowToken),
                        amount: type(uint256).max,
                        to: address(this)
                    }),
                    onBehalfOf: msg.sender
                })
            );

            _swap(address(dataView.underlyingBorrowToken), address(dataView.underlyingCollateralToken), swapParams);

            collateralAmount = dataView.underlyingCollateralToken.balanceOf(address(this));

            size.deposit(
                DepositParams({
                    token: address(dataView.underlyingCollateralToken),
                    amount: collateralAmount,
                    to: msg.sender
                })
            );
        }
        dataView.underlyingCollateralToken.forceApprove(address(size), 0);
    }

    function maxLeveragePercent(ISize size) public view returns (uint256) {
        InitializeRiskConfigParams memory riskConfig = size.riskConfig();
        return Math.mulDivDown(PERCENT, riskConfig.crLiquidation, riskConfig.crLiquidation - PERCENT);
    }

    function currentLeveragePercent(ISize size, address account) public view returns (uint256) {
        CurrentLeverage memory currentLeverage = _currentLeverage(size.data(), account);
        return currentLeverage.currentLeveragePercent;
    }

    function getActionsBitmap() external pure override returns (ActionsBitmap) {
        Action[] memory actions = new Action[](2);
        actions[0] = Action.SELL_CREDIT_MARKET;
        actions[1] = Action.WITHDRAW;
        return Authorization.getActionsBitmap(actions);
    }

    function _currentLeverage(DataView memory dataView, address account)
        private
        view
        returns (CurrentLeverage memory currentLeverage)
    {
        currentLeverage.totalCollateral = dataView.collateralToken.balanceOf(account);
        currentLeverage.totalDebt = dataView.debtToken.balanceOf(account);
        currentLeverage.currentLeveragePercent = Math.mulDivDown(
            currentLeverage.totalCollateral, PERCENT, currentLeverage.totalCollateral - currentLeverage.totalDebt
        );
    }

    function _sellCreditMarket(
        ISize size,
        InitializeRiskConfigParams memory riskConfig,
        DataView memory dataView,
        CurrentLeverage memory currentLeverage,
        SellCreditMarketParams[] memory sellCreditMarketParamsArray,
        uint256 price,
        uint256 leveragePercent
    ) private {
        uint256 maxBorrowAmount =
            Math.mulDivDown(currentLeverage.totalCollateral, price, riskConfig.crOpening) - currentLeverage.totalDebt;
        for (uint256 j = 0; j < sellCreditMarketParamsArray.length; j++) {
            uint256 cash =
                Math.min(dataView.borrowAToken.balanceOf(sellCreditMarketParamsArray[j].lender), maxBorrowAmount);

            if (
                size.getSellCreditMarketSwapData(sellCreditMarketParamsArray[j]).creditAmountIn
                    < riskConfig.minimumCreditBorrowAToken
            ) {
                continue;
            }

            size.sellCreditMarketOnBehalfOf(
                SellCreditMarketOnBehalfOfParams({
                    params: sellCreditMarketParamsArray[j],
                    onBehalfOf: msg.sender,
                    recipient: address(this)
                })
            );

            maxBorrowAmount -= cash;

            currentLeverage = _currentLeverage(dataView, msg.sender);
            if (currentLeverage.currentLeveragePercent >= leveragePercent) break;
        }
    }
}
