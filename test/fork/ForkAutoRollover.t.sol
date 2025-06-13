// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ForkTestVirtualsUSDC} from "./ForkTestVirtualsUSDC.sol";
import {AutoRollover} from "src/authorization/AutoRollover.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {DebtPosition} from "@src/market/libraries/LoanLibrary.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Addresses, CONTRACT} from "script/Addresses.s.sol";
import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {ActionsBitmap} from "@size/src/factory/libraries/Authorization.sol";

contract ForkAutoRolloverTest is ForkTestVirtualsUSDC, Addresses {
    // https://basescan.org/tx/0x93cb5935b1d8bf8b11990671aad0008c31ceb1bca5511c900d84ed0944271e40
    address constant BORROWER = 0x0f0B08CE5Cf394C77CA9763366656C629FDba449;
    address constant LENDER = 0x73b875d16d395fe3CA830F8F0F04ADe52706836E;
    uint256 constant DEBT_POSITION_ID = 181;
    address constant POOL_ADDRESSES_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D; // Base mainnet Aave V3

    function setUp() public override {
        vm.createSelectFork("base", 31138987);
        super.setUp();
    }

    function testFork_AutoRollover() public {
        // Log addresses and parameters
        console.log("Deploying AutoRollover with:");
        console.log("POOL_ADDRESSES_PROVIDER:", POOL_ADDRESSES_PROVIDER);
        console.log("Owner:", address(this));
        console.log("size:", address(size));
        console.log("usdc:", address(usdc));
        console.log("virtuals:", address(virtuals));

        // Deploy implementation and proxy (format exactly as in working setup)
        AutoRollover autoRolloverImplementation = new AutoRollover();
        bytes memory initData = abi.encodeWithSelector(
            AutoRollover.initialize.selector,
            address(this),
            IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER),
            48 days,
            1 days,
            365 days
        );
        AutoRollover autoRollover =
            AutoRollover(address(new ERC1967Proxy(address(autoRolloverImplementation), initData)));
        console.log("AutoRollover proxy deployed at:", address(autoRollover));

        // Authorize AutoRollover contract
        console.log("Authorizing AutoRollover contract");
        ActionsBitmap actionsBitmap = autoRollover.getActionsBitmap();
        vm.prank(BORROWER);
        ISizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]).setAuthorization(
            address(autoRollover), actionsBitmap
        );

        // Fetch debt position
        DebtPosition memory debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        uint256 dueDate = debtPosition.dueDate;
        console.log("Debt position dueDate:", dueDate);

        // Set rollover params
        uint256 tenor = 30 days;
        uint256 maxAPR = 1e18; // 100% as a placeholder
        uint256 deadline = block.timestamp + 1 days;

        // Impersonate owner and call rollover
        vm.startPrank(address(this));
        console.log("Calling rollover...");
        autoRollover.rollover(size, DEBT_POSITION_ID, BORROWER, LENDER, tenor, maxAPR, deadline);
        vm.stopPrank();
        console.log("rollover called");

        // Assert old debt is repaid (futureValue == 0)
        debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        console.log("Debt position futureValue after:", debtPosition.futureValue);
        assertEq(debtPosition.futureValue, 0, "Debt should be repaid after rollover");
    }
}
