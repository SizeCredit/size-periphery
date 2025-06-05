// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DepositParams} from "@size/src/market/interfaces/ISize.sol";
import {WithdrawParams} from "@size/src/market/interfaces/ISize.sol";
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

    error InvalidPercent(uint256 percent, uint256 minPercent, uint256 maxPercent);

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
        uint256 borrowPercent,
        uint256 maxIterations,
        SwapParams[] memory swapParamsArray
    ) external {
        if (leveragePercent < PERCENT || leveragePercent > maxLeveragePercent(size)) {
            revert InvalidPercent(leveragePercent, PERCENT, maxLeveragePercent(size));
        }
        if (borrowPercent > PERCENT) {
            revert InvalidPercent(borrowPercent, 0, PERCENT);
        }

        DataView memory dataView = size.data();
        InitializeRiskConfigParams memory riskConfig = size.riskConfig();
        uint256 price = IPriceFeed(size.oracle().priceFeed).getPrice();

        dataView.underlyingCollateralToken.forceApprove(address(size), type(uint256).max);

        dataView.underlyingCollateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        size.deposit(
            DepositParams({token: address(dataView.underlyingCollateralToken), amount: collateralAmount, to: msg.sender})
        );

        for (uint256 i = 0; i < maxIterations; i++) {
            CurrentLeverage memory currentLeverage = _currentLeverage(size, dataView, msg.sender);

            if (currentLeverage.currentLeveragePercent >= leveragePercent) break;

            _sellCreditMarket(
                size,
                riskConfig,
                dataView,
                currentLeverage,
                sellCreditMarketParamsArray,
                price,
                leveragePercent,
                borrowPercent
            );

            uint256 borrowATokenAmount = dataView.borrowAToken.balanceOf(address(this));
            if (borrowATokenAmount == 0) break;

            size.withdraw(
                WithdrawParams({
                    token: address(dataView.underlyingBorrowToken),
                    amount: borrowATokenAmount,
                    to: address(this)
                })
            );

            _swap(swapParamsArray);

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
        return Math.mulDivDown(PERCENT, riskConfig.crOpening, riskConfig.crOpening - PERCENT);
    }

    function currentLeveragePercent(ISize size, address account) public view returns (uint256) {
        CurrentLeverage memory currentLeverage = _currentLeverage(size, size.data(), account);
        return currentLeverage.currentLeveragePercent;
    }

    function getActionsBitmap() external pure override returns (ActionsBitmap) {
        Action[] memory actions = new Action[](1);
        actions[0] = Action.SELL_CREDIT_MARKET;
        return Authorization.getActionsBitmap(actions);
    }

    function _currentLeverage(ISize size, DataView memory dataView, address account)
        private
        view
        returns (CurrentLeverage memory currentLeverage)
    {
        currentLeverage.totalCollateral = dataView.collateralToken.balanceOf(account);
        currentLeverage.totalDebt = dataView.debtToken.balanceOf(account);
        currentLeverage.currentLeveragePercent = Math.mulDivDown(
            currentLeverage.totalCollateral,
            PERCENT,
            currentLeverage.totalCollateral - size.debtTokenAmountToCollateralTokenAmount(currentLeverage.totalDebt)
        );
    }

    function _sellCreditMarket(
        ISize size,
        InitializeRiskConfigParams memory riskConfig,
        DataView memory dataView,
        CurrentLeverage memory currentLeverage,
        SellCreditMarketParams[] memory sellCreditMarketParamsArray,
        uint256 price,
        uint256 leveragePercent,
        uint256 borrowPercent
    ) private {
        uint256 maxBorrowAmount = Math.mulDivDown(
            currentLeverage.totalCollateral * 10 ** dataView.debtToken.decimals(),
            price,
            riskConfig.crOpening * 10 ** dataView.collateralToken.decimals()
        ) - currentLeverage.totalDebt;
        for (uint256 j = 0; j < sellCreditMarketParamsArray.length; j++) {
            uint256 lenderCashBalance = dataView.borrowAToken.balanceOf(sellCreditMarketParamsArray[j].lender);
            sellCreditMarketParamsArray[j].amount =
                Math.mulDivDown(Math.min(lenderCashBalance, maxBorrowAmount), borrowPercent, PERCENT); // quick fix to account for swap fees

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

            maxBorrowAmount -= sellCreditMarketParamsArray[j].amount;

            currentLeverage = _currentLeverage(size, dataView, msg.sender);
            if (currentLeverage.currentLeveragePercent >= leveragePercent) break;
        }
    }
}
