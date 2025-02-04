// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/interfaces/ISize.sol";
import {
    SetAuthorizationParams,
    SetAuthorizationOnBehalfOfParams
} from "@size/src/libraries/actions/v1.7/Authorization.sol";
import {Authorization} from "@size/src/libraries/actions/v1.7/Authorization.sol";

abstract contract GrantAndRevokeAuthorizations {
    modifier grantAndRevokeAuthorizations(ISize size, bytes4[] memory actions) {
        _grantAuthorizations(size, actions);
        _;
        _revokeAuthorizations(size);
    }

    function _grantAuthorizations(ISize size, bytes4[] memory actions) internal {
        size.setAuthorizationOnBehalfOf(
            SetAuthorizationOnBehalfOfParams({
                params: SetAuthorizationParams({
                    operator: address(this),
                    actionsBitmap: Authorization.getActionsBitmap(actions)
                }),
                onBehalfOf: msg.sender
            })
        );
    }

    function _revokeAuthorizations(ISize size) internal {
        size.setAuthorizationOnBehalfOf(
            SetAuthorizationOnBehalfOfParams({
                params: SetAuthorizationParams({operator: address(this), actionsBitmap: 0}),
                onBehalfOf: msg.sender
            })
        );
    }
}
