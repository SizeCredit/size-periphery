// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";
import {
    CopyLimitOrdersParams,
    CopyLimitOrdersOnBehalfOfParams
} from "@size/src/market/libraries/actions/CopyLimitOrders.sol";
import {OfferLibrary, CopyLimitOrder} from "@size/src/market/libraries/OfferLibrary.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";

contract CopyLimitOrdersForCollection is AccessControl, Multicall {
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
    mapping(address user => CopyLimitOrdersParams params) public userCopyLimitOrdersParams;
    EnumerableMap.AddressToUintMap private collection;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event AddedToCollection(ISize market, uint256 addedAt);
    event RemovedFromCollection(ISize market);
    event CopyLimitOrdersParamsSet(
        address indexed user, CopyLimitOrdersParams previousParams, CopyLimitOrdersParams newParams
    );
    event FactorySet(ISizeFactory previousFactory, ISizeFactory newFactory);
    event TimelockDelaySet(uint256 previousDelay, uint256 newDelay);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _admin, ISizeFactory _factory) {
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
        collection.set(address(market), block.timestamp);
        emit AddedToCollection(market, block.timestamp);
    }

    function removeFromCollection(ISize market) external onlyRole(RATE_PROVIDER_ROLE) {
        collection.remove(address(market));
        emit RemovedFromCollection(market);
    }

    /*//////////////////////////////////////////////////////////////
                            BOT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function copyLimitOrdersOnBehalfOf(ISize market, address onBehalfOf, CopyLimitOrdersParams memory params)
        public
        onlyRole(BOT_ROLE)
    {
        (bool exists, uint256 addedAt) = collection.tryGet(address(market));

        if (exists && addedAt + timelockDelay < block.timestamp) {
            CopyLimitOrdersParams memory overridenParams =
                _isNull(userCopyLimitOrdersParams[onBehalfOf]) ? params : userCopyLimitOrdersParams[onBehalfOf];
            market.copyLimitOrdersOnBehalfOf(
                CopyLimitOrdersOnBehalfOfParams({params: overridenParams, onBehalfOf: onBehalfOf})
            );
        }
    }

    function copyLimitOrdersOnBehalfOf(address onBehalfOf, CopyLimitOrdersParams calldata params)
        external /*onlyRole(BOT_ROLE)*/
    {
        uint256 length = collection.length();
        for (uint256 i = 0; i < length; i++) {
            (address market,) = collection.at(i);
            copyLimitOrdersOnBehalfOf(ISize(market), onBehalfOf, params);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PERMISSIONLESS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setCopyLimitOrdersParams(CopyLimitOrdersParams calldata params) external {
        emit CopyLimitOrdersParamsSet(msg.sender, userCopyLimitOrdersParams[msg.sender], params);
        userCopyLimitOrdersParams[msg.sender] = params;
    }

    function getCollection() external view returns (ISize[] memory markets, uint256[] memory addedAt) {
        uint256 length = collection.length();
        markets = new ISize[](length);
        addedAt = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            (address market, uint256 _addedAt) = collection.at(i);
            markets[i] = ISize(market);
            addedAt[i] = _addedAt;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setTimelockDelay(uint256 newTimelockDelay) internal {
        emit TimelockDelaySet(timelockDelay, newTimelockDelay);
        timelockDelay = newTimelockDelay;
    }

    function _setFactory(ISizeFactory newFactory) internal {
        emit FactorySet(factory, newFactory);
        factory = newFactory;
    }

    function _isNull(CopyLimitOrdersParams memory params) internal pure returns (bool) {
        return params.copyAddress == address(0) && params.copyBorrowOffer.isNull() && params.copyLoanOffer.isNull();
    }
}
