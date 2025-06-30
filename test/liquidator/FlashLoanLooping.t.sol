// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SwapMethod, SwapParams, OneInchParams} from "src/liquidator/DexSwap.sol";
import {FlashLoanLooping} from "src/liquidator/FlashLoanLooping.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";

import {BaseTest, Vars} from "@size/test/BaseTest.sol";

import {DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";

import {console} from "forge-std/console.sol";

contract FlashLoanLoopingTest is BaseTest {
    MockAavePool public mockAavePool;
    Mock1InchAggregator public mock1InchAggregator;
    FlashLoanLooping public flashLoanLooping;

    function setUp() public override {
        super.setUp();
        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));

        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 100_000e18);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 100_000e6);

        // Initialize the FlashLoanLooping contract
        flashLoanLooping = new FlashLoanLooping(
            address(mockAavePool),
            address(mock1InchAggregator),
            address(1), // placeholder for the unoswap router
            address(1), // placeholder for the uniswapv2 aggregator
            address(1) // placeholder for the uniswapv3 router
        );
    }

    /// @notice Calculate the flash loan amount needed to achieve a target LTV
    /// @param initialCollateralValue The value of initial collateral in USDC terms
    /// @param targetLTV The target LTV in basis points (e.g., 877 for 87.7%)
    /// @return flashLoanAmount The amount to flash loan to achieve the target LTV
    function calculateFlashLoanAmount(uint256 initialCollateralValue, uint256 targetLTV) public pure returns (uint256 flashLoanAmount) {
        // Formula: D = TargetLTV * C / (1 - TargetLTV)
        // Where D = flash loan amount, C = initial collateral value
        // targetLTV is in basis points (e.g., 877 for 87.7%)
        flashLoanAmount = (targetLTV * initialCollateralValue) / (1000 - targetLTV);
    }

    function test_FlashLoanLooping_basic_loop_with_target_LTV() public {
        // Setup initial state
        _setPrice(1e18);

        // Alice deposits USDC to lend
        _deposit(alice, usdc, 1000e6);
        
        // Alice creates a borrow offer
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // Bob has 100 USD worth of WETH as initial collateral
        uint256 initialCollateral = 100e18; // 100 WETH = 100 USD worth
        _mint(address(weth), bob, initialCollateral);
        _approve(bob, address(weth), address(size), initialCollateral);
        
        // Bob deposits his initial collateral to Size
        vm.prank(bob);
        size.deposit(DepositParams({token: address(weth), amount: initialCollateral, to: bob}));

        // Log initial state
        Vars memory initialState = _state();
        console.log("=== INITIAL STATE ===");
        console.log("Bob's WETH balance:", initialState.bob.collateralTokenBalance);
        console.log("Bob's USDC balance:", initialState.bob.borrowATokenBalance);
        console.log("Bob's debt balance:", initialState.bob.debtBalance);
        console.log("Alice's USDC balance:", initialState.alice.borrowATokenBalance);
        
        // Calculate collateral ratio before looping
        uint256 collateralValue = initialState.bob.collateralTokenBalance; // WETH balance
        uint256 debtValue = initialState.bob.debtBalance; // USDC debt
        uint256 collateralRatio = debtValue == 0 ? type(uint256).max : (collateralValue * 1e18) / debtValue;
        console.log("Initial collateral ratio:", collateralRatio);

        // Bob wants to achieve a target LTV of 0.877 (87.7%)
        uint256 targetLTV = 877; // 0.877 * 1000 for precision (87.7%)
        uint256 initialCollateralValue = 100e6; // 100 USD in USDC terms
        
        // Calculate flash loan amount using the formula
        uint256 calculatedFlashLoanAmount = calculateFlashLoanAmount(initialCollateralValue, targetLTV);
        console.log("Calculated flash loan amount:", calculatedFlashLoanAmount);
        
        // For the test, let's use a more realistic amount: 669 USDC as mentioned in the example
        uint256 flashLoanAmount = 669e6; // 669 USDC

        uint256 tenor = 365 days;
        uint256 maxAPR = 0.05e18; // 5% max APR

        // Create swap params to convert USDC to WETH
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({
            method: SwapMethod.OneInch,
            data: abi.encode(oneInchParams)
        });

        Vars memory _before = _state();

        // Execute the loop
        vm.prank(bob);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth), // collateral token
            address(usdc), // borrow token
            flashLoanAmount,
            tenor,
            maxAPR,
            alice, // lender
            swapParamsArray,
            address(0) // recipient (address(0) means transfer profits to msg.sender)
        );

        Vars memory _after = _state();

        // Log final state
        console.log("=== FINAL STATE ===");
        console.log("Bob's WETH balance:", _after.bob.collateralTokenBalance);
        console.log("Bob's USDC balance:", _after.bob.borrowATokenBalance);
        console.log("Bob's debt balance:", _after.bob.debtBalance);
        console.log("Alice's USDC balance:", _after.alice.borrowATokenBalance);
        
        // Calculate final collateral ratio
        uint256 finalCollateralValue = _after.bob.collateralTokenBalance;
        uint256 finalDebtValue = _after.bob.debtBalance;
        uint256 finalCollateralRatio = finalDebtValue == 0 ? type(uint256).max : (finalCollateralValue * 1e18) / finalDebtValue;
        console.log("Final collateral ratio:", finalCollateralRatio);

        // Verify the loop worked correctly
        // Bob should have borrowed USDC and deposited additional WETH as collateral
        assertGt(_after.bob.debtBalance, _before.bob.debtBalance, "Bob should have debt after looping");
        assertGt(_after.bob.collateralTokenBalance, _before.bob.collateralTokenBalance, "Bob should have more collateral after looping");
        
        // Alice should have lent USDC
        assertLt(_after.alice.borrowATokenBalance, _before.alice.borrowATokenBalance, "Alice should have lent USDC");

        // Calculate the actual LTV achieved
        uint256 totalCollateralValue = _after.bob.collateralTokenBalance; // WETH balance
        uint256 totalDebtValue = _after.bob.debtBalance; // USDC debt
        uint256 actualLTV = (totalDebtValue * 1000) / totalCollateralValue; // In basis points
        
        console.log("Initial collateral:", initialCollateral);
        console.log("Flash loan amount:", flashLoanAmount);
        console.log("Calculated flash loan amount:", calculatedFlashLoanAmount);
        console.log("Final collateral:", _after.bob.collateralTokenBalance);
        console.log("Final debt:", _after.bob.debtBalance);
        console.log("Target LTV (basis points):", targetLTV);
        console.log("Actual LTV (basis points):", actualLTV);
        
        // The actual LTV should be close to the target LTV (allowing for some precision loss)
        assertApproxEqRel(actualLTV, targetLTV, 0.01e18, "LTV should be close to target");
    }

    function test_FlashLoanLooping_with_deposit_profits() public {
        // Setup initial state
        _setPrice(1e18);

        _deposit(alice, usdc, 1000e6);
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // Bob has 100 USD worth of WETH as initial collateral
        uint256 initialCollateral = 100e18;
        _mint(address(weth), bob, initialCollateral);
        _approve(bob, address(weth), address(size), initialCollateral);
        
        vm.prank(bob);
        size.deposit(DepositParams({token: address(weth), amount: initialCollateral, to: bob}));

        // Log initial state
        Vars memory initialState = _state();
        console.log("=== INITIAL STATE (DEPOSIT PROFITS) ===");
        console.log("Bob's WETH balance:", initialState.bob.collateralTokenBalance);
        console.log("Bob's USDC balance:", initialState.bob.borrowATokenBalance);
        console.log("Bob's debt balance:", initialState.bob.debtBalance);
        console.log("Alice's USDC balance:", initialState.alice.borrowATokenBalance);
        
        // Calculate collateral ratio before looping
        uint256 collateralValue = initialState.bob.collateralTokenBalance;
        uint256 debtValue = initialState.bob.debtBalance;
        uint256 collateralRatio = debtValue == 0 ? type(uint256).max : (collateralValue * 1e18) / debtValue;
        console.log("Initial collateral ratio:", collateralRatio);

        // Target LTV of 0.877
        uint256 targetLTV = 877;
        uint256 initialCollateralValue = 100e6;
        uint256 flashLoanAmount = calculateFlashLoanAmount(initialCollateralValue, targetLTV);
        flashLoanAmount = 669e6; // Use the example amount

        uint256 tenor = 365 days;
        uint256 maxAPR = 0.05e18;

        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({
            method: SwapMethod.OneInch,
            data: abi.encode(oneInchParams)
        });

        Vars memory _before = _state();

        // Execute the loop with depositProfits = true
        vm.prank(bob);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            flashLoanAmount,
            tenor,
            maxAPR,
            alice,
            swapParamsArray,
            bob // recipient (non-zero means deposit profits to Size)
        );

        Vars memory _after = _state();

        // Log final state
        console.log("=== FINAL STATE (DEPOSIT PROFITS) ===");
        console.log("Bob's WETH balance:", _after.bob.collateralTokenBalance);
        console.log("Bob's USDC balance:", _after.bob.borrowATokenBalance);
        console.log("Bob's debt balance:", _after.bob.debtBalance);
        console.log("Alice's USDC balance:", _after.alice.borrowATokenBalance);
        
        // Calculate final collateral ratio
        uint256 finalCollateralValue = _after.bob.collateralTokenBalance;
        uint256 finalDebtValue = _after.bob.debtBalance;
        uint256 finalCollateralRatio = finalDebtValue == 0 ? type(uint256).max : (finalCollateralValue * 1e18) / finalDebtValue;
        console.log("Final collateral ratio:", finalCollateralRatio);

        // Verify the loop worked and profits were deposited
        assertGt(_after.bob.debtBalance, _before.bob.debtBalance, "Bob should have debt after looping");
        assertGt(_after.bob.collateralTokenBalance, _before.bob.collateralTokenBalance, "Bob should have more collateral after looping");
        
        // Bob should have additional USDC deposited from profits
        assertGt(_after.bob.borrowATokenBalance, _before.bob.borrowATokenBalance, "Bob should have profits deposited");
    }

    function test_FlashLoanLooping_revert_insufficient_balance() public {
        // Setup with insufficient liquidity
        _setPrice(1e18);
        _deposit(alice, usdc, 10e6); // Only 10 USDC available
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // Bob has initial collateral
        uint256 initialCollateral = 100e18;
        _mint(address(weth), bob, initialCollateral);
        _approve(bob, address(weth), address(size), initialCollateral);
        
        vm.prank(bob);
        size.deposit(DepositParams({token: address(weth), amount: initialCollateral, to: bob}));

        uint256 flashLoanAmount = 669e6; // Try to flash loan 669 USDC
        uint256 tenor = 365 days;
        uint256 maxAPR = 0.05e18;

        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({
            method: SwapMethod.OneInch,
            data: abi.encode(oneInchParams)
        });

        // This should revert due to insufficient balance
        vm.prank(bob);
        vm.expectRevert();
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            flashLoanAmount,
            tenor,
            maxAPR,
            alice,
            swapParamsArray,
            address(0)
        );
    }

    function test_FlashLoanLooping_LTV_calculation_formula() public {
        // Test the LTV calculation formula: D = TargetLTV * C / (1 - TargetLTV)
        
        // Example 1: 100 USD collateral, 87.7% target LTV
        uint256 collateral = 100e6; // 100 USD
        uint256 targetLTV = 877; // 87.7% in basis points
        uint256 expectedFlashLoan = calculateFlashLoanAmount(collateral, targetLTV);
        // Calculate manually: (877 * 100e6) / 123 = 87700000000 / 123 ≈ 713,008 USDC
        uint256 expectedFlashLoanExact = 713008130; // Pre-calculated value
        
        console.log("Example 1:");
        console.log("Collateral:", collateral);
        console.log("Target LTV (basis points):", targetLTV);
        console.log("Expected flash loan:", expectedFlashLoan);
        console.log("Expected flash loan exact:", expectedFlashLoanExact);
        
        // Example 2: 50 USD collateral, 80% target LTV
        collateral = 50e6; // 50 USD
        targetLTV = 800; // 80% in basis points
        expectedFlashLoan = calculateFlashLoanAmount(collateral, targetLTV);
        // Calculate manually: (800 * 50e6) / 200 = 40000000000 / 200 = 200,000,000 = 200 USDC
        expectedFlashLoanExact = 200e6; // 200 USDC
        
        console.log("Example 2:");
        console.log("Collateral:", collateral);
        console.log("Target LTV (basis points):", targetLTV);
        console.log("Expected flash loan:", expectedFlashLoan);
        console.log("Expected flash loan exact:", expectedFlashLoanExact);
        
        // Example 3: 200 USD collateral, 90% target LTV
        collateral = 200e6; // 200 USD
        targetLTV = 900; // 90% in basis points
        expectedFlashLoan = calculateFlashLoanAmount(collateral, targetLTV);
        // Calculate manually: (900 * 200e6) / 100 = 180000000000 / 100 = 1,800,000,000 = 1800 USDC
        expectedFlashLoanExact = 1800e6; // 1800 USDC
        
        console.log("Example 3:");
        console.log("Collateral:", collateral);
        console.log("Target LTV (basis points):", targetLTV);
        console.log("Expected flash loan:", expectedFlashLoan);
        console.log("Expected flash loan exact:", expectedFlashLoanExact);
    }

    function test_FlashLoanLooping_description() public {
        string memory desc = flashLoanLooping.description();
        assertEq(desc, "FlashLoanLooping (DexSwap takes SwapParams[] as input)");
    }
} 