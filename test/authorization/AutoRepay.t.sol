// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AutoRepay} from "src/authorization/AutoRepay.sol";
import {Authorization, Action} from "@size/src/factory/libraries/Authorization.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {RESERVED_ID, DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {LoanStatus} from "@size/src/market/libraries/LoanLibrary.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SwapParams, SwapMethod, OneInchParams} from "src/liquidator/DexSwap.sol";
import {console} from "forge-std/console.sol";
import {Addresses, CONTRACT} from "script/Addresses.s.sol";

contract AutoRepayTest is BaseTest, Addresses {
    MockAavePool public mockAavePool;
    Mock1InchAggregator public mock1InchAggregator;
    AutoRepay public autoRepay;
    AutoRepay public autoRepayImplementation;

    uint256 private _initialEarlyRepaymentBuffer = 1 hours;

    // Add error selector constant
    bytes4 constant OWNER_ONLY = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));

    function setUp() public override {
        super.setUp();

        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));

        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 100_000e6);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 100_000e6);

        vm.warp(block.timestamp + 123 days);

        // Deploy implementation and proxy
        autoRepayImplementation = new AutoRepay();
        bytes memory initData = abi.encodeWithSelector(
            AutoRepay.initialize.selector,
            james,
            IPoolAddressesProvider(address(mockAavePool)),
            _initialEarlyRepaymentBuffer
        );
        autoRepay = AutoRepay(address(new ERC1967Proxy(address(autoRepayImplementation), initData)));
    }

    function test_AutoRepay_initialState() public view {
        assertEq(autoRepay.owner(), james);
        assertEq(autoRepay.earlyRepaymentBuffer(), _initialEarlyRepaymentBuffer);
    }

    function test_AutoRepay_setEarlyRepaymentBuffer() public {
        uint256 newBuffer = 2 hours;

        // Test unauthorized access
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(OWNER_ONLY, candy));
        autoRepay.setEarlyRepaymentBuffer(newBuffer);

        // Test setting to zero
        vm.prank(james);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        autoRepay.setEarlyRepaymentBuffer(0);

        // Test successful update
        vm.prank(james);
        autoRepay.setEarlyRepaymentBuffer(newBuffer);
        assertEq(autoRepay.earlyRepaymentBuffer(), newBuffer);
    }

    function test_AutoRepay_initialize_reverts() public {
        // Test initializing implementation directly
        vm.expectRevert(); // Expect any revert
        autoRepayImplementation.initialize(
            james, IPoolAddressesProvider(address(mockAavePool)), _initialEarlyRepaymentBuffer
        );

        // Test initializing proxy again
        vm.expectRevert(); // Expect any revert
        autoRepay.initialize(james, IPoolAddressesProvider(address(mockAavePool)), _initialEarlyRepaymentBuffer);
    }

    function test_AutoRepay_initialize_invalidParams() public {
        // Test initializing with zero address provider
        bytes memory initData =
            abi.encodeWithSelector(AutoRepay.initialize.selector, james, address(0), _initialEarlyRepaymentBuffer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        new ERC1967Proxy(address(autoRepayImplementation), initData);

        // Test initializing with zero early repayment buffer
        initData = abi.encodeWithSelector(
            AutoRepay.initialize.selector, james, IPoolAddressesProvider(address(mockAavePool)), 0
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        new ERC1967Proxy(address(autoRepayImplementation), initData);
    }

    function _setupLoan(uint256 amount, uint256 tenor) private returns (uint256 debtPositionId) {
        console.log("\n=== Setting up loan ===");
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 100e18);
        console.log("Initial WETH Balance (Bob):", weth.balanceOf(bob));
        console.log("Initial USDC Balance (Bob):", usdc.balanceOf(bob));

        _buyCreditLimit(
            alice,
            block.timestamp + 5 * tenor,
            YieldCurveHelper.customCurve(tenor, uint256(0.03e18), 2 * tenor, uint256(0.05e18))
        );

        debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, tenor, false);
        console.log("Debt Position ID:", debtPositionId);

        _withdraw(bob, address(usdc), type(uint256).max);
        console.log("After withdraw - WETH Balance (Bob):", weth.balanceOf(bob));
        console.log("After withdraw - USDC Balance (Bob):", usdc.balanceOf(bob));

        Action[] memory actions = new Action[](2);
        actions[0] = Action.DEPOSIT;
        actions[1] = Action.WITHDRAW;
        _setAuthorization(bob, address(autoRepay), Authorization.getActionsBitmap(actions));
        console.log("Authorization set for AutoRepay");

        // Set allowances
        _approve(bob, address(weth), address(autoRepay), type(uint256).max);
        _approve(bob, address(usdc), address(autoRepay), type(uint256).max);
        console.log("Allowances set for AutoRepay");
        console.log("WETH Allowance (Bob -> AutoRepay):", weth.allowance(bob, address(autoRepay)));
        console.log("USDC Allowance (Bob -> AutoRepay):", usdc.allowance(bob, address(autoRepay)));

        return debtPositionId;
    }

    function test_AutoRepay_repayWithCollateral_too_early() public {
        uint256 amount = 100e6;
        uint256 tenor = 365 days;
        uint256 debtPositionId = _setupLoan(amount, tenor);

        // Try to repay too early
        vm.prank(james);
        vm.expectRevert(
            abi.encodeWithSelector(
                PeripheryErrors.AUTO_REPAY_TOO_EARLY.selector, block.timestamp + tenor, block.timestamp
            )
        );
        autoRepay.repayWithCollateral(size, debtPositionId, bob, amount, new SwapParams[](0));

        // Verify loan state unchanged
        Vars memory _after = _state();
        assertEq(_after.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue);
    }

    function test_AutoRepay_repayWithCollateral_unauthorized() public {
        uint256 amount = 100e6;
        uint256 tenor = 365 days;
        uint256 debtPositionId = _setupLoan(amount, tenor);

        // Try to repay without authorization
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(OWNER_ONLY, candy));
        autoRepay.repayWithCollateral(size, debtPositionId, bob, amount, new SwapParams[](0));
    }

    function test_AutoRepay_repayWithCollateral_zeroAmount() public {
        uint256 amount = 100e6;
        uint256 tenor = 365 days;
        uint256 debtPositionId = _setupLoan(amount, tenor);

        // Try to repay with zero collateral amount
        vm.prank(james);
        vm.expectRevert();
        autoRepay.repayWithCollateral(size, debtPositionId, bob, 0, new SwapParams[](0));
    }

    function test_AutoRepay_repayWithCollateral_early() public {
        uint256 amount = 100e6;
        uint256 tenor = 365 days;
        uint256 debtPositionId = _setupLoan(amount, tenor);

        // Setup mock swap params
        SwapParams[] memory swapParams = new SwapParams[](1);
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(weth),
            toToken: address(usdc),
            minReturn: 0,
            data: "",
            router: address(mock1InchAggregator)
        });
        swapParams[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Log initial state
        console.log("=== Initial State ===");
        console.log("Debt Position ID:", debtPositionId);
        console.log("Debt Amount:", amount);
        console.log("WETH Balance (Bob):", weth.balanceOf(bob));
        console.log("USDC Balance (Bob):", usdc.balanceOf(bob));
        console.log("WETH Allowance (Bob -> AutoRepay):", weth.allowance(bob, address(autoRepay)));
        console.log("USDC Allowance (Bob -> AutoRepay):", usdc.allowance(bob, address(autoRepay)));

        // Get debt position details
        DebtPosition memory debtPosition = size.getDebtPosition(debtPositionId);
        console.log("Debt Position Future Value:", debtPosition.futureValue);
        console.log("Debt Position Due Date:", debtPosition.dueDate);

        // Warp to just before due date
        vm.warp(block.timestamp + tenor - 30 minutes);
        console.log("\n=== After Warp ===");
        console.log("Current Timestamp:", block.timestamp);
        console.log("Loan Status:", uint256(size.getLoanStatus(debtPositionId)));

        // Execute repay
        vm.prank(james);
        console.log("\n=== Executing Repay ===");
        autoRepay.repayWithCollateral(size, debtPositionId, bob, amount, swapParams);

        // Log final state
        console.log("\n=== Final State ===");
        Vars memory _after = _state();
        console.log("Bob's Debt Balance:", _after.bob.debtBalance);
        console.log("Bob's Borrow AToken Balance:", _after.bob.borrowATokenBalance);
        console.log("Bob's Collateral Balance:", _after.bob.collateralTokenBalance);
        console.log("WETH Balance (Bob):", weth.balanceOf(bob));
        console.log("USDC Balance (Bob):", usdc.balanceOf(bob));
        console.log("WETH Balance (AutoRepay):", weth.balanceOf(address(autoRepay)));
        console.log("USDC Balance (AutoRepay):", usdc.balanceOf(address(autoRepay)));

        // Verify loan repaid
        assertEq(_after.bob.debtBalance, 0);
    }

    function test_AutoRepay_repayWithCollateral_overdue() public {
        uint256 amount = 100e6;
        uint256 tenor = 365 days;
        uint256 debtPositionId = _setupLoan(amount, tenor);

        // Setup mock swap params
        SwapParams[] memory swapParams = new SwapParams[](1);
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(weth),
            toToken: address(usdc),
            minReturn: 0,
            data: "",
            router: address(mock1InchAggregator)
        });
        swapParams[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Log initial state
        console.log("=== Initial State ===");
        console.log("Debt Position ID:", debtPositionId);
        console.log("Debt Amount:", amount);
        console.log("WETH Balance (Bob):", weth.balanceOf(bob));
        console.log("USDC Balance (Bob):", usdc.balanceOf(bob));
        console.log("WETH Allowance (Bob -> AutoRepay):", weth.allowance(bob, address(autoRepay)));
        console.log("USDC Allowance (Bob -> AutoRepay):", usdc.allowance(bob, address(autoRepay)));

        // Get debt position details
        DebtPosition memory debtPosition = size.getDebtPosition(debtPositionId);
        console.log("Debt Position Future Value:", debtPosition.futureValue);
        console.log("Debt Position Due Date:", debtPosition.dueDate);

        // Warp to after due date
        vm.warp(block.timestamp + tenor + 1 hours);
        console.log("\n=== After Warp ===");
        console.log("Current Timestamp:", block.timestamp);
        console.log("Loan Status:", uint256(size.getLoanStatus(debtPositionId)));

        // Execute repay
        vm.prank(james);
        console.log("\n=== Executing Repay ===");
        autoRepay.repayWithCollateral(size, debtPositionId, bob, amount, swapParams);

        // Log final state
        console.log("\n=== Final State ===");
        Vars memory _after = _state();
        console.log("Bob's Debt Balance:", _after.bob.debtBalance);
        console.log("Bob's Borrow AToken Balance:", _after.bob.borrowATokenBalance);
        console.log("Bob's Collateral Balance:", _after.bob.collateralTokenBalance);
        console.log("WETH Balance (Bob):", weth.balanceOf(bob));
        console.log("USDC Balance (Bob):", usdc.balanceOf(bob));
        console.log("WETH Balance (AutoRepay):", weth.balanceOf(address(autoRepay)));
        console.log("USDC Balance (AutoRepay):", usdc.balanceOf(address(autoRepay)));

        // Verify loan repaid
        assertEq(_after.bob.debtBalance, 0);
    }

    function test_AutoRepay_repayWithCollateral_insufficientCollateral() public {
        uint256 amount = 100e6;
        uint256 tenor = 365 days;
        uint256 debtPositionId = _setupLoan(amount, tenor);

        // Setup mock swap params
        SwapParams[] memory swapParams = new SwapParams[](1);
        swapParams[0] =
            SwapParams({method: SwapMethod.GenericRoute, data: abi.encode(address(0), address(0), bytes(""))});

        // Try to repay with more collateral than available
        vm.prank(james);
        vm.expectRevert(); // Expect revert from withdraw
        autoRepay.repayWithCollateral(
            size,
            debtPositionId,
            bob,
            amount * 2, // Try to withdraw 2x the amount
            swapParams
        );
    }
}
