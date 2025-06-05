// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {FlashLoanReceiverBase} from "@aave/flashloan/base/FlashLoanReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/interfaces/IPool.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";

abstract contract UpgradeableFlashLoanReceiver is Initializable {
    IPoolAddressesProvider public ADDRESSES_PROVIDER;
    IPool public POOL;

    function __FlashLoanReceiver_init(IPoolAddressesProvider provider) internal onlyInitializing {
        if (address(provider) == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(ADDRESSES_PROVIDER.getPool());
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external virtual returns (bool);
} 