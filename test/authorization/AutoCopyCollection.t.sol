// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@size/test/BaseTest.sol";
import {AutoCopyCollection} from "src/authorization/AutoCopyCollection.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {
    CopyLimitOrder,
    CopyLimitOrdersParams,
    CopyLimitOrdersOnBehalfOfParams
} from "@size/src/market/libraries/actions/CopyLimitOrders.sol";
import {Authorization, Action} from "@size/src/factory/libraries/Authorization.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";

contract AutoCopyCollectionTest is BaseTest {
    AutoCopyCollection public autoCopyCollection;
    CopyLimitOrdersParams public nullParams;

    address bot;
    address lpc;
    address gauntlet;

    function setUp() public override {
        super.setUp();
        vm.warp(block.timestamp + 123 days);

        bot = makeAddr("BOT");
        lpc = makeAddr("LPC");
        gauntlet = makeAddr("GAUNTLET");

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(new AutoCopyCollection()),
            abi.encodeCall(AutoCopyCollection.initialize, (address(this), sizeFactory))
        );
        autoCopyCollection = AutoCopyCollection(address(proxy));
        sizeFactory.createMarket(f, r, o, d);

        autoCopyCollection.grantRole(autoCopyCollection.BOT_ROLE(), bot);
        autoCopyCollection.grantRole(autoCopyCollection.RATE_PROVIDER_ROLE(), lpc);
        autoCopyCollection.grantRole(autoCopyCollection.RATE_PROVIDER_ROLE(), gauntlet);
    }

    function test_AutoCopyCollection_initialState() public view {
        assertEq(autoCopyCollection.hasRole(autoCopyCollection.DEFAULT_ADMIN_ROLE(), address(this)), true);
        assertEq(autoCopyCollection.timelockDelay(), 1 days);

        (ISize[] memory markets, uint256[] memory addedAt) = autoCopyCollection.getCollection(lpc);
        assertEq(markets.length, 0);
        assertEq(addedAt.length, 0);
    }

    function test_AutoCopyCollection_addToCollection_admin() public {
        ISize market = sizeFactory.getMarket(1);
        vm.prank(lpc);
        autoCopyCollection.addToCollection(market);

        (ISize[] memory markets, uint256[] memory addedAt) = autoCopyCollection.getCollection(lpc);
        assertEq(markets.length, 1);
        assertEq(address(markets[0]), address(market));
        assertEq(addedAt[0], block.timestamp);

        (markets, addedAt) = autoCopyCollection.getCollection(gauntlet);
        assertEq(markets.length, 0);
        assertEq(addedAt.length, 0);
    }

    function test_AutoCopyCollection_addToCollection_not_rate_provider() public {
        ISize market = sizeFactory.getMarket(1);
        vm.prank(alice);
        vm.expectRevert();
        autoCopyCollection.addToCollection(market);
    }

    function test_AutoCopyCollection_removeFromCollection_rate_provider() public {
        ISize market = sizeFactory.getMarket(1);
        vm.prank(lpc);
        autoCopyCollection.addToCollection(market);

        (ISize[] memory markets, uint256[] memory addedAt) = autoCopyCollection.getCollection(lpc);
        assertEq(markets.length, 1);
        assertEq(address(markets[0]), address(market));
        assertEq(addedAt[0], block.timestamp);

        vm.prank(lpc);
        autoCopyCollection.removeFromCollection(market);

        (markets, addedAt) = autoCopyCollection.getCollection(gauntlet);
        assertEq(markets.length, 0);
        assertEq(addedAt.length, 0);
    }

    function test_AutoCopyCollection_removeFromCollection_notAdmin() public {
        ISize market = sizeFactory.getMarket(1);
        vm.prank(alice);
        vm.expectRevert();
        autoCopyCollection.removeFromCollection(market);
    }

    function test_AutoCopyCollection_setCopyLimitOrdersParams() public {
        CopyLimitOrdersParams memory newParams = CopyLimitOrdersParams({
            copyAddress: james,
            copyLoanOffer: CopyLimitOrder({minTenor: 3 days, maxTenor: 15 days, minAPR: 3e18, maxAPR: 15e18, offsetAPR: 0}),
            copyBorrowOffer: CopyLimitOrder({
                minTenor: 5 days,
                maxTenor: 20 days,
                minAPR: 6e18,
                maxAPR: 18e18,
                offsetAPR: 1e18
            })
        });

        vm.prank(bob);
        autoCopyCollection.setCopyLimitOrdersParams(lpc, newParams);

        (
            address storedCopyAddress,
            CopyLimitOrder memory storedCopyLoanOffer,
            CopyLimitOrder memory storedCopyBorrowOffer
        ) = autoCopyCollection.userToCollectionToCopyLimitOrdersParams(bob, lpc);
        assertEq(storedCopyAddress, newParams.copyAddress);

        assertEq(storedCopyLoanOffer.minTenor, newParams.copyLoanOffer.minTenor);
        assertEq(storedCopyLoanOffer.maxTenor, newParams.copyLoanOffer.maxTenor);
        assertEq(storedCopyLoanOffer.minAPR, newParams.copyLoanOffer.minAPR);
        assertEq(storedCopyLoanOffer.maxAPR, newParams.copyLoanOffer.maxAPR);
        assertEq(storedCopyLoanOffer.offsetAPR, newParams.copyLoanOffer.offsetAPR);

        assertEq(storedCopyBorrowOffer.minTenor, newParams.copyBorrowOffer.minTenor);
        assertEq(storedCopyBorrowOffer.maxTenor, newParams.copyBorrowOffer.maxTenor);
        assertEq(storedCopyBorrowOffer.minAPR, newParams.copyBorrowOffer.minAPR);
        assertEq(storedCopyBorrowOffer.maxAPR, newParams.copyBorrowOffer.maxAPR);
        assertEq(storedCopyBorrowOffer.offsetAPR, newParams.copyBorrowOffer.offsetAPR);
    }

    function test_AutoCopyCollection_copyLimitOrdersOnBehalfOf_specificMarket() public {
        ISize market = sizeFactory.getMarket(1);
        vm.prank(lpc);
        autoCopyCollection.addToCollection(market);

        CopyLimitOrdersParams memory newParams = CopyLimitOrdersParams({
            copyAddress: james,
            copyLoanOffer: CopyLimitOrder({minTenor: 3 days, maxTenor: 15 days, minAPR: 3e18, maxAPR: 15e18, offsetAPR: 0}),
            copyBorrowOffer: CopyLimitOrder({
                minTenor: 5 days,
                maxTenor: 20 days,
                minAPR: 6e18,
                maxAPR: 18e18,
                offsetAPR: 1e18
            })
        });

        vm.prank(bob);
        autoCopyCollection.setCopyLimitOrdersParams(lpc, newParams);

        vm.prank(bob);
        sizeFactory.setAuthorization(
            address(autoCopyCollection), Authorization.getActionsBitmap(Action.COPY_LIMIT_ORDERS)
        );

        vm.prank(bot);
        autoCopyCollection.copyLimitOrdersOnBehalfOf(lpc, market, bob, nullParams);
        assertEq(market.getUserCopyLimitOrders(bob).copyAddress, address(0));

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(bot);
        autoCopyCollection.copyLimitOrdersOnBehalfOf(lpc, market, bob, nullParams);
        assertEq(market.getUserCopyLimitOrders(bob).copyAddress, lpc);
    }

    function test_AutoCopyCollection_copyLimitOrdersOnBehalfOf_nonExistingMarket() public {
        ISize market = sizeFactory.getMarket(1);
        vm.prank(bot);
        autoCopyCollection.copyLimitOrdersOnBehalfOf(lpc, market, alice, nullParams);
        assertEq(market.getUserCopyLimitOrders(alice).copyAddress, address(0));
    }

    function test_AutoCopyCollection_copyLimitOrdersOnBehalfOf_allMarkets() public {
        ISize market1 = sizeFactory.getMarket(0);
        ISize market2 = sizeFactory.getMarket(1);
        vm.prank(lpc);
        autoCopyCollection.addToCollection(market1);
        vm.prank(lpc);
        autoCopyCollection.addToCollection(market2);

        vm.warp(block.timestamp + 1 days + 1);

        CopyLimitOrdersParams memory newParams = CopyLimitOrdersParams({
            copyAddress: james,
            copyLoanOffer: CopyLimitOrder({minTenor: 3 days, maxTenor: 15 days, minAPR: 3e18, maxAPR: 15e18, offsetAPR: 0}),
            copyBorrowOffer: CopyLimitOrder({
                minTenor: 5 days,
                maxTenor: 20 days,
                minAPR: 6e18,
                maxAPR: 18e18,
                offsetAPR: 1e18
            })
        });

        vm.prank(bob);
        autoCopyCollection.setCopyLimitOrdersParams(lpc, newParams);

        vm.prank(bob);
        sizeFactory.setAuthorization(
            address(autoCopyCollection), Authorization.getActionsBitmap(Action.COPY_LIMIT_ORDERS)
        );

        vm.prank(bot);
        autoCopyCollection.copyLimitOrdersOnBehalfOf(lpc, bob, nullParams);

        assertEq(market1.getUserCopyLimitOrders(bob).copyAddress, lpc);
        assertEq(market2.getUserCopyLimitOrders(bob).copyAddress, lpc);
    }

    function test_AutoCopyCollection_getCollection() public {
        ISize market1 = sizeFactory.getMarket(0);
        ISize market2 = sizeFactory.getMarket(1);
        vm.prank(gauntlet);
        autoCopyCollection.addToCollection(market1);
        vm.warp(block.timestamp + 100);
        vm.prank(gauntlet);
        autoCopyCollection.addToCollection(market2);

        (ISize[] memory markets, uint256[] memory addedAt) = autoCopyCollection.getCollection(gauntlet);

        assertEq(markets.length, 2);
        assertEq(addedAt.length, 2);

        assertEq(address(markets[0]), address(market1));
        assertEq(addedAt[0], block.timestamp - 100);

        assertEq(address(markets[1]), address(market2));
        assertEq(addedAt[1], block.timestamp);
    }

    function test_AutoCopyCollection_setTimelockDelay_not_admin() public {
        vm.prank(alice);
        vm.expectRevert();
        autoCopyCollection.setTimelockDelay(0);
    }

    function test_AutoCopyCollection_setTimelockDelay_admin() public {
        autoCopyCollection.setTimelockDelay(0);
        assertEq(autoCopyCollection.timelockDelay(), 0);
    }

    function test_AutoCopyCollection_addToCollection_not_market() public {
        address invalid = makeAddr("INVALID");

        vm.prank(lpc);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MARKET.selector, invalid));
        autoCopyCollection.addToCollection(ISize(invalid));
    }
}
