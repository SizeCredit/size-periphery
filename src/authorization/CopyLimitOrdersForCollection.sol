// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";
import {
    CopyLimitOrdersParams,
    CopyLimitOrdersOnBehalfOfParams
} from "@size/src/market/libraries/actions/CopyLimitOrders.sol";
import {OfferLibrary, CopyLimitOrder} from "@size/src/market/libraries/OfferLibrary.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";

contract CopyLimitOrdersForCollection is AccessControlEnumerableUpgradeable, MulticallUpgradeable {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using OfferLibrary for CopyLimitOrder;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant RATE_PROVIDER_ROLE = keccak256("RATE_PROVIDER_ROLE");
    bytes32 public constant BOT_ROLE = keccak256("BOT_ROLE");

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    ISizeFactory public factory;
    uint256 public timelockDelay;
    mapping(address user => mapping(address collection => CopyLimitOrdersParams params)) public
        userToCollectionToCopyLimitOrdersParams;
    mapping(address collection => EnumerableMap.AddressToUintMap marketToAddedAt) private collections;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event AddedToCollection(address indexed collection, ISize indexed market, uint256 addedAt);
    event RemovedFromCollection(address indexed collection, ISize indexed market);
    event CopyLimitOrdersParamsSet(
        address indexed user,
        address indexed collection,
        CopyLimitOrdersParams previousParams,
        CopyLimitOrdersParams newParams
    );
    event FactorySet(ISizeFactory previousFactory, ISizeFactory newFactory);
    event TimelockDelaySet(uint256 previousDelay, uint256 newDelay);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR/INITIALIZER
    //////////////////////////////////////////////////////////////*/

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, ISizeFactory _factory) external initializer {
        __AccessControlEnumerable_init();
        __Multicall_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setTimelockDelay(1 days);
        _setFactory(_factory);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setTimelockDelay(uint256 newTimelockDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTimelockDelay(newTimelockDelay);
    }

    /*//////////////////////////////////////////////////////////////
                            RATE PROVIDER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addToCollection(ISize market) external onlyRole(RATE_PROVIDER_ROLE) {
        if (!factory.isMarket(address(market))) {
            revert Errors.INVALID_MARKET(address(market));
        }
        collections[msg.sender].set(address(market), block.timestamp);
        emit AddedToCollection(msg.sender, market, block.timestamp);
    }

    function removeFromCollection(ISize market) external onlyRole(RATE_PROVIDER_ROLE) {
        collections[msg.sender].remove(address(market));
        emit RemovedFromCollection(msg.sender, market);
    }

    /*//////////////////////////////////////////////////////////////
                            BOT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function copyLimitOrdersOnBehalfOf(
        address collection,
        ISize market,
        address onBehalfOf,
        CopyLimitOrdersParams memory params
    ) public onlyRole(BOT_ROLE) {
        (bool exists, uint256 addedAt) = collections[collection].tryGet(address(market));

        if (exists && addedAt + timelockDelay < block.timestamp) {
            CopyLimitOrdersParams memory overridenParams = _isNull(
                userToCollectionToCopyLimitOrdersParams[onBehalfOf][collection]
            ) ? params : userToCollectionToCopyLimitOrdersParams[onBehalfOf][collection];
            overridenParams.copyAddress = collection;
            market.copyLimitOrdersOnBehalfOf(
                CopyLimitOrdersOnBehalfOfParams({params: overridenParams, onBehalfOf: onBehalfOf})
            );
        }
    }

    function copyLimitOrdersOnBehalfOf(address collection, address onBehalfOf, CopyLimitOrdersParams calldata params)
        external /*onlyRole(BOT_ROLE)*/
    {
        uint256 length = collections[collection].length();
        for (uint256 i = 0; i < length; i++) {
            (address market,) = collections[collection].at(i);
            copyLimitOrdersOnBehalfOf(collection, ISize(market), onBehalfOf, params);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PERMISSIONLESS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setCopyLimitOrdersParams(address collection, CopyLimitOrdersParams calldata params) external {
        emit CopyLimitOrdersParamsSet(
            msg.sender, collection, userToCollectionToCopyLimitOrdersParams[msg.sender][collection], params
        );
        userToCollectionToCopyLimitOrdersParams[msg.sender][collection] = params;
    }

    function getCollection(address collection)
        external
        view
        returns (ISize[] memory markets, uint256[] memory addedAt)
    {
        uint256 length = collections[collection].length();
        markets = new ISize[](length);
        addedAt = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            (address market, uint256 _addedAt) = collections[collection].at(i);
            markets[i] = ISize(market);
            addedAt[i] = _addedAt;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setTimelockDelay(uint256 newTimelockDelay) private {
        emit TimelockDelaySet(timelockDelay, newTimelockDelay);
        timelockDelay = newTimelockDelay;
    }

    function _setFactory(ISizeFactory newFactory) private {
        emit FactorySet(factory, newFactory);
        factory = newFactory;
    }

    function _isNull(CopyLimitOrdersParams memory params) private pure returns (bool) {
        return params.copyAddress == address(0) && params.copyBorrowOffer.isNull() && params.copyLoanOffer.isNull();
    }
}
