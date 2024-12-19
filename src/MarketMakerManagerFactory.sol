// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {MarketMakerManager} from "src/MarketMakerManager.sol";

contract MarketMakerManagerFactory is Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    UpgradeableBeacon public upgradeableBeacon;
    address private ___UNUSED_DO_NOT_REMOVE;
    address public bot;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketMakerManagerCreated(address marketMakerManager, address marketMaker);
    event BotSet(address indexed oldBot, address indexed newBot);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _bot) public initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        _setBot(_bot);
        upgradeableBeacon = new UpgradeableBeacon(address(new MarketMakerManager()), address(this));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function upgradeBeacon(address newImplementation) external onlyOwner {
        upgradeableBeacon.upgradeTo(newImplementation);
    }

    function setBot(address _bot) external onlyOwner {
        _setBot(_bot);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function createMarketMakerManager(address _marketMaker) external returns (MarketMakerManager) {
        BeaconProxy proxy = new BeaconProxy(
            address(upgradeableBeacon), abi.encodeCall(MarketMakerManager.initialize, (this, _marketMaker))
        );

        emit MarketMakerManagerCreated(address(proxy), _marketMaker);

        return MarketMakerManager(address(proxy));
    }

    function _setBot(address _bot) internal {
        emit BotSet(bot, _bot);
        bot = _bot;
    }
}
