// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MarketMakerManager} from "src/market-maker/MarketMakerManager.sol";
import {MarketMakerManagerFactory} from "src/market-maker/MarketMakerManagerFactory.sol";
import {Addresses, CONTRACT} from "./Addresses.s.sol";
import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

contract ProposeUpgradeMMMBeacon is Script, Addresses {
    using Safe for *;
    using Tenderly for *;

    Safe.Client safe;
    Tenderly.Client tenderly;
    address signer;
    string derivationPath;

    constructor() {
        safe.initialize(Addresses.addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE]);
        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
    }

    function run() external {
        vm.startBroadcast();

        MarketMakerManager implementation = new MarketMakerManager();
        MarketMakerManagerFactory mmmFactory =
            MarketMakerManagerFactory(Addresses.addresses[block.chainid][CONTRACT.MARKET_MAKER_MANAGER_FACTORY]);

        safe.proposeTransaction(
            address(mmmFactory),
            abi.encodeCall(MarketMakerManagerFactory.upgradeBeacon, (address(implementation))),
            address(this),
            derivationPath
        );

        Tenderly.VirtualTestnet memory vnet = tenderly.createVirtualTestnet("mmmbeacon", 1_000_000 + block.chainid);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(
            vnet.id,
            signer,
            safe.instance().safe,
            safe.getExecTransactionData(
                address(mmmFactory),
                abi.encodeCall(MarketMakerManagerFactory.upgradeBeacon, (address(implementation))),
                signer,
                derivationPath
            )
        );

        vm.stopBroadcast();
    }
}
