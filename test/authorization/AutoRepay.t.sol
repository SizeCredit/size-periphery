// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {AutoRepay} from "src/authorization/AutoRepay.sol";
import {Authorization, Action} from "@size/src/factory/libraries/Authorization.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {LoanStatus} from "@size/src/market/libraries/LoanLibrary.sol";

contract AutoRepayTest is BaseTest {
    AutoRepay public autoRepay;

    function setUp() public override {
        super.setUp();
        vm.warp(block.timestamp + 123 days);
        autoRepay = new AutoRepay();
    }

    function test_AutoRepay_initialState() public view {
        assertEq(autoRepay.EARLY_REPAYMENT_BUFFER(), 1 hours);
    }

    function test_AutoRepay_depositOnBehalfOfAndRepay_too_early() public {
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0));

        uint256 amount = 100e6;
        uint256 tenor = 365 days;

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, tenor, false);

        Vars memory _before = _state();

        assertEq(_before.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue);

        assertEq(_before.bob.borrowATokenBalance, amount);

        _setAuthorization(bob, address(autoRepay), Authorization.getActionsBitmap(Action.DEPOSIT));

        vm.prank(james);
        vm.expectRevert(
            abi.encodeWithSelector(
                PeripheryErrors.AUTO_REPAY_TOO_EARLY.selector, block.timestamp + 365 days, block.timestamp
            )
        );
        autoRepay.depositOnBehalfOfAndRepay(size, debtPositionId, bob);

        Vars memory _after = _state();

        assertEq(_after.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue);
        assertEq(_after.bob.borrowATokenBalance, amount);
    }

    function test_AutoRepay_depositOnBehalfOfAndRepay_early() public {
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0));

        uint256 amount = 100e6;
        uint256 tenor = 365 days;

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, tenor, false);
        _withdraw(bob, address(usdc), 100e6);
        _approve(bob, address(usdc), address(size), 100e6);

        Vars memory _before = _state();

        assertEq(_before.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue, "x");

        _setAuthorization(bob, address(autoRepay), Authorization.getActionsBitmap(Action.DEPOSIT));

        vm.warp(block.timestamp + 365 days - 30 minutes);
        assertEq(size.getLoanStatus(debtPositionId), LoanStatus.ACTIVE);

        vm.prank(james);
        autoRepay.depositOnBehalfOfAndRepay(size, debtPositionId, bob);

        Vars memory _after = _state();

        assertEq(_after.bob.debtBalance, 0, "y");
        assertEq(_after.bob.borrowATokenBalance, 0, "z");
    }

    function test_AutoRepay_depositOnBehalfOfAndRepay_overdue() public {
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0));

        uint256 amount = 100e6;
        uint256 tenor = 365 days;

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, tenor, false);
        _withdraw(bob, address(usdc), 100e6);
        _approve(bob, address(usdc), address(size), 100e6);

        Vars memory _before = _state();

        assertEq(_before.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue);

        _setAuthorization(bob, address(autoRepay), Authorization.getActionsBitmap(Action.DEPOSIT));

        vm.warp(block.timestamp + 365 days + 1 hours);
        assertEq(size.getLoanStatus(debtPositionId), LoanStatus.OVERDUE);

        vm.prank(james);
        autoRepay.depositOnBehalfOfAndRepay(size, debtPositionId, bob);

        Vars memory _after = _state();

        assertEq(_after.bob.debtBalance, 0);
        assertEq(_after.bob.borrowATokenBalance, 0);
    }
}
