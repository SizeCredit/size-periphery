// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

enum CONTRACT {
    ADDRESS_PROVIDER,
    AGGREGATOR_1INCH,
    UNOSWAP_ROUTER,
    UNISWAP_V2_ROUTER,
    UNISWAP_V3_ROUTER,
    SIZE_FACTORY,
    SIZE_GOVERNANCE,
    MARKET_MAKER_MANAGER_FACTORY,
    FLASH_LOAN_LIQUIDATOR,
    MULTI_SEND_CALL_ONLY
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
        addresses[1][CONTRACT.UNISWAP_V2_ROUTER] = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        addresses[8453][CONTRACT.UNISWAP_V2_ROUTER] = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        addresses[84532][CONTRACT.UNISWAP_V2_ROUTER] = address(0);

        // https://docs.uniswap.org/contracts/v3/reference/deployments/
        addresses[1][CONTRACT.UNISWAP_V3_ROUTER] = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        addresses[8453][CONTRACT.UNISWAP_V3_ROUTER] = 0x2626664c2603336E57B271c5C0b26F421741e481;
        addresses[84532][CONTRACT.UNISWAP_V2_ROUTER] = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;

        // https://docs.size.credit/
        addresses[1][CONTRACT.SIZE_FACTORY] = 0x3A9C05c3Da48E6E26f39928653258D7D4Eb594C1;
        addresses[8453][CONTRACT.SIZE_FACTORY] = 0x330Dc31dB45672c1F565cf3EC91F9a01f8f3DF0b;
        addresses[84532][CONTRACT.SIZE_FACTORY] = 0x1bC2Aa26D4F3eCD612ddC4aB2518B59E04468191;

        // https://docs.size.credit/
        addresses[1][CONTRACT.SIZE_GOVERNANCE] = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
        addresses[8453][CONTRACT.SIZE_GOVERNANCE] = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
        addresses[84532][CONTRACT.SIZE_GOVERNANCE] = 0xf7164d2fC05350C75387Fa6C0Cc4F97634cA9451;

        // https://docs.size.credit/
        addresses[1][CONTRACT.MARKET_MAKER_MANAGER_FACTORY] = 0x34608ff33e44973C77b702F87a2478eEB1c4be24;
        addresses[8453][CONTRACT.MARKET_MAKER_MANAGER_FACTORY] = 0x3381aeDD39b4fa423AF3ECB599F7d9788FF3fF83;
        addresses[84532][CONTRACT.MARKET_MAKER_MANAGER_FACTORY] = address(0);

        // https://docs.size.credit/
        addresses[1][CONTRACT.FLASH_LOAN_LIQUIDATOR] = 0x3e1232c65c021A031b223D38BbBd1127CD97F725;
        addresses[8453][CONTRACT.FLASH_LOAN_LIQUIDATOR] = 0x66C84EE9DBd6FFb64f6a119FaC65c408148fcC4c;
        addresses[84532][CONTRACT.FLASH_LOAN_LIQUIDATOR] = address(0);

        // https://github.com/safe-global/safe-deployments/blob/v1.37.32/src/assets/v1.3.0/multi_send_call_only.json
        addresses[1][CONTRACT.MULTI_SEND_CALL_ONLY] = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
        addresses[8453][CONTRACT.MULTI_SEND_CALL_ONLY] = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
        addresses[84532][CONTRACT.MULTI_SEND_CALL_ONLY] = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    }
}
