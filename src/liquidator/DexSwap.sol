// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {I1InchAggregator} from "src/interfaces/dex/I1InchAggregator.sol";
import {IUniswapV2Router02} from "src/interfaces/dex/IUniswapV2Router02.sol";
import {IUniswapV3Router} from "src/interfaces/dex/IUniswapV3Router.sol";
import {IUnoswapRouter} from "src/interfaces/dex/IUnoswapRouter.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {BoringPtSeller} from "@pendle/contracts/oracles/PtYtLpOracle/samples/BoringPtSeller.sol";
import {IPMarket} from "@pendle/contracts/interfaces/IPMarket.sol";
import {IStandardizedYield} from "@pendle/contracts/interfaces/IStandardizedYield.sol";

enum SwapMethod {
    OneInch,
    Unoswap,
    UniswapV2,
    UniswapV3,
    GenericRoute,
    BoringPtSeller
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
abstract contract DexSwap is BoringPtSeller {
    using SafeERC20 for IERC20;

    I1InchAggregator public immutable oneInchAggregator;
    IUnoswapRouter public immutable unoswapRouter;
    IUniswapV2Router02 public immutable uniswapV2Router;
    IUniswapV3Router public immutable uniswapV3Router;

    constructor(
        address _oneInchAggregator,
        address _unoswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router
    ) {
        if (
            _oneInchAggregator == address(0) || _unoswapRouter == address(0) || _uniswapV2Router == address(0)
                || _uniswapV3Router == address(0)
        ) {
            revert Errors.NULL_ADDRESS();
        }

        oneInchAggregator = I1InchAggregator(_oneInchAggregator);
        unoswapRouter = IUnoswapRouter(_unoswapRouter);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = IUniswapV3Router(_uniswapV3Router);
    }

    function _swapCollateral(address collateralToken, address borrowToken, SwapParams memory swapParams)
        internal
        returns (uint256)
    {
        if (swapParams.method == SwapMethod.GenericRoute) {
            return _swapCollateralGenericRoute(collateralToken, swapParams.data);
        } else if (swapParams.method == SwapMethod.OneInch) {
            return _swapCollateral1Inch(collateralToken, borrowToken, swapParams.data, swapParams.minimumReturnAmount);
        } else if (swapParams.method == SwapMethod.Unoswap) {
            address pool = abi.decode(swapParams.data, (address));
            return _swapCollateralUnoswap(collateralToken, borrowToken, pool, swapParams.minimumReturnAmount);
        } else if (swapParams.method == SwapMethod.UniswapV2) {
            address[] memory path = abi.decode(swapParams.data, (address[]));
            return _swapCollateralUniswapV2(
                collateralToken, borrowToken, path, swapParams.deadline, swapParams.minimumReturnAmount
            );
        } else if (swapParams.method == SwapMethod.UniswapV3) {
            (uint24 fee, uint160 sqrtPriceLimitX96) = abi.decode(swapParams.data, (uint24, uint160));
            return _swapCollateralUniswapV3(
                collateralToken, borrowToken, fee, sqrtPriceLimitX96, swapParams.minimumReturnAmount
            );
        } else if (swapParams.method == SwapMethod.BoringPtSeller) {
            return _swapCollateralBoringPtSeller(
                collateralToken, borrowToken, swapParams.data, swapParams.minimumReturnAmount
            );
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

    function _swapCollateralUniswapV2(
        address collateralToken,
        address, /* borrowToken */
        address[] memory tokenPaths,
        uint256 deadline,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        IERC20(collateralToken).forceApprove(address(uniswapV2Router), type(uint256).max);
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
            IERC20(collateralToken).balanceOf(address(this)), minimumReturnAmount, tokenPaths, address(this), deadline
        );
        return amounts[amounts.length - 1];
    }

    function _swapCollateralUnoswap(
        address collateralToken,
        address, /* borrowToken */
        address pool,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        IERC20(collateralToken).forceApprove(address(unoswapRouter), type(uint256).max);
        uint256 returnAmount = unoswapRouter.unoswapTo(
            address(this), collateralToken, IERC20(collateralToken).balanceOf(address(this)), minimumReturnAmount, pool
        );

        return returnAmount;
    }

    function _swapCollateralUniswapV3(
        address collateralToken,
        address borrowToken,
        uint24 fee,
        uint160 sqrtPriceLimitX96,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        uint256 amountIn = IERC20(collateralToken).balanceOf(address(this));
        IERC20(collateralToken).forceApprove(address(uniswapV3Router), amountIn);

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: collateralToken,
            tokenOut: borrowToken,
            fee: fee,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: minimumReturnAmount,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        uint256 amountOut = uniswapV3Router.exactInputSingle(params);
        return amountOut;
    }

    function _swapCollateralGenericRoute(address collateralToken, bytes memory routeData) internal returns (uint256) {
        // Decode the first 32 bytes as the target router address
        address router;
        assembly {
            router := mload(add(routeData, 32))
        }

        // The remaining bytes are the call data
        bytes memory callData;
        assembly {
            // Skip first 32 bytes (router address)
            let dataStart := add(routeData, 64)
            let dataLength := mload(add(routeData, 32))
            callData := mload(dataStart)
        }

        // Approve router to spend collateral token
        IERC20(collateralToken).forceApprove(router, type(uint256).max);

        // Execute swap via low-level call
        (bool success, bytes memory result) = router.call(callData);
        if (!success) {
            revert PeripheryErrors.GENERIC_SWAP_ROUTE_FAILED();
        }

        // Decode returned amount (assumes uint256 return value)
        uint256 returnAmount;
        assembly {
            returnAmount := mload(add(result, 32))
        }

        return returnAmount;
    }

    function _swapCollateralBoringPtSeller(
        address collateralToken,
        address borrowToken,
        bytes memory data,
        uint256 minimumReturnAmount
    ) internal returns (uint256) {
        (address market, uint24 fee, uint160 sqrtPriceLimitX96, bool tokenOutIsYieldToken) =
            abi.decode(data, (address, uint24, uint160, bool));

        (IStandardizedYield SY,,) = IPMarket(market).readTokens();
        address tokenOut;
        if (tokenOutIsYieldToken) {
            // PT (e.g. PT-sUSDE-29MAY2025) to yieldToken (e.g. sUSDe)
            tokenOut = SY.yieldToken();
        } else {
            // PT (e.g. PT-wstUSR-25SEP2025) to asset (e.g. USR)
            (, tokenOut,) = SY.assetInfo();
        }

        _sellPtForToken(market, IERC20(collateralToken).balanceOf(address(this)), tokenOut);

        // tokenOut to borrowToken (e.g. USDC)
        return _swapCollateralUniswapV3(tokenOut, borrowToken, fee, sqrtPriceLimitX96, minimumReturnAmount);
    }
}
