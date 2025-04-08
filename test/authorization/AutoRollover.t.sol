// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutoRollover} from "src/authorization/AutoRollover.sol";
import {Authorization, Action} from "@size/src/factory/libraries/Authorization.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {LoanStatus} from "@size/src/market/libraries/LoanLibrary.sol";

contract AutoRolloverTest is BaseTest {
    MockAavePool public mockAavePool;
    AutoRollover public autoRollover;

    function setUp() public override {
        super.setUp();
        mockAavePool = new MockAavePool();
        _mint(address(usdc), address(mockAavePool), 100_000e6);
        vm.warp(block.timestamp + 123 days);
        autoRollover = new AutoRollover(james, IPoolAddressesProvider(address(mockAavePool)));
    }

    function test_AutoRollover_initialState() public view {
        assertEq(autoRollover.owner(), james);
        assertEq(autoRollover.EARLY_REPAYMENT_BUFFER(), 1 hours);
    }

    function _test_AutoRollover_rollover(uint256 tenor, uint256 warp) private {
        _deposit(alice, usdc, 300e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(
            alice,
            block.timestamp + 5 * tenor,
            YieldCurveHelper.customCurve(tenor, uint256(0.03e18), 2 * tenor, uint256(0.05e18))
        );
        uint256 dueDate = block.timestamp + tenor;

        uint256 amount = 100e6;

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, tenor, false);
        _withdraw(bob, address(usdc), type(uint256).max);

        Vars memory _before = _state();

        assertEq(_before.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue);

        _setAuthorization(bob, address(autoRollover), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        vm.warp(block.timestamp + warp);
        LoanStatus expected = warp <= tenor ? LoanStatus.ACTIVE : LoanStatus.OVERDUE;
        assertEq(size.getLoanStatus(debtPositionId), expected);

        uint256 rollover = 2 * tenor;

        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, candy));
        autoRollover.rollover(size, debtPositionId, bob, alice, rollover, type(uint256).max, block.timestamp);

        bool shouldRevert = dueDate > block.timestamp + autoRollover.EARLY_REPAYMENT_BUFFER();

        if (shouldRevert) {
            vm.expectRevert(
                abi.encodeWithSelector(PeripheryErrors.AUTO_REPAY_TOO_EARLY.selector, dueDate, block.timestamp)
            );
        }
        vm.prank(james);
        autoRollover.rollover(size, debtPositionId, bob, alice, rollover, type(uint256).max, block.timestamp);

        if (!shouldRevert) {
            Vars memory _after = _state();

            assertGt(_after.bob.debtBalance, _before.bob.debtBalance);
            assertEq(_after.bob.borrowATokenBalance, 0);
        }
    }

    function test_AutoRollover_rollover_too_early() public {
        _test_AutoRollover_rollover(2 days, 2 days - 1 hours);
    }

    function test_AutoRollover_rollover_early() public {
        _test_AutoRollover_rollover(2 days, 2 days - 30 minutes);
    }

    function test_AutoRollover_rollover_overdue() public {
        _test_AutoRollover_rollover(2 days, 2 days + 1 hours);
    }
}
