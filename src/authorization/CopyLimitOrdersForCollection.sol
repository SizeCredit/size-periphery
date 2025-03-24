// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {
    CopyLimitOrder,
    CopyLimitOrdersParams,
    CopyLimitOrdersOnBehalfOfParams
} from "@size/src/market/libraries/actions/CopyLimitOrders.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract CopyLimitOrdersForCollection is Ownable2Step, Multicall {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint256 public constant TIMELOCK_DELAY = 1 days;

    mapping(address user => CopyLimitOrdersParams params) public userToCopyLimitOrdersParams;
    EnumerableMap.AddressToUintMap private collection;

    event AddedToCollection(ISize market, uint256 addedAt);
    event CopyLimitOrdersParamsSet(
        address indexed user, CopyLimitOrdersParams previousParams, CopyLimitOrdersParams newParams
    );

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addToCollection(ISize market) external onlyOwner {
        collection.set(address(market), block.timestamp);
        emit AddedToCollection(market, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            PERMISSIONLESS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setCopyLimitOrdersParams(CopyLimitOrdersParams calldata params) external {
        emit CopyLimitOrdersParamsSet(msg.sender, userToCopyLimitOrdersParams[msg.sender], params);
        userToCopyLimitOrdersParams[msg.sender] = params;
    }

    function copyLimitOrdersOnBehalfOf(ISize market, address onBehalfOf) public {
        (bool exists, uint256 addedAt) = collection.tryGet(address(market));

        if (exists && addedAt + TIMELOCK_DELAY < block.timestamp) {
            market.copyLimitOrdersOnBehalfOf(
                CopyLimitOrdersOnBehalfOfParams({
                    params: userToCopyLimitOrdersParams[onBehalfOf],
                    onBehalfOf: onBehalfOf
                })
            );
        }
    }

    function copyLimitOrdersOnBehalfOf(address onBehalfOf) external {
        uint256 length = collection.length();
        for (uint256 i = 0; i < length; i++) {
            (address market,) = collection.at(i);
            copyLimitOrdersOnBehalfOf(ISize(market), onBehalfOf);
        }
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
}
