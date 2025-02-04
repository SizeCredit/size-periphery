// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title PeripheryErrors
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
library PeripheryErrors {
    error INVALID_SWAP_METHOD();
    error NOT_AAVE_POOL();
    error NOT_INITIATOR();
    error INSUFFICIENT_BALANCE();
    error GENERIC_SWAP_ROUTE_FAILED();

    error LEVERAGE_GREATER_THAN_MAX(uint256 leverage, uint256 maxLeverage);
    error LEVERAGE_LESS_THAN_MIN(uint256 leverage, uint256 minLeverage);
    error INSUFFICIENT_TOKEN_BALANCE(address token, uint256 actual, uint256 required);
}
