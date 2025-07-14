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
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {SellCreditMarketParams, SellCreditMarketOnBehalfOfParams} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {DepositOnBehalfOfParams, DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {WithdrawOnBehalfOfParams, WithdrawParams} from "@size/src/market/libraries/actions/Withdraw.sol";
import {DexSwap, SwapParams} from "src/liquidator/DexSwap.sol";

import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {ActionsBitmap, Action, Authorization} from "@size/src/factory/libraries/Authorization.sol";
import {Math, PERCENT} from "@size/src/market/libraries/Math.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";

/// @title FlashLoanLooping
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A contract that allows users to loop using flash loans
contract FlashLoanLooping is Ownable, FlashLoanReceiverBase, DexSwap {
    using SafeERC20 for IERC20;

    error InvalidPercent(uint256 percent, uint256 minPercent, uint256 maxPercent);
    error TargetLeverageNotAchieved(uint256 currentLeveragePercent, uint256 targetLeveragePercent);

    struct LoopParams {
        address sizeMarket;
        address collateralToken;
        address borrowToken;
        uint256 flashLoanAmount;
        uint256 tenor;
        uint256 maxAPR;
        SellCreditMarketParams[] sellCreditMarketParamsArray;
        address onBehalfOf;
        address recipient;
        uint256 deadline;
        SwapParams[] swapParamsArray;
        bool depositProfits;
        uint256 targetLeveragePercent;
    }

    struct CurrentLeverage {
        uint256 totalCollateral;
        uint256 totalDebt;
        uint256 currentLeveragePercent;
    }

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

    function _executeLoopMulticall(
        ISize size,
        address collateralToken,
        address borrowToken,
        uint256 collateralBalance,
        SellCreditMarketParams[] memory sellCreditMarketParamsArray,
        address onBehalfOf
    ) internal {
        bytes memory depositCall = abi.encodeWithSelector(
            ISize.deposit.selector, 
            DepositOnBehalfOfParams({
                params: DepositParams({token: collateralToken, amount: collateralBalance, to: onBehalfOf}),
                onBehalfOf: address(this)
            })
        );

        // Execute all sell credit market calls
        bytes[] memory calls = new bytes[](1 + sellCreditMarketParamsArray.length);
        calls[0] = depositCall;

        for (uint256 i = 0; i < sellCreditMarketParamsArray.length; i++) {
            bytes memory borrowCall = abi.encodeWithSelector(
                ISize.sellCreditMarket.selector,
                SellCreditMarketOnBehalfOfParams({
                    params: sellCreditMarketParamsArray[i],
                    onBehalfOf: onBehalfOf,
                    recipient: address(this)
                })
            );
            calls[1 + i] = borrowCall;
        }

        // slither-disable-next-line unused-return
        size.multicall(calls);
    }

    function _executeLoop(
        address sizeMarket,
        address collateralToken,
        address borrowToken,
        SellCreditMarketParams[] memory sellCreditMarketParamsArray,
        address onBehalfOf,
        address recipient
    ) internal returns (uint256 borrowedAmount) {
        // Deposit collateral
        uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
        IERC20(collateralToken).forceApprove(sizeMarket, collateralBalance);

        ISize size = ISize(sizeMarket);
        
        // Execute the multicall in a separate function to avoid stack too deep
        _executeLoopMulticall(
            size,
            collateralToken,
            borrowToken,
            collateralBalance,
            sellCreditMarketParamsArray,
            onBehalfOf
        );

        // Return the amount borrowed
        borrowedAmount = IERC20(borrowToken).balanceOf(address(this));
    }

    function _returnRemainderToUser(
        address asset,
        uint256 amountToUser,
        bool depositProfits,
        address sizeMarket,
        address recipient,
        address onBehalfOf
    ) internal {
        if (depositProfits) {
            IERC20(asset).forceApprove(sizeMarket, amountToUser);
            ISize(sizeMarket).depositOnBehalfOf(
                DepositOnBehalfOfParams({
                    params: DepositParams({token: asset, amount: amountToUser, to: recipient}),
                    onBehalfOf: onBehalfOf
                })
            );
        } else {
            IERC20(asset).transfer(recipient, amountToUser);
        }
    }

    function _settleFlashLoan(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address recipient,
        bool depositProfits,
        address sizeMarket,
        address onBehalfOf
    ) internal {
        uint256 totalDebt = amounts[0] + premiums[0];
        uint256 balance = IERC20(assets[0]).balanceOf(address(this));

        if (balance < totalDebt) {
            revert PeripheryErrors.INSUFFICIENT_BALANCE();
        }

        // Send remainder back to user
        uint256 amountToUser = balance - totalDebt;
        _returnRemainderToUser(assets[0], amountToUser, depositProfits, sizeMarket, recipient, onBehalfOf);

        // Approve the Pool contract to pull the owed amount
        IERC20(assets[0]).forceApprove(address(POOL), amounts[0] + premiums[0]);
    }

    function loopPositionWithFlashLoan(
        address sizeMarket,
        address collateralToken,
        address borrowToken,
        uint256 flashLoanAmount,
        uint256 tenor,
        uint256 maxAPR,
        SellCreditMarketParams[] memory sellCreditMarketParamsArray,
        SwapParams[] memory swapParamsArray,
        address recipient,
        uint256 targetLeveragePercent
    ) external {
        ISize size = ISize(sizeMarket);

        bool depositProfits = recipient != address(0);
        LoopParams memory loopParams = LoopParams({
            sizeMarket: sizeMarket,
            collateralToken: collateralToken,
            borrowToken: borrowToken,
            flashLoanAmount: flashLoanAmount,
            tenor: tenor,
            maxAPR: maxAPR,
            sellCreditMarketParamsArray: sellCreditMarketParamsArray,
            onBehalfOf: msg.sender,
            recipient: depositProfits ? recipient : msg.sender,
            deadline: block.timestamp + 1 hours,
            swapParamsArray: swapParamsArray,
            depositProfits: depositProfits,
            targetLeveragePercent: targetLeveragePercent
        });

        bytes memory params = abi.encode(loopParams);

        address[] memory assets = new address[](1);
        assets[0] = borrowToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanAmount;
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

        LoopParams memory loopParams = abi.decode(params, (LoopParams));

        // Execute swaps to convert flash loaned USDC to collateral
        _swap(loopParams.swapParamsArray);

        // Execute the loop (deposit collateral, borrow USDC)
        _executeLoop(
            loopParams.sizeMarket,
            loopParams.collateralToken,
            loopParams.borrowToken,
            loopParams.sellCreditMarketParamsArray,
            loopParams.onBehalfOf,
            loopParams.recipient
        );

        // Check if target leverage was achieved
        uint256 leveragePercentNow = currentLeveragePercent(ISize(loopParams.sizeMarket), loopParams.onBehalfOf);
        if (leveragePercentNow < loopParams.targetLeveragePercent) {
            revert TargetLeverageNotAchieved(leveragePercentNow, loopParams.targetLeveragePercent);
        }

        // Settle the flash loan
        _settleFlashLoan(assets, amounts, premiums, loopParams.recipient, loopParams.depositProfits, loopParams.sizeMarket, loopParams.onBehalfOf);

        return true;
    }

    function currentLeveragePercent(ISize size, address account) public view returns (uint256) {
        CurrentLeverage memory currentLeverage = _currentLeverage(size, size.data(), account);
        return currentLeverage.currentLeveragePercent;
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

    function recover(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function description() external pure returns (string memory) {
        return "FlashLoanLooping (DexSwap takes SwapParams[] as input)";
    }

    function getActionsBitmap() external pure returns (ActionsBitmap) {
        Action[] memory actions = new Action[](3);
        actions[0] = Action.DEPOSIT;
        actions[1] = Action.WITHDRAW;
        actions[2] = Action.SELL_CREDIT_MARKET;
        return Authorization.getActionsBitmap(actions);
    }
} 