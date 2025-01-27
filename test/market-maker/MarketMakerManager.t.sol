// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseTest} from "@size/test/BaseTest.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MarketMakerManager} from "src/MarketMakerManager.sol";
import {MarketMakerManagerV2} from "test/mocks/MarketMakerManagerV2.sol";
import {
    DepositParams, WithdrawParams, BuyCreditLimitParams, SellCreditLimitParams
} from "@size/src/interfaces/ISize.sol";
import {UpdateConfigParams} from "@size/src/libraries/actions/UpdateConfig.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";
import {YieldCurve} from "@size/src/libraries/YieldCurveLibrary.sol";
import {MarketMakerManagerFactory} from "src/MarketMakerManagerFactory.sol";
import {MarketMakerManagerFactoryV2} from "test/mocks/MarketMakerManagerFactoryV2.sol";
import {ISizeFactory} from "@size/src/v1.5/interfaces/ISizeFactory.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {PAUSER_ROLE} from "@size/src/Size.sol";

contract MarketMakerManagerTest is BaseTest {
    address public governance;
    address public bot;
    address public mm;
    MarketMakerManagerFactory public factory;
    MarketMakerManager public marketMakerManager;

    function setUp() public override {
        super.setUp();

        governance = makeAddr("governance");
        mm = makeAddr("mm");
        bot = makeAddr("bot");

        factory = MarketMakerManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new MarketMakerManagerFactory()),
                    abi.encodeCall(MarketMakerManagerFactory.initialize, (governance, bot))
                )
            )
        );
        marketMakerManager = factory.createMarketMakerManager(mm);

        vm.prank(governance);
        factory.setSizeFactory(ISizeFactory(sizeFactory));
    }

    function test_MarketMakerManager_initialize() public view {
        assertEq(marketMakerManager.owner(), mm);
        assertEq(factory.bot(), bot);
    }

    function test_MarketMakerManager_upgradeBeacon_onlyOwner() public {
        vm.expectRevert();
        MarketMakerManagerV2(address(marketMakerManager)).version();

        address newImplementation = address(new MarketMakerManagerV2());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bot));
        vm.prank(bot);
        factory.upgradeBeacon(newImplementation);

        vm.prank(governance);
        factory.upgradeBeacon(newImplementation);

        assertEq(MarketMakerManagerV2(address(marketMakerManager)).version(), 2);
    }

    function test_MarketMakerManagerFactory_upgrade_onlyOwner() public {
        vm.expectRevert();
        MarketMakerManagerFactoryV2(address(factory)).version();

        address newImplementation = address(new MarketMakerManagerFactoryV2());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bot));
        vm.prank(bot);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(newImplementation, "");

        vm.prank(governance);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(newImplementation, "");

        assertEq(MarketMakerManagerFactoryV2(address(factory)).version(), 2);
    }

    function test_MarketMakerManager_setBot() public {
        address newBot = makeAddr("newBot");
        vm.prank(governance);
        factory.setBot(newBot);
        assertEq(factory.bot(), newBot);
    }

    function test_MarketMakerManager_setBot_onlyOwner() public {
        address newBot = makeAddr("newBot");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.setBot(newBot);
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

    function test_MarketMakerManager_depositDirect() public {
        uint256 amount = 100e6;
        usdc.mint(mm, amount);
        vm.prank(mm);

        uint256 balanceBefore = size.getUserView(address(marketMakerManager)).borrowATokenBalance;

        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), amount);
        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, amount);

        uint256 balanceAfter = size.getUserView(address(marketMakerManager)).borrowATokenBalance;
        assertEq(balanceAfter, balanceBefore + amount);
    }

    function test_MarketMakerManager_deposit_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        marketMakerManager.deposit(size, usdc, 100e6);
    }

    function test_MarketMakerManager_deposit_withdraw() public {
        uint256 amount = 100e6;
        usdc.mint(mm, amount);

        vm.prank(mm);
        usdc.approve(address(marketMakerManager), amount);
        vm.prank(mm);
        marketMakerManager.deposit(size, usdc, amount);

        uint256 amount2 = 30e6;
        uint256 balanceBefore = usdc.balanceOf(mm);

        vm.prank(mm);
        marketMakerManager.withdraw(size, usdc, amount2);

        uint256 balanceAfter = usdc.balanceOf(mm);
        uint256 balanceAfterSize = size.getUserView(address(marketMakerManager)).borrowATokenBalance;
        assertEq(balanceAfter, balanceBefore + amount2);
        assertEq(balanceAfterSize, amount - amount2, balanceAfterSize);
    }

    function test_MarketMakerManager_depositDirect_withdraw() public {
        uint256 amount = 100e6;
        usdc.mint(mm, amount);

        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), amount);
        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, amount);

        uint256 amount2 = 30e6;
        uint256 balanceBefore = usdc.balanceOf(mm);

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

    function test_MarketMakerManager_buyCreditLimit_onlyBotWhenNotPausedOrOwner() public {
        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBotWhenNotPausedOrOwner.selector));
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

    function test_MarketMakerManager_sellCreditLimit_onlyBotWhenNotPausedOrOwner() public {
        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBotWhenNotPausedOrOwner.selector));
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

    function test_MarketMakerManager_validateCurvesIsBelow_whenCurvesIntersect_1() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.flatCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.normalCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, params);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.InvalidCurves.selector));
        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);
    }

    function test_MarketMakerManager_validateCurvesIsBelow_whenCurvesIntersect_2() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.flatCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.normalCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.InvalidCurves.selector));
        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, params);
    }

    function test_MarketMakerManager_validateCurvesIsBelow_whenCurvesIsNotBelow() public {
        YieldCurve memory borrowCurve = YieldCurveHelper.negativeCurve();
        YieldCurve memory loanCurve = YieldCurveHelper.humpedCurve();

        BuyCreditLimitParams memory params =
            BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: loanCurve});
        SellCreditLimitParams memory params2 =
            SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: borrowCurve});

        vm.prank(bot);
        marketMakerManager.sellCreditLimit(size, params2);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.InvalidCurves.selector));
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
        vm.prank(governance);
        factory.pause();
        assertEq(factory.paused(), true);

        vm.prank(governance);
        factory.unpause();
        assertEq(factory.paused(), false);
    }

    function test_MarketMakerManager_pause_notOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.pause();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.unpause();
    }

    function test_MarketMakerManager_paused_owner_can_still_perform_all_actions() public {
        vm.prank(governance);
        factory.pause();

        YieldCurve memory curve = YieldCurveHelper.normalCurve();

        usdc.mint(mm, 100e6);
        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), 100e6);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBotWhenNotPausedOrOwner.selector));
        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, 100e6);

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBotWhenNotPausedOrOwner.selector));
        vm.prank(bot);
        marketMakerManager.buyCreditLimit(
            size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );

        vm.prank(mm);
        marketMakerManager.depositDirect(size, usdc, 100e6);

        vm.prank(mm);
        marketMakerManager.withdraw(size, usdc, 100e6);

        vm.prank(mm);
        marketMakerManager.buyCreditLimit(
            size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );
    }

    function test_MarketMakerManager_multiple_instances() public {
        address mm2 = makeAddr("mm2");
        MarketMakerManager marketMakerManager2 = factory.createMarketMakerManager(mm2);
        assertEq(marketMakerManager2.owner(), mm2);
        assertEq(address(marketMakerManager2.factory()), address(factory));

        YieldCurve memory curve = YieldCurveHelper.normalCurve();
        YieldCurve memory curve2 = YieldCurveHelper.flatCurve();

        vm.prank(bot);
        marketMakerManager.buyCreditLimit(
            size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );

        vm.prank(bot);
        marketMakerManager2.sellCreditLimit(
            size, SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve})
        );

        vm.prank(governance);
        factory.pause();

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBotWhenNotPausedOrOwner.selector));
        vm.prank(bot);
        marketMakerManager.buyCreditLimit(
            size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve2})
        );

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyBotWhenNotPausedOrOwner.selector));
        vm.prank(bot);
        marketMakerManager2.sellCreditLimit(
            size, SellCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: curve2})
        );
    }

    function test_MarketMakerManager_emergencyWithdraw_withdrawer() public {
        usdc.mint(mm, 100e6);
        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), 100e6);

        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, 90e6);

        address withdrawer = makeAddr("withdrawer");
        vm.prank(governance);
        factory.setEmergencyWithdrawer(withdrawer, true);

        uint256 balanceBefore = usdc.balanceOf(mm);

        vm.prank(withdrawer);
        marketMakerManager.emergencyWithdraw();

        uint256 balanceAfter = usdc.balanceOf(mm);
        assertEq(balanceAfter, balanceBefore + 100e6);
    }

    function test_MarketMakerManager_emergencyWithdraw_owner() public {
        usdc.mint(mm, 100e6);
        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), 100e6);

        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, 90e6);

        uint256 balanceBefore = usdc.balanceOf(mm);

        vm.prank(mm);
        marketMakerManager.emergencyWithdraw();

        uint256 balanceAfter = usdc.balanceOf(mm);
        assertEq(balanceAfter, balanceBefore + 100e6);
    }

    function test_MarketMakerManager_emergencyWithdraw_onlyEmergencyWithdrawerOrOwner() public {
        address notEmergencyWithdrawer = makeAddr("notEmergencyWithdrawer");
        address emergencyWithdrawer = makeAddr("emergencyWithdrawer");

        vm.expectRevert(abi.encodeWithSelector(MarketMakerManager.OnlyEmergencyWithdrawerOrOwner.selector));
        vm.prank(notEmergencyWithdrawer);
        marketMakerManager.emergencyWithdraw();

        vm.prank(governance);
        factory.setEmergencyWithdrawer(emergencyWithdrawer, true);

        vm.prank(emergencyWithdrawer);
        marketMakerManager.emergencyWithdraw();

        vm.prank(mm);
        marketMakerManager.emergencyWithdraw();

        assertTrue(factory.isEmergencyWithdrawer(emergencyWithdrawer));
        assertEq(factory.getEmergencyWithdrawers()[0], emergencyWithdrawer);

        vm.prank(governance);
        factory.setEmergencyWithdrawer(emergencyWithdrawer, false);
        assertFalse(factory.isEmergencyWithdrawer(emergencyWithdrawer));
    }

    function test_MarketMakerManager_emergencyWithdraw_one_market_paused_does_not_stop_process() public {
        ISize market1 = ISize(size);
        sizeFactory.createMarket(f, r, o, d);

        usdc.mint(mm, 100e6);
        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), 100e6);

        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, 90e6);

        market1.pause();

        vm.prank(mm);
        marketMakerManager.emergencyWithdraw();
    }

    function test_MarketMakerManager_emergencyWithdraw_single_token_borrow_token() public {
        d.borrowATokenV1_5 = address(sizeFactory.createBorrowATokenV1_5(variablePool, IERC20Metadata(address(weth))));
        d.underlyingBorrowToken = address(weth);
        sizeFactory.createMarket(f, r, o, d);

        usdc.mint(mm, 100e6);
        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), 100e6);

        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, 90e6);

        vm.prank(mm);
        marketMakerManager.emergencyWithdraw(IERC20Metadata(address(usdc)));
    }

    function test_MarketMakerManager_emergencyWithdraw_single_token_collateral_token() public {
        deal(mm, 100 ether);
        vm.prank(mm);
        weth.deposit{value: 100 ether}();

        vm.prank(mm);
        weth.transfer(address(marketMakerManager), 100 ether);

        vm.prank(bot);
        marketMakerManager.depositDirect(size, weth, 90 ether);

        vm.prank(mm);
        marketMakerManager.emergencyWithdraw(IERC20Metadata(address(weth)));
    }

    function test_MarketMakerManager_recoverTokens() public {
        usdc.mint(address(marketMakerManager), 123e6);

        vm.prank(mm);
        marketMakerManager.recoverTokens(usdc);

        assertEq(usdc.balanceOf(mm), 123e6);
    }

    function test_MarketMakerManager_emergencyWithdraw_all_tokens_when_paused() public {
        usdc.mint(mm, 100e6);
        vm.prank(mm);
        usdc.transfer(address(marketMakerManager), 100e6);

        vm.prank(bot);
        marketMakerManager.depositDirect(size, usdc, 90e6);

        size.pause();
        AccessControlUpgradeable(address(size)).grantRole(PAUSER_ROLE, address(marketMakerManager));

        vm.prank(mm);
        marketMakerManager.emergencyWithdraw();
    }
}
