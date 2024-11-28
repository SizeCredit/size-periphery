// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/interfaces/ISize.sol";
import {BuyCreditLimitParams, SellCreditLimitParams} from "@size/src/interfaces/ISize.sol";

abstract contract Encoder {
    function _encodeSellCreditLimitParams(SellCreditLimitParams calldata params)
        private
        pure
        returns (bytes memory encoded)
    {
        return abi.encode(
            params.maxDueDate,
            abi.encode(
                params.curveRelativeTime.tenors,
                params.curveRelativeTime.aprs,
                params.curveRelativeTime.marketRateMultipliers
            )
        );
    }

    function _decodeSellCreditLimitParams(bytes memory encoded)
        private
        pure
        returns (SellCreditLimitParams memory params)
    {
        bytes memory curveEncoded;
        (params.maxDueDate, curveEncoded) = abi.decode(encoded, (uint256, bytes));
        (params.curveRelativeTime.tenors, params.curveRelativeTime.aprs, params.curveRelativeTime.marketRateMultipliers)
        = abi.decode(curveEncoded, (uint256[], int256[], uint256[]));
    }

    function _encodeBuyCreditLimitParams(BuyCreditLimitParams calldata params)
        private
        pure
        returns (bytes memory encoded)
    {
        return abi.encode(
            params.maxDueDate,
            abi.encode(
                params.curveRelativeTime.tenors,
                params.curveRelativeTime.aprs,
                params.curveRelativeTime.marketRateMultipliers
            )
        );
    }

    function _decodeBuyCreditLimitParams(bytes memory encoded)
        private
        pure
        returns (BuyCreditLimitParams memory params)
    {
        bytes memory curveEncoded;
        (params.maxDueDate, curveEncoded) = abi.decode(encoded, (uint256, bytes));
        (params.curveRelativeTime.tenors, params.curveRelativeTime.aprs, params.curveRelativeTime.marketRateMultipliers)
        = abi.decode(curveEncoded, (uint256[], int256[], uint256[]));
    }
}
