// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MarketMakerManager} from "src/MarketMakerManager.sol";

contract MarketMakerManagerFactory is Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    UpgradeableBeacon public upgradeableBeacon;
    address private ___UNUSED_DO_NOT_REMOVE;
    address public bot;
    EnumerableSet.AddressSet private emergencyWithdrawers;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketMakerManagerCreated(address marketMakerManager, address marketMaker);
    event BotSet(address indexed oldBot, address indexed newBot);
    event EmergencyWithdrawerSet(address indexed emergencyWithdrawer, bool indexed isEmergencyWithdrawer);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR/INITIALIZER
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

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    function setEmergencyWithdrawer(address emergencyWithdrawer, bool isEmergencyWithdrawer) external onlyOwner {
        if (isEmergencyWithdrawer) {
            emergencyWithdrawers.add(emergencyWithdrawer);
        } else {
            emergencyWithdrawers.remove(emergencyWithdrawer);
        }
        emit EmergencyWithdrawerSet(emergencyWithdrawer, isEmergencyWithdrawer);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createMarketMakerManager(address _marketMaker) external returns (MarketMakerManager) {
        BeaconProxy proxy = new BeaconProxy(
            address(upgradeableBeacon), abi.encodeCall(MarketMakerManager.initialize, (this, _marketMaker))
        );

        emit MarketMakerManagerCreated(address(proxy), _marketMaker);

        return MarketMakerManager(address(proxy));
    }

    function getEmergencyWithdrawers() external view returns (address[] memory) {
        return emergencyWithdrawers.values();
    }

    function isEmergencyWithdrawer(address emergencyWithdrawer) external view returns (bool) {
        return emergencyWithdrawers.contains(emergencyWithdrawer);
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setBot(address _bot) private {
        emit BotSet(bot, _bot);
        bot = _bot;
    }
}
