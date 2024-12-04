// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseTest} from "@size/test/BaseTest.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MarketMakerManager} from "src/market-maker/MarketMakerManager.sol";
import {
    DepositParams, WithdrawParams, BuyCreditLimitParams, SellCreditLimitParams
} from "@size/src/interfaces/ISize.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve} from "@size/src/libraries/YieldCurveLibrary.sol";

contract MarketMakerManagerTest is BaseTest {
    address public bot;
    address public mm;
    MarketMakerManager public marketMakerManager;

    function setUp() public override {
        super.setUp();

        mm = makeAddr("mm");
        bot = makeAddr("bot");

        marketMakerManager = MarketMakerManager(
            payable(
                new ERC1967Proxy(
                    address(new MarketMakerManager()), abi.encodeCall(MarketMakerManager.initialize, (mm, bot))
                )
            )
        );
    }

    function test_MarketMakerManager_initialize() public {
        assertEq(marketMakerManager.owner(), mm);
        assertEq(marketMakerManager.bot(), bot);
    }

    function test_MarketMakerManager_upgrade_onlyOwner() public {
        address newImplementation = address(new MarketMakerManager());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bot));
        vm.prank(bot);
        marketMakerManager.upgradeToAndCall(
            payable(newImplementation), abi.encodeCall(MarketMakerManager.initialize, (bot, bot))
        );
    }

    function test_MarketMakerManager_setBot() public {
        address newBot = makeAddr("newBot");
        vm.prank(mm);
        marketMakerManager.setBot(newBot);
        assertEq(marketMakerManager.bot(), newBot);
    }

    function test_MarketMakerManager_setBot_onlyOwner() public {
        address newBot = makeAddr("newBot");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        marketMakerManager.setBot(newBot);
    }

    function test_MarketMakerManager_deposit() public {
        uint256 amount = 100e6;
        usdc.mint(mm, amount);
        vm.prank(mm);

        uint256 balanceBefore = size.getUserView(address(marketMakerManager)).borrowATokenBalance;

        vm.prank(mm);
        usdc.approve(address(marketMakerManager), amount);
        vm.prank(mm);
        marketMakerManager.deposit(size, usdc, amount);

        uint256 balanceAfter = size.getUserView(address(marketMakerManager)).borrowATokenBalance;
        assertEq(balanceAfter, balanceBefore + amount);
    }

    function test_MarketMakerManager_deposit_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        marketMakerManager.deposit(size, usdc, 100e6);
    }

    function test_MarketMakerManager_withdraw() public {
        uint256 amount = 100e6;
        usdc.mint(mm, amount);

        vm.prank(mm);
        usdc.approve(address(marketMakerManager), amount);
        vm.prank(mm);
        marketMakerManager.deposit(size, usdc, amount);

        uint256 amount2 = 30e6;
        uint256 balanceBefore = usdc.balanceOf(mm);
        uint256 balanceBeforeSize = size.getUserView(address(marketMakerManager)).borrowATokenBalance;

        vm.prank(mm);
        marketMakerManager.withdraw(size, usdc, amount2);

        uint256 balanceAfter = usdc.balanceOf(mm);
        uint256 balanceAfterSize = size.getUserView(address(marketMakerManager)).borrowATokenBalance;
        assertEq(balanceAfter, balanceBefore + amount2);
        assertEq(balanceAfterSize, amount - amount2, balanceAfterSize);
    }

    function test_MarketMakerManager_withdraw_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        marketMakerManager.withdraw(size, usdc, 100e6);
    }

    function test_MarketMakerManager_buyCreditLimit() public {
        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        vm.prank(bot);
        marketMakerManager.buyCreditLimit(
            size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );
    }

    function test_MarketMakerManager_buyCreditLimit_onlyBot() public {
        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBot.selector));
        marketMakerManager.buyCreditLimit(
            size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );
    }

    function test_MarketMakerManager_sellCreditLimit() public {
        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        vm.prank(bot);
        marketMakerManager.sellCreditLimit(
            size, SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );
    }

    function test_MarketMakerManager_sellCreditLimit_onlyBot() public {
        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBot.selector));
        marketMakerManager.sellCreditLimit(
            size, SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );
    }

    function test_MarketMakerManager_validateCurvesDoNotIntersect_whenCurvesDoNotIntersect_1() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.normalCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.steepCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, params);

        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);
    }

    function test_MarketMakerManager_validateCurvesDoNotIntersect_whenCurvesDoNotIntersect_2() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.normalCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.steepCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);

        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, params);
    }

    function test_MarketMakerManager_validateCurvesDoNotIntersect_whenCurvesIntersect_1() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.flatCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.normalCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, params);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.CurvesIntersect.selector));
        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);
    }

    function test_MarketMakerManager_validateCurvesDoNotIntersect_whenCurvesIntersect_2() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.flatCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.normalCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.CurvesIntersect.selector));
        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, params);
    }

    // test for curves with non-null multplier
    function test_MarketMakerManager_validateCurvesDoNotIntersect_non_null_multiplier() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.marketCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.marketCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyNullMultipliersAllowed.selector));
        marketMakerManager.buyCreditLimit(size, params);

        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyNullMultipliersAllowed.selector));
        marketMakerManager.sellCreditLimit(size, params2);
    }

    function test_MarketMakerManager_pause_owner() public {
        vm.prank(mm);
        marketMakerManager.pause();
        assertEq(marketMakerManager.paused(), true);

        vm.prank(mm);
        marketMakerManager.unpause();
        assertEq(marketMakerManager.paused(), false);
    }

    function test_MarketMakerManager_pause_notOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        marketMakerManager.pause();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        marketMakerManager.unpause();
    }
}
