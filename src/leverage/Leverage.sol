// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/interfaces/ISize.sol";
import {DepositParams} from "@size/src/interfaces/ISize.sol";
import {WithdrawParams} from "@size/src/interfaces/ISize.sol";
import {DepositOnBehalfOfParams, WithdrawOnBehalfOfParams} from "@size/src/interfaces/v1.7/ISizeV1_7.sol";
import {
    SellCreditMarketParams, SellCreditMarketOnBehalfOfParams
} from "@size/src/libraries/actions/SellCreditMarket.sol";
import {
    SetUserConfigurationParams,
    SetUserConfigurationOnBehalfOfParams
} from "@size/src/libraries/actions/SetUserConfiguration.sol";
import {Math, PERCENT} from "@size/src/libraries/Math.sol";
import {GrantAndRevokeAuthorizations} from "./GrantAndRevokeAuthorizations.sol";
import {DataView, UserView} from "@size/src/SizeViewData.sol";
import {InitializeRiskConfigParams} from "@size/src/libraries/actions/Initialize.sol";
import {RESERVED_ID} from "@size/src/libraries/LoanLibrary.sol";
import {FlashLoanSimpleReceiverBase} from "@aave/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceFeed} from "@size/src/oracle/IPriceFeed.sol";
import {DexSwap, SwapParams} from "src/DexSwap.sol";

contract Leverage is GrantAndRevokeAuthorizations, FlashLoanSimpleReceiverBase, DexSwap {
    using SafeERC20 for IERC20;

    bytes4[] private actions;

    struct SellCreditMarketWindParams {
        address[] lenders;
        uint256 leverage;
        uint256 tenor;
        uint256 deadline;
        uint256 maxAPR;
    }

    struct Vars {
        ISize size;
        address onBehalfOf;
        SellCreditMarketWindParams sellCreditMarketWindParams;
        SwapParams swapParams;
        InitializeRiskConfigParams riskConfig;
        DataView dataView;
    }

    constructor(
        IPoolAddressesProvider aaveAddressProvider,
        address _1inchAggregator,
        address _unoswapRouter,
        address _uniswapRouter,
        address _uniswapV3Router
    )
        FlashLoanSimpleReceiverBase(aaveAddressProvider)
        DexSwap(_1inchAggregator, _unoswapRouter, _uniswapRouter, _uniswapV3Router)
    {
        actions = [ISize.setUserConfiguration.selector, ISize.deposit.selector, ISize.sellCreditMarket.selector];
    }

    function wind(
        ISize size,
        SellCreditMarketWindParams memory sellCreditMarketWindParams,
        SwapParams memory swapParams
    ) external {
        _grantAuthorizations(size, actions);

        InitializeRiskConfigParams memory riskConfig = size.riskConfig();

        if (sellCreditMarketWindParams.leverage > _maxLeveragePercent(riskConfig)) {
            revert PeripheryErrors.LEVERAGE_GREATER_THAN_MAX(
                sellCreditMarketWindParams.leverage, _maxLeveragePercent(riskConfig)
            );
        }
        if (sellCreditMarketWindParams.leverage < PERCENT) {
            revert PeripheryErrors.LEVERAGE_LESS_THAN_MIN(sellCreditMarketWindParams.leverage, PERCENT);
        }

        DataView memory dataView = size.data();
        UserView memory userView = size.getUserView(msg.sender);

        uint256 collateralAmountToFlashLoan =
            Math.mulDivDown(userView.collateralTokenBalance, sellCreditMarketWindParams.leverage - PERCENT, PERCENT);

        bool shouldSetUserConfiguration =
            userView.user.openingLimitBorrowCR != 0 && userView.user.openingLimitBorrowCR != riskConfig.crOpening;
        if (shouldSetUserConfiguration) {
            _setUserConfiguration(size, userView, msg.sender, riskConfig.crOpening);
        }

        POOL.flashLoanSimple(
            address(this),
            address(dataView.underlyingCollateralToken),
            collateralAmountToFlashLoan,
            abi.encode(
                Vars({
                    size: size,
                    onBehalfOf: msg.sender,
                    sellCreditMarketWindParams: sellCreditMarketWindParams,
                    swapParams: swapParams,
                    riskConfig: riskConfig,
                    dataView: dataView
                })
            ),
            0
        );

        if (shouldSetUserConfiguration) {
            _setUserConfiguration(size, userView, msg.sender, userView.user.openingLimitBorrowCR);
        }

        _revokeAuthorizations(size);
    }

    function unwind() external {}

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        if (msg.sender != address(POOL)) {
            revert PeripheryErrors.NOT_AAVE_POOL();
        }
        if (initiator != address(this)) {
            revert PeripheryErrors.NOT_INITIATOR();
        }

        Vars memory vars = abi.decode(params, (Vars));

        _approve(asset, address(vars.size), amount);
        _depositOnBehalfOf(vars.size, vars.onBehalfOf, asset, amount);

        _manySellCreditMarketOnBehalfOf(
            vars.size,
            vars.onBehalfOf,
            address(this),
            vars.sellCreditMarketWindParams.lenders,
            amount,
            vars.riskConfig,
            vars.sellCreditMarketWindParams.tenor,
            vars.sellCreditMarketWindParams.deadline,
            vars.sellCreditMarketWindParams.maxAPR
        );

        _withdrawOnBehalfOf(
            vars.size, vars.onBehalfOf, address(vars.dataView.underlyingBorrowToken), type(uint256).max, address(this)
        );

        _swap(address(vars.dataView.underlyingBorrowToken), asset, vars.swapParams);

        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < amount + premium) {
            revert PeripheryErrors.INSUFFICIENT_TOKEN_BALANCE(asset, balance, amount + premium);
        }
        _depositOnBehalfOf(vars.size, vars.onBehalfOf, asset, balance - amount - premium);

        _approve(asset, msg.sender, amount + premium);

        return true;
    }

    function _maxLeveragePercent(InitializeRiskConfigParams memory riskConfig) private pure returns (uint256) {
        return Math.mulDivDown(PERCENT, riskConfig.crLiquidation, riskConfig.crLiquidation - PERCENT);
    }

    function _setUserConfiguration(ISize size, UserView memory userView, address onBehalfOf, uint256 crOpening)
        private
    {
        size.setUserConfigurationOnBehalfOf(
            SetUserConfigurationOnBehalfOfParams({
                params: SetUserConfigurationParams({
                    openingLimitBorrowCR: crOpening,
                    allCreditPositionsForSaleDisabled: userView.user.allCreditPositionsForSaleDisabled,
                    creditPositionIdsForSale: false,
                    creditPositionIds: new uint256[](0)
                }),
                onBehalfOf: onBehalfOf
            })
        );
    }

    function _approve(address token, address spender, uint256 amount) private {
        IERC20(token).forceApprove(spender, amount);
    }

    function _depositOnBehalfOf(ISize size, address onBehalfOf, address token, uint256 amount) private {
        size.depositOnBehalfOf(
            DepositOnBehalfOfParams({
                params: DepositParams({token: token, amount: amount, to: onBehalfOf}),
                onBehalfOf: onBehalfOf
            })
        );
    }

    function _withdrawOnBehalfOf(ISize size, address onBehalfOf, address token, uint256 amount, address to) private {
        size.withdrawOnBehalfOf(
            WithdrawOnBehalfOfParams({
                params: WithdrawParams({token: token, amount: amount, to: to}),
                onBehalfOf: onBehalfOf
            })
        );
    }

    function _manySellCreditMarketOnBehalfOf(
        ISize size,
        address onBehalfOf,
        address recipient,
        address[] memory lenders,
        uint256 amount,
        InitializeRiskConfigParams memory riskConfig,
        uint256 tenor,
        uint256 deadline,
        uint256 maxAPR
    ) private {
        uint256 price = IPriceFeed(size.oracle().priceFeed).getPrice();
        uint256 totalBorrowAmount = Math.mulDivDown(amount, price, riskConfig.crOpening);
        uint256 i = 0;
        while (i < lenders.length) {
            address lender = lenders[i];
            uint256 lenderAvailableAmount = size.getUserView(lender).borrowATokenBalance;

            if (lenderAvailableAmount < riskConfig.minimumCreditBorrowAToken /* this is comparing cash to credit */ ) {
                i++;
                continue;
            }

            uint256 cash = Math.min(lenderAvailableAmount, totalBorrowAmount);
            _sellCreditMarketOnBehalfOf(size, onBehalfOf, recipient, lender, cash, tenor, deadline, maxAPR);

            totalBorrowAmount -= cash;
            i++;
        }
    }

    function _sellCreditMarketOnBehalfOf(
        ISize size,
        address onBehalfOf,
        address recipient,
        address lender,
        uint256 amount,
        uint256 tenor,
        uint256 deadline,
        uint256 maxAPR
    ) private {
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: lender,
                    creditPositionId: RESERVED_ID,
                    amount: amount,
                    tenor: tenor,
                    deadline: deadline,
                    maxAPR: maxAPR,
                    exactAmountIn: false
                }),
                onBehalfOf: onBehalfOf,
                recipient: recipient
            })
        );
    }
}
