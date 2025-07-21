// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";

import {FlashLoanReceiverBase} from "@aave/flashloan/base/FlashLoanReceiverBase.sol";
import {IPool} from "@aave/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {LiquidateParams} from "@size/src/market/libraries/actions/Liquidate.sol";
import {LiquidateWithReplacementParams} from "@size/src/market/libraries/actions/LiquidateWithReplacement.sol";
import {DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {WithdrawParams} from "@size/src/market/libraries/actions/Withdraw.sol";
import {DexSwap, SwapParams} from "src/liquidator/DexSwap.sol";

import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";

string constant DESCRIPTION = "FlashLoanLiquidator (DexSwap takes SwapParams[] as input)";

struct ReplacementParams {
    uint256 minAPR;
    uint256 deadline;
    address replacementBorrower;
    uint256 collectionId;
    address rateProvider;
}

struct OperationParams {
    address sizeMarket;
    address collateralToken;
    address borrowToken;
    uint256 debtPositionId;
    uint256 minimumCollateralProfit;
    address recipient;
    uint256 deadline;
    SwapParams[] swapParamsArray;
    bool depositProfits;
    bool useReplacement;
    ReplacementParams replacementParams;
    uint256 debtAmount;
}

/// @title FlashLoanLiquidator
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A contract that liquidates debt positions using flash loans
contract FlashLoanLiquidator is Ownable, FlashLoanReceiverBase, DexSwap {
    using SafeERC20 for IERC20;

    constructor(
        address _addressProvider,
        address _1inchAggregator,
        address _unoswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router
    )
        Ownable(msg.sender)
        FlashLoanReceiverBase(IPoolAddressesProvider(_addressProvider))
        DexSwap(_1inchAggregator, _unoswapRouter, _uniswapV2Router, _uniswapV3Router)
    {
        if (_addressProvider == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        POOL = IPool(IPoolAddressesProvider(_addressProvider).getPool());
    }

    function _liquidateDebtPositionWithReplacement(
        address sizeMarket,
        address collateralToken,
        address borrowToken,
        uint256 debtAmount,
        uint256 debtPositionId,
        uint256 minimumCollateralProfit,
        ReplacementParams memory replacementParams
    ) internal {
        // Approve USDC to repay the borrower's debt
        IERC20(borrowToken).forceApprove(sizeMarket, debtAmount);

        ISize size = ISize(sizeMarket);

        // Encode Deposit
        bytes memory depositCall = abi.encodeWithSelector(
            ISize.deposit.selector, DepositParams({token: borrowToken, amount: debtAmount, to: address(this)})
        );

        // Encode Liquidate with Replacement
        bytes memory liquidateCall = abi.encodeWithSelector(
            ISize.liquidateWithReplacement.selector,
            LiquidateWithReplacementParams({
                debtPositionId: debtPositionId,
                borrower: replacementParams.replacementBorrower,
                minimumCollateralProfit: minimumCollateralProfit,
                deadline: replacementParams.deadline,
                minAPR: replacementParams.minAPR,
                collectionId: replacementParams.collectionId,
                rateProvider: replacementParams.rateProvider
            })
        );

        // Encode Withdraw
        bytes memory withdrawCall = abi.encodeWithSelector(
            ISize.withdraw.selector,
            WithdrawParams({token: collateralToken, amount: type(uint256).max, to: address(this)})
        );

        // Multicall
        bytes[] memory calls = new bytes[](3);
        calls[0] = depositCall;
        calls[1] = liquidateCall;
        calls[2] = withdrawCall;

        // slither-disable-next-line unused-return
        size.multicall(calls);
    }

    function _liquidateDebtPosition(
        address sizeMarket,
        address collateralToken,
        address borrowToken,
        uint256 debtAmount,
        uint256 debtPositionId,
        uint256 minimumCollateralProfit,
        uint256 deadline
    ) internal {
        // Approve USDC to repay the borrower's debt
        IERC20(borrowToken).forceApprove(sizeMarket, debtAmount);

        ISize size = ISize(sizeMarket);

        // Encode Deposit
        bytes memory depositCall = abi.encodeWithSelector(
            ISize.deposit.selector, DepositParams({token: borrowToken, amount: debtAmount, to: address(this)})
        );

        // Encode Liquidate
        bytes memory liquidateCall = abi.encodeWithSelector(
            ISize.liquidate.selector,
            LiquidateParams({
                debtPositionId: debtPositionId,
                minimumCollateralProfit: minimumCollateralProfit,
                deadline: deadline
            })
        );

        // Encode Withdraw
        bytes memory withdrawCall = abi.encodeWithSelector(
            ISize.withdraw.selector,
            WithdrawParams({token: collateralToken, amount: type(uint256).max, to: address(this)})
        );

        // Multicall
        bytes[] memory calls = new bytes[](3);
        calls[0] = depositCall;
        calls[1] = liquidateCall;
        calls[2] = withdrawCall;

        // slither-disable-next-line unused-return
        size.multicall(calls);
    }

    function _settleFlashLoan(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address recipient,
        bool depositProfits,
        address sizeMarket
    ) internal {
        uint256 totalDebt = amounts[0] + premiums[0];
        uint256 balance = IERC20(assets[0]).balanceOf(address(this));

        if (balance < totalDebt) {
            revert PeripheryErrors.INSUFFICIENT_BALANCE();
        }

        // Send remainder back to liquidator
        uint256 amountToLiquidator = balance - totalDebt;
        if (depositProfits) {
            IERC20(assets[0]).forceApprove(sizeMarket, amountToLiquidator);
            ISize(sizeMarket).deposit(DepositParams({token: assets[0], amount: amountToLiquidator, to: recipient}));
        } else {
            IERC20(assets[0]).transfer(recipient, amountToLiquidator);
        }

        // Approve the Pool contract to pull the owed amount
        IERC20(assets[0]).forceApprove(address(POOL), amounts[0] + premiums[0]);
    }

    function liquidatePositionWithFlashLoan(
        address sizeMarket,
        address collateralToken,
        address borrowToken,
        uint256 debtPositionId,
        uint256 minimumCollateralProfit,
        uint256 deadline,
        SwapParams[] memory swapParamsArray,
        uint256 supplementAmount,
        address recipient
    ) external {
        if (supplementAmount > 0) {
            IERC20(borrowToken).transferFrom(msg.sender, address(this), supplementAmount);
        }

        ISize size = ISize(sizeMarket);
        uint256 debtAmount = size.getDebtPosition(debtPositionId).futureValue;

        bool depositProfits = recipient != address(0);
        OperationParams memory opParams = OperationParams({
            sizeMarket: sizeMarket,
            collateralToken: collateralToken,
            borrowToken: borrowToken,
            debtPositionId: debtPositionId,
            minimumCollateralProfit: minimumCollateralProfit,
            deadline: deadline,
            recipient: depositProfits ? recipient : msg.sender,
            depositProfits: depositProfits,
            swapParamsArray: swapParamsArray,
            useReplacement: false,
            replacementParams: ReplacementParams({minAPR: 0, deadline: 0, replacementBorrower: address(0), collectionId: type(uint256).max, rateProvider: address(0)}),
            debtAmount: debtAmount
        });

        bytes memory params = abi.encode(opParams);

        address[] memory assets = new address[](1);
        assets[0] = borrowToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtAmount - supplementAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function liquidatePositionWithFlashLoanReplacement(
        address sizeMarket,
        address collateralToken,
        address borrowToken,
        uint256 debtPositionId,
        uint256 minimumCollateralProfit,
        uint256 deadline,
        SwapParams[] memory swapParamsArray,
        uint256 supplementAmount,
        address recipient,
        ReplacementParams memory replacementParams
    ) external onlyOwner {
        if (supplementAmount > 0) {
            IERC20(borrowToken).transferFrom(msg.sender, address(this), supplementAmount);
        }

        ISize size = ISize(sizeMarket);
        uint256 debtAmount = size.getDebtPosition(debtPositionId).futureValue;

        bool depositProfits = recipient != address(0);
        OperationParams memory opParams = OperationParams({
            sizeMarket: sizeMarket,
            collateralToken: collateralToken,
            borrowToken: borrowToken,
            debtPositionId: debtPositionId,
            minimumCollateralProfit: minimumCollateralProfit,
            recipient: depositProfits ? recipient : msg.sender,
            depositProfits: depositProfits,
            deadline: deadline,
            swapParamsArray: swapParamsArray,
            useReplacement: true,
            replacementParams: replacementParams,
            debtAmount: debtAmount
        });

        bytes memory params = abi.encode(opParams);

        address[] memory assets = new address[](1);
        assets[0] = borrowToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtAmount - supplementAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(POOL)) {
            revert PeripheryErrors.NOT_AAVE_POOL();
        }
        if (initiator != address(this)) {
            revert PeripheryErrors.NOT_INITIATOR();
        }

        OperationParams memory opParams = abi.decode(params, (OperationParams));
        if (opParams.useReplacement) {
            _liquidateDebtPositionWithReplacement(
                opParams.sizeMarket,
                opParams.collateralToken,
                opParams.borrowToken,
                opParams.debtAmount,
                opParams.debtPositionId,
                opParams.minimumCollateralProfit,
                opParams.replacementParams
            );
        } else {
            _liquidateDebtPosition(
                opParams.sizeMarket,
                opParams.collateralToken,
                opParams.borrowToken,
                opParams.debtAmount,
                opParams.debtPositionId,
                opParams.minimumCollateralProfit,
                opParams.deadline
            );
        }

        _swap(opParams.swapParamsArray);

        _settleFlashLoan(assets, amounts, premiums, opParams.recipient, opParams.depositProfits, opParams.sizeMarket);

        return true;
    }

    function recover(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function description() external pure returns (string memory) {
        return DESCRIPTION;
    }
}
