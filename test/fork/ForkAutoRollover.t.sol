// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ForkTestVirtualsUSDC} from "./ForkTestVirtualsUSDC.sol";
import {AutoRollover} from "src/authorization/AutoRollover.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {DebtPosition} from "@src/market/libraries/LoanLibrary.sol";

contract ForkAutoRolloverTest is ForkTestVirtualsUSDC {
    address constant BORROWER = 0x0f0B08CE5Cf394C77CA9763366656C629FDba449;
    address constant LENDER = 0xe136879df65633203E31423082da4F13f5bF8DB1;
    uint256 constant DEBT_POSITION_ID = 181;
    address constant POOL_ADDRESSES_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D; // Base mainnet Aave V3

    function setUp() public override {
        vm.createSelectFork("base", 31138987);
        super.setUp();
    }

    function testFork_AutoRollover() public {
        // Deploy and initialize AutoRollover
        AutoRollover autoRollover = new AutoRollover();
        autoRollover.initialize(address(this), IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER), 1 hours, 1 days, 365 days);

        // Fetch debt position
        DebtPosition memory debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        uint256 dueDate = debtPosition.dueDate;

        // Set rollover params
        uint256 tenor = 30 days;
        uint256 maxAPR = 1e18; // 100% as a placeholder
        uint256 deadline = block.timestamp + 1 days;

        // Impersonate owner and call rollover
        vm.startPrank(address(this));
        autoRollover.rollover(
            size,
            DEBT_POSITION_ID,
            BORROWER,
            LENDER,
            tenor,
            maxAPR,
            deadline
        );
        vm.stopPrank();

        // Assert old debt is repaid (futureValue == 0)
        debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        assertEq(debtPosition.futureValue, 0, "Debt should be repaid after rollover");
    }
} 