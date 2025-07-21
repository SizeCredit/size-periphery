// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AutoRollover} from "src/authorization/AutoRollover.sol";
import {Authorization, Action} from "@size/src/factory/libraries/Authorization.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {LoanStatus} from "@size/src/market/libraries/LoanLibrary.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

// Define events for testing
event EarlyRepaymentBufferUpdated(uint256 oldValue, uint256 newValue);

event MinTenorUpdated(uint256 oldValue, uint256 newValue);

event MaxTenorUpdated(uint256 oldValue, uint256 newValue);

contract AutoRolloverTest is BaseTest {
    MockAavePool public mockAavePool;
    AutoRollover public autoRollover;
    AutoRollover public autoRolloverImplementation;

    uint256 private _initialEarlyRepaymentBuffer = 1 hours;
    uint256 private _initialMinTenor = 1 hours;
    uint256 private _initialMaxTenor = 7 days;

    // Add error selector constant
    bytes4 constant OWNER_ONLY = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));

    function setUp() public override {
        super.setUp();
        mockAavePool = new MockAavePool();
        _mint(address(usdc), address(mockAavePool), 100_000e6);
        vm.warp(block.timestamp + 123 days);

        // Deploy implementation and proxy
        autoRolloverImplementation = new AutoRollover();
        bytes memory initData = abi.encodeWithSelector(
            AutoRollover.initialize.selector,
            james,
            IPoolAddressesProvider(address(mockAavePool)),
            _initialEarlyRepaymentBuffer,
            _initialMinTenor,
            _initialMaxTenor
        );
        autoRollover = AutoRollover(address(new ERC1967Proxy(address(autoRolloverImplementation), initData)));
    }

    function test_AutoRollover_initialState() public view {
        assertEq(autoRollover.owner(), james);
        assertEq(autoRollover.earlyRepaymentBuffer(), _initialEarlyRepaymentBuffer);
        assertEq(autoRollover.minTenor(), _initialMinTenor);
        assertEq(autoRollover.maxTenor(), _initialMaxTenor);
    }

    function test_AutoRollover_setEarlyRepaymentBuffer() public {
        uint256 newBuffer = 2 hours;

        // Test unauthorized access
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(OWNER_ONLY, candy));
        autoRollover.setEarlyRepaymentBuffer(newBuffer);

        // Test setting to zero
        vm.prank(james);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        autoRollover.setEarlyRepaymentBuffer(0);

        // Test successful update
        vm.prank(james);
        autoRollover.setEarlyRepaymentBuffer(newBuffer);
        assertEq(autoRollover.earlyRepaymentBuffer(), newBuffer);
    }

    function test_AutoRollover_setMinTenor() public {
        uint256 newMinTenor = 2 hours;

        // Test unauthorized access
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(OWNER_ONLY, candy));
        autoRollover.setMinTenor(newMinTenor);

        // Test setting minTenor >= maxTenor
        vm.prank(james);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, _initialMaxTenor, _initialMaxTenor));
        autoRollover.setMinTenor(_initialMaxTenor);

        // Test successful update
        vm.prank(james);
        autoRollover.setMinTenor(newMinTenor);
        assertEq(autoRollover.minTenor(), newMinTenor);
    }

    function test_AutoRollover_setMaxTenor() public {
        uint256 newMaxTenor = 14 days;

        // Test unauthorized access
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(OWNER_ONLY, candy));
        autoRollover.setMaxTenor(newMaxTenor);

        // Test setting maxTenor <= minTenor
        vm.prank(james);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, _initialMinTenor, _initialMinTenor));
        autoRollover.setMaxTenor(_initialMinTenor);

        // Test successful update
        vm.prank(james);
        autoRollover.setMaxTenor(newMaxTenor);
        assertEq(autoRollover.maxTenor(), newMaxTenor);
    }

    function test_AutoRollover_initialize_reverts() public {
        // Test initializing implementation directly
        vm.expectRevert(); // Expect any revert
        autoRolloverImplementation.initialize(
            james,
            IPoolAddressesProvider(address(mockAavePool)),
            _initialEarlyRepaymentBuffer,
            _initialMinTenor,
            _initialMaxTenor
        );

        // Test initializing proxy again
        vm.expectRevert(); // Expect any revert
        autoRollover.initialize(
            james,
            IPoolAddressesProvider(address(mockAavePool)),
            _initialEarlyRepaymentBuffer,
            _initialMinTenor,
            _initialMaxTenor
        );
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
        vm.expectRevert(abi.encodeWithSelector(OWNER_ONLY, candy));
        autoRollover.rollover(size, debtPositionId, bob, alice, rollover, type(uint256).max, block.timestamp, type(uint256).max, address(0));

        bool shouldRevert = dueDate > block.timestamp + autoRollover.earlyRepaymentBuffer();

        if (shouldRevert) {
            vm.expectRevert(
                abi.encodeWithSelector(PeripheryErrors.AUTO_REPAY_TOO_EARLY.selector, dueDate, block.timestamp)
            );
        }
        vm.prank(james);
        autoRollover.rollover(size, debtPositionId, bob, alice, rollover, type(uint256).max, block.timestamp, type(uint256).max, address(0));

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

    function test_AutoRollover_initialize_invalidParams() public {
        // Test initializing with zero address provider
        bytes memory initData = abi.encodeWithSelector(
            AutoRollover.initialize.selector,
            james,
            address(0),
            _initialEarlyRepaymentBuffer,
            _initialMinTenor,
            _initialMaxTenor
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        new ERC1967Proxy(address(autoRolloverImplementation), initData);

        // Test initializing with zero early repayment buffer
        initData = abi.encodeWithSelector(
            AutoRollover.initialize.selector,
            james,
            IPoolAddressesProvider(address(mockAavePool)),
            0,
            _initialMinTenor,
            _initialMaxTenor
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        new ERC1967Proxy(address(autoRolloverImplementation), initData);

        // Test initializing with invalid tenor range
        initData = abi.encodeWithSelector(
            AutoRollover.initialize.selector,
            james,
            IPoolAddressesProvider(address(mockAavePool)),
            _initialEarlyRepaymentBuffer,
            _initialMaxTenor, // minTenor >= maxTenor
            _initialMinTenor
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, _initialMaxTenor, _initialMinTenor));
        new ERC1967Proxy(address(autoRolloverImplementation), initData);
    }

    function test_AutoRollover_setEarlyRepaymentBuffer_events() public {
        uint256 newBuffer = 2 hours;

        // Test event emission
        vm.prank(james);
        vm.expectEmit(true, true, true, true);
        emit EarlyRepaymentBufferUpdated(_initialEarlyRepaymentBuffer, newBuffer);
        autoRollover.setEarlyRepaymentBuffer(newBuffer);

        // Test setting to same value (should still emit event)
        vm.prank(james);
        vm.expectEmit(true, true, true, true);
        emit EarlyRepaymentBufferUpdated(newBuffer, newBuffer);
        autoRollover.setEarlyRepaymentBuffer(newBuffer);
    }

    function test_AutoRollover_setMinTenor_events() public {
        uint256 newMinTenor = 2 hours;

        // Test event emission
        vm.prank(james);
        vm.expectEmit(true, true, true, true);
        emit MinTenorUpdated(_initialMinTenor, newMinTenor);
        autoRollover.setMinTenor(newMinTenor);

        // Test setting to same value (should still emit event)
        vm.prank(james);
        vm.expectEmit(true, true, true, true);
        emit MinTenorUpdated(newMinTenor, newMinTenor);
        autoRollover.setMinTenor(newMinTenor);
    }

    function test_AutoRollover_setMaxTenor_events() public {
        uint256 newMaxTenor = 14 days;

        // Test event emission
        vm.prank(james);
        vm.expectEmit(true, true, true, true);
        emit MaxTenorUpdated(_initialMaxTenor, newMaxTenor);
        autoRollover.setMaxTenor(newMaxTenor);

        // Test setting to same value (should still emit event)
        vm.prank(james);
        vm.expectEmit(true, true, true, true);
        emit MaxTenorUpdated(newMaxTenor, newMaxTenor);
        autoRollover.setMaxTenor(newMaxTenor);
    }

    function test_AutoRollover_setMinTenor_edgeCases() public {
        // Test setting minTenor to just below maxTenor
        vm.prank(james);
        autoRollover.setMinTenor(_initialMaxTenor - 1);
        assertEq(autoRollover.minTenor(), _initialMaxTenor - 1);

        // Test setting minTenor to 0 (should be allowed as long as maxTenor > 0)
        vm.prank(james);
        autoRollover.setMinTenor(0);
        assertEq(autoRollover.minTenor(), 0);
    }

    function test_AutoRollover_setMaxTenor_edgeCases() public {
        // Test setting maxTenor to just above minTenor
        vm.prank(james);
        autoRollover.setMaxTenor(_initialMinTenor + 1);
        assertEq(autoRollover.maxTenor(), _initialMinTenor + 1);

        // Test setting maxTenor to a very large value
        vm.prank(james);
        autoRollover.setMaxTenor(type(uint256).max);
        assertEq(autoRollover.maxTenor(), type(uint256).max);
    }

    function test_AutoRollover_rollover_afterEarlyRepaymentBufferChange() public {
        // Setup initial loan
        uint256 tenor = 2 days;
        _deposit(alice, usdc, 300e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(
            alice,
            block.timestamp + 5 * tenor,
            YieldCurveHelper.customCurve(tenor, uint256(0.03e18), 2 * tenor, uint256(0.05e18))
        );
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, tenor, false);
        _withdraw(bob, address(usdc), type(uint256).max);
        _setAuthorization(bob, address(autoRollover), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        uint256 dueDate = block.timestamp + tenor;
        // Warp to 2 hours before due date (should fail with 1 hour buffer)
        uint256 currentTime = dueDate - 2 hours;
        vm.warp(currentTime);

        // Try rollover with original buffer (should fail)
        vm.prank(james);
        vm.expectRevert(); // Expect any revert
        autoRollover.rollover(size, debtPositionId, bob, alice, 2 * tenor, type(uint256).max, block.timestamp, type(uint256).max, address(0));

        // Increase buffer to allow earlier rollover
        vm.prank(james);
        autoRollover.setEarlyRepaymentBuffer(3 hours);

        // Try rollover again (should succeed)
        vm.prank(james);
        autoRollover.rollover(size, debtPositionId, bob, alice, 2 * tenor, type(uint256).max, block.timestamp, type(uint256).max, address(0));

        // Verify loan was rolled over
        Vars memory _after = _state();
        assertGt(_after.bob.debtBalance, 0);
        assertEq(_after.bob.borrowATokenBalance, 0);
    }

    function test_AutoRollover_rollover_afterMaxTenorChange() public {
        // Setup initial loan
        uint256 tenor = 2 days;
        _deposit(alice, usdc, 300e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(
            alice,
            block.timestamp + 5 * tenor,
            YieldCurveHelper.customCurve(tenor, uint256(0.03e18), 2 * tenor, uint256(0.05e18))
        );
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, tenor, false);
        _withdraw(bob, address(usdc), type(uint256).max);
        _setAuthorization(bob, address(autoRollover), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        // Try rollover with tenor above original maxTenor (should fail)
        vm.warp(block.timestamp + tenor - 30 minutes);
        uint256 longTenor = 3 * tenor; // 6 days
        vm.prank(james);
        vm.expectRevert();
        autoRollover.rollover(size, debtPositionId, bob, alice, longTenor, type(uint256).max, block.timestamp, type(uint256).max, address(0));

        // Increase maxTenor to allow longer rollover
        uint256 newMaxTenor = 4 * tenor; // 8 days
        vm.prank(james);
        autoRollover.setMaxTenor(newMaxTenor);

        // Verify maxTenor was updated
        assertEq(autoRollover.maxTenor(), newMaxTenor, "Max tenor not updated correctly");

        // Try rollover again with a tenor that's within the new range
        uint256 validTenor = tenor + 1 days; // 3 days
        vm.prank(james);
        autoRollover.rollover(size, debtPositionId, bob, alice, validTenor, type(uint256).max, block.timestamp, type(uint256).max, address(0));

        // Verify loan was rolled over
        Vars memory _after = _state();
        assertGt(_after.bob.debtBalance, 0);
        assertEq(_after.bob.borrowATokenBalance, 0);
    }
}
