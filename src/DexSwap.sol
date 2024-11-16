// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "@size/src/libraries/Errors.sol";
import {I1InchAggregator} from "src/interfaces/dex/I1InchAggregator.sol";
import {IUniswapV2Router02} from "src/interfaces/dex/IUniswapV2Router02.sol";
import {IUnoswapRouter} from "src/interfaces/dex/IUnoswapRouter.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";

enum SwapMethod {
    OneInch,
    Unoswap,
    Uniswap
}

struct SwapParams {
    SwapMethod method;
    bytes data; // Encoded data for the specific swap method
    uint256 deadline; // Deadline for the swap to occur
    uint256 minimumReturnAmount; // Minimum return amount from the swap
}

/// @title DexSwap
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Contract that allows to swap tokens using different DEXs
abstract contract DexSwap {
    using SafeERC20 for IERC20;

    I1InchAggregator public immutable oneInchAggregator;
    IUnoswapRouter public immutable unoswapRouter;
    IUniswapV2Router02 public immutable uniswapRouter;

    constructor(
        address _oneInchAggregator,
        address _unoswapRouter,
        address _uniswapRouter
    ) {
        if (
            _oneInchAggregator == address(0) || _unoswapRouter == address(0) || _uniswapRouter == address(0)
        ) {
            revert Errors.NULL_ADDRESS();
        }

        oneInchAggregator = I1InchAggregator(_oneInchAggregator);
        unoswapRouter = IUnoswapRouter(_unoswapRouter);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    function _swapCollateral(
        address collateralToken,
        address borrowToken,
        SwapParams memory swapParams
    ) internal returns (uint256) {
        if (swapParams.method == SwapMethod.OneInch) {
            return _swapCollateral1Inch(collateralToken, borrowToken, swapParams.data, swapParams.minimumReturnAmount);
        } else if (swapParams.method == SwapMethod.Unoswap) {
            address pool = abi.decode(swapParams.data, (address));
            return _swapCollateralUnoswap(collateralToken, borrowToken, pool, swapParams.minimumReturnAmount);
        } else if (swapParams.method == SwapMethod.Uniswap) {
            address[] memory path = abi.decode(swapParams.data, (address[]));
            return _swapCollateralUniswap(collateralToken, borrowToken, path, swapParams.deadline, swapParams.minimumReturnAmount);
        } else {
            revert PeripheryErrors.INVALID_SWAP_METHOD();
        }
    }

    function _swapCollateral1Inch(
        address collateralToken,
        address borrowToken,
        bytes memory data,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        IERC20(collateralToken).forceApprove(address(oneInchAggregator), type(uint256).max);
        uint256 swappedAmount = oneInchAggregator.swap(
            collateralToken, borrowToken, IERC20(collateralToken).balanceOf(address(this)), minimumReturnAmount, data
        );
        return swappedAmount;
    }

    function _swapCollateralUniswap(
        address collateralToken,
        address borrowToken,
        address[] memory tokenPaths,
        uint256 deadline,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        IERC20(collateralToken).forceApprove(address(uniswapRouter), type(uint256).max);
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            IERC20(collateralToken).balanceOf(address(this)), minimumReturnAmount, tokenPaths, address(this), deadline
        );
        return amounts[amounts.length - 1];
    }

    function _swapCollateralUnoswap(
        address collateralToken,
        address borrowToken,
        address pool,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        IERC20(collateralToken).forceApprove(address(unoswapRouter), type(uint256).max);
        uint256 returnAmount = unoswapRouter.unoswapTo(
            address(this), collateralToken, IERC20(collateralToken).balanceOf(address(this)), minimumReturnAmount, pool
        );

        return returnAmount;
    }
}
