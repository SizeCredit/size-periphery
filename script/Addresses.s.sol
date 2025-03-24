// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

enum CONTRACT {
    ADDRESS_PROVIDER,
    AGGREGATOR_1INCH,
    UNOSWAP_ROUTER,
    UNISWAP_V2_ROUTER,
    UNISWAP_V3_ROUTER
}

contract Addresses {
    mapping(uint256 chainId => mapping(CONTRACT => address)) public addresses;

    constructor() {
        // https://aave.com/docs/resources/addresses
        addresses[1][CONTRACT.ADDRESS_PROVIDER] = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
        addresses[8453][CONTRACT.ADDRESS_PROVIDER] = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
        addresses[84532][CONTRACT.ADDRESS_PROVIDER] = 0x6f7E694fe5250Ce638fFE95524760422E6e41997;

        // ?
        addresses[1][CONTRACT.AGGREGATOR_1INCH] = address(0);
        addresses[8453][CONTRACT.AGGREGATOR_1INCH] = address(0);
        addresses[84532][CONTRACT.AGGREGATOR_1INCH] = address(0);

        // ?
        addresses[1][CONTRACT.UNOSWAP_ROUTER] = address(0);
        addresses[8453][CONTRACT.UNOSWAP_ROUTER] = address(0);
        addresses[84532][CONTRACT.UNOSWAP_ROUTER] = address(0);

        // ?
        addresses[1][CONTRACT.UNISWAP_V2_ROUTER] = address(0);
        addresses[8453][CONTRACT.UNISWAP_V2_ROUTER] = address(0);
        addresses[84532][CONTRACT.UNISWAP_V2_ROUTER] = address(0);

        // https://docs.uniswap.org/contracts/v3/reference/deployments/
        addresses[1][CONTRACT.UNISWAP_V3_ROUTER] = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        addresses[8453][CONTRACT.UNISWAP_V3_ROUTER] = 0x2626664c2603336E57B271c5C0b26F421741e481;
        addresses[84532][CONTRACT.UNISWAP_V2_ROUTER] = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    }
}
