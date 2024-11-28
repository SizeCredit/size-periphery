// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MarketMakerManager} from "src/market-maker/MarketMakerManager.sol";
import {DepositParams, WithdrawParams, BuyCreditLimitParams} from "@size/src/interfaces/ISize.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";

contract MarketMakerManagerTest is BaseTest {
    address public bot;
    address public mm;
    MarketMakerManager public marketMakerManager;

    function setUp() public override {
        super.setUp();

        mm = makeAddr("mm");
        bot = makeAddr("bot");

        marketMakerManager = MarketMakerManager(
            payable(new ERC1967Proxy(
                payable(new MarketMakerManager()),
                abi.encodeCall(MarketMakerManager.initialize, (mm, bot))
            ))
        );
    }

    function test_MarketMakerManager_initialize() public {
        assertEq(marketMakerManager.owner(), mm);
        assertEq(marketMakerManager.bot(), bot);
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
        assertEq(balanceAfter , balanceBefore + amount);
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
        vm.prank(bot);
        marketMakerManager.buyCreditLimit(size, BuyCreditLimitParams({maxDueDate: block.timestamp + 365 days, curveRelativeTime: YieldCurveHelper.normalCurve()}));
    }
}
