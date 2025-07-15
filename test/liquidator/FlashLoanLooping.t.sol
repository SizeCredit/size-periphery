// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SwapMethod, SwapParams, OneInchParams} from "src/liquidator/DexSwap.sol";
import {FlashLoanLooping} from "src/zaps/FlashLoanLooping.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";

import {BaseTest, Vars} from "@size/test/BaseTest.sol";

import {DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {Action, Authorization} from "@size/src/factory/libraries/Authorization.sol";
import {SellCreditMarketParams} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {Math, PERCENT} from "@size/src/market/libraries/Math.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";

import {console} from "forge-std/console.sol";

contract FlashLoanLoopingTest is BaseTest {
    MockAavePool public mockAavePool;
    Mock1InchAggregator public mock1InchAggregator;
    FlashLoanLooping public flashLoanLooping;
    address carol;

    function setUp() public override {
        super.setUp();
        
        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));
        carol = makeAddr("carol");

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

    function test_FlashLoanLooping_user_loop_with_authorization() public {
        console.log("=== test_FlashLoanLooping_user_loop_with_authorization ===");
        console.log("alice address:", alice);
        console.log("bob address:", bob);
        console.log("carol address:", carol);
        console.log("flashLoanLooping address:", address(flashLoanLooping));
        console.log("size address:", address(size));
        // Setup initial state
        _setPrice(1e18);
        
        // User deposits collateral and USDC
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        
        // Lender provides credit limit
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        console.log("After initial deposits:");
        console.log("alice WETH balance:", weth.balanceOf(alice));
        console.log("alice USDC balance:", usdc.balanceOf(alice));
        console.log("bob USDC balance:", usdc.balanceOf(bob));

        // User authorizes the FlashLoanLooping contract to act on their behalf
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.DEPOSIT));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.WITHDRAW));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        Vars memory _before = _state();
        uint256 beforeAliceWETH = weth.balanceOf(alice);
        uint256 beforeAliceUSDC = usdc.balanceOf(alice);

        console.log("Before loop operation:");
        console.log("alice collateral token balance:", _before.alice.collateralTokenBalance);
        console.log("alice debt balance:", _before.alice.debtBalance);
        console.log("alice borrowAToken balance:", _before.alice.borrowATokenBalance);

        // Create swap parameters to convert USDC to WETH
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Create sell credit market parameters for the lender
        SellCreditMarketParams[] memory sellCreditMarketParamsArray = new SellCreditMarketParams[](1);
        sellCreditMarketParamsArray[0] = SellCreditMarketParams({
            lender: bob,
            creditPositionId: RESERVED_ID,
            amount: 50e6, // amount to borrow
            tenor: 365 days,
            deadline: block.timestamp + 1 hours,
            maxAPR: 0.05e18, // 5% max APR
            exactAmountIn: false
        });

        // Calculate target leverage (e.g., 2x leverage)
        uint256 targetLeveragePercent = 200e16; // 200% = 2x leverage

        console.log("About to call loopPositionWithFlashLoan with:");
        console.log("targetLeveragePercent:", targetLeveragePercent);
        console.log("sellCreditMarketParamsArray[0].lender:", sellCreditMarketParamsArray[0].lender);
        console.log("sellCreditMarketParamsArray[0].amount:", sellCreditMarketParamsArray[0].amount);

        // User calls the loop function
        vm.prank(alice);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            50e6, // flash loan amount
            365 days, // tenor
            0.05e18, // max APR
            sellCreditMarketParamsArray,
            swapParamsArray,
            address(0), // recipient (address(0) means transfer profits to user)
            targetLeveragePercent
        );

        Vars memory _after = _state();
        uint256 afterAliceWETH = weth.balanceOf(alice);
        uint256 afterAliceUSDC = usdc.balanceOf(alice);

        console.log("After loop operation:");
        console.log("alice collateral token balance:", _after.alice.collateralTokenBalance);
        console.log("alice debt balance:", _after.alice.debtBalance);
        console.log("alice borrowAToken balance:", _after.alice.borrowATokenBalance);

        // Verify the loop was successful
        assertGt(_after.alice.debtBalance, _before.alice.debtBalance, "User should have increased debt");
        assertGt(_after.alice.collateralTokenBalance, _before.alice.collateralTokenBalance, "User should have increased collateral");
        
        // User should have received some USDC as profit from the loop
        assertGt(afterAliceUSDC, beforeAliceUSDC, "User should have received USDC profit");

        // Verify target leverage was achieved
        uint256 currentLeverage = flashLoanLooping.currentLeveragePercent(ISize(address(size)), alice);
        assertGe(currentLeverage, targetLeveragePercent, "Target leverage should be achieved");
    }

    function test_FlashLoanLooping_user_loop_with_deposit_profits() public {
        console.log("=== test_FlashLoanLooping_user_loop_with_deposit_profits ===");
        console.log("alice address:", alice);
        console.log("bob address:", bob);
        console.log("flashLoanLooping address:", address(flashLoanLooping));
        // Setup initial state
        _setPrice(1e18);
        
        // User deposits collateral and USDC
        _deposit(alice, weth, 1000000000e18);
        _deposit(alice, usdc, 10000e6);
        
        // Lender provides credit limit
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        console.log("After initial deposits:");
        console.log("alice WETH balance:", weth.balanceOf(alice));
        console.log("alice USDC balance:", usdc.balanceOf(alice));
        console.log("bob USDC balance:", usdc.balanceOf(bob));

        // User authorizes the FlashLoanLooping contract
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.DEPOSIT));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.WITHDRAW));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        Vars memory _before = _state();
        uint256 beforeAliceBorrowAToken = _before.alice.borrowATokenBalance;

        console.log("Before loop operation:");
        console.log("alice collateral token balance:", _before.alice.collateralTokenBalance);
        console.log("alice debt balance:", _before.alice.debtBalance);
        console.log("alice borrowAToken balance:", _before.alice.borrowATokenBalance);

        // Create swap parameters
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Create sell credit market parameters
        SellCreditMarketParams[] memory sellCreditMarketParamsArray = new SellCreditMarketParams[](1);
        sellCreditMarketParamsArray[0] = SellCreditMarketParams({
            lender: bob,
            creditPositionId: RESERVED_ID,
            amount: 10e6, // amount to borrow
            tenor: 365 days,
            deadline: block.timestamp + 1 hours,
            maxAPR: 0.05e18, // 5% max APR
            exactAmountIn: false
        });

        uint256 targetLeveragePercent = 150e16; // 150% = 1.5x leverage

        console.log("About to call loopPositionWithFlashLoan with:");
        console.log("targetLeveragePercent:", targetLeveragePercent);
        console.log("sellCreditMarketParamsArray[0].lender:", sellCreditMarketParamsArray[0].lender);
        console.log("sellCreditMarketParamsArray[0].amount:", sellCreditMarketParamsArray[0].amount);

        // User calls the loop function with depositProfits = true
        vm.prank(alice);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            10e6, // flash loan amount
            365 days, // tenor
            0.05e18, // max APR
            sellCreditMarketParamsArray,
            swapParamsArray,
            alice, // recipient (deposits profits to user's account)
            targetLeveragePercent
        );

        Vars memory _after = _state();
        uint256 afterAliceBorrowAToken = _after.alice.borrowATokenBalance;

        console.log("After loop operation:");
        console.log("alice collateral token balance:", _after.alice.collateralTokenBalance);
        console.log("alice debt balance:", _after.alice.debtBalance);
        console.log("alice borrowAToken balance:", _after.alice.borrowATokenBalance);

        // Verify the loop was successful and profits were deposited
        assertGt(_after.alice.debtBalance, _before.alice.debtBalance, "User should have increased debt");
        assertGt(_after.alice.collateralTokenBalance, _before.alice.collateralTokenBalance, "User should have increased collateral");
        assertGt(afterAliceBorrowAToken, beforeAliceBorrowAToken, "User should have received USDC profit as deposit");

        // Verify target leverage was achieved
        uint256 currentLeverage = flashLoanLooping.currentLeveragePercent(ISize(address(size)), alice);
        assertGe(currentLeverage, targetLeveragePercent, "Target leverage should be achieved");
    }

    function test_FlashLoanLooping_unauthorized_access_reverts() public {
        // Setup initial state
        _setPrice(1e18);
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // User does NOT authorize the FlashLoanLooping contract
        // This should cause the transaction to revert

        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Create sell credit market parameters
        SellCreditMarketParams[] memory sellCreditMarketParamsArray = new SellCreditMarketParams[](1);
        sellCreditMarketParamsArray[0] = SellCreditMarketParams({
            lender: bob,
            creditPositionId: RESERVED_ID,
            amount: 50e6,
            tenor: 365 days,
            deadline: block.timestamp + 1 hours,
            maxAPR: 0.05e18,
            exactAmountIn: false
        });

        uint256 targetLeveragePercent = 200e16; // 200% = 2x leverage

        // This should revert due to lack of authorization
        vm.prank(alice);
        vm.expectRevert(); // Expect any revert due to authorization failure
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            50e6,
            365 days,
            0.05e18,
            sellCreditMarketParamsArray,
            swapParamsArray,
            address(0),
            targetLeveragePercent
        );
    }

    function test_FlashLoanLooping_target_leverage_not_achieved_reverts() public {
        // Setup initial state
        _setPrice(1e18);
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // User authorizes the FlashLoanLooping contract
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.DEPOSIT));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.WITHDRAW));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Create sell credit market parameters with very small amount (insufficient for target leverage)
        SellCreditMarketParams[] memory sellCreditMarketParamsArray = new SellCreditMarketParams[](1);
        sellCreditMarketParamsArray[0] = SellCreditMarketParams({
            lender: bob,
            creditPositionId: RESERVED_ID,
            amount: 1e6, // very small amount
            tenor: 365 days,
            deadline: block.timestamp + 1 hours,
            maxAPR: 0.05e18,
            exactAmountIn: false
        });

        uint256 targetLeveragePercent = 500e16; // 500% = 5x leverage (very high, won't be achieved)

        // This should revert because target leverage won't be achieved
        vm.prank(alice);
        vm.expectRevert(); // Expect TargetLeverageNotAchieved error
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            50e6,
            365 days,
            0.05e18,
            sellCreditMarketParamsArray,
            swapParamsArray,
            address(0),
            targetLeveragePercent
        );
    }

    function test_FlashLoanLooping_multiple_lenders() public {
        console.log("=== test_FlashLoanLooping_multiple_lenders ===");
        console.log("alice address:", alice);
        console.log("bob address:", bob);
        console.log("carol address:", carol);
        console.log("flashLoanLooping address:", address(flashLoanLooping));
        // Setup initial state
        _setPrice(1e18);
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        
        // Multiple lenders provide credit limits
        _deposit(bob, usdc, 50e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        
        _deposit(carol, usdc, 50e6);
        _buyCreditLimit(carol, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.04e18));

        console.log("After initial deposits:");
        console.log("alice WETH balance:", weth.balanceOf(alice));
        console.log("alice USDC balance:", usdc.balanceOf(alice));
        console.log("bob USDC balance:", usdc.balanceOf(bob));
        console.log("carol USDC balance:", usdc.balanceOf(carol));

        // User authorizes the FlashLoanLooping contract
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.DEPOSIT));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.WITHDRAW));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        Vars memory _before = _state();

        console.log("Before loop operation:");
        console.log("alice collateral token balance:", _before.alice.collateralTokenBalance);
        console.log("alice debt balance:", _before.alice.debtBalance);
        console.log("alice borrowAToken balance:", _before.alice.borrowATokenBalance);

        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Create sell credit market parameters for multiple lenders
        SellCreditMarketParams[] memory sellCreditMarketParamsArray = new SellCreditMarketParams[](2);
        sellCreditMarketParamsArray[0] = SellCreditMarketParams({
            lender: bob,
            creditPositionId: RESERVED_ID,
            amount: 25e6, // borrow from bob
            tenor: 365 days,
            deadline: block.timestamp + 1 hours,
            maxAPR: 0.05e18,
            exactAmountIn: false
        });
        sellCreditMarketParamsArray[1] = SellCreditMarketParams({
            lender: carol,
            creditPositionId: RESERVED_ID,
            amount: 25e6, // borrow from carol
            tenor: 365 days,
            deadline: block.timestamp + 1 hours,
            maxAPR: 0.05e18,
            exactAmountIn: false
        });

        uint256 targetLeveragePercent = 200e16; // 200% = 2x leverage

        console.log("About to call loopPositionWithFlashLoan with:");
        console.log("targetLeveragePercent:", targetLeveragePercent);
        console.log("sellCreditMarketParamsArray[0].lender:", sellCreditMarketParamsArray[0].lender);
        console.log("sellCreditMarketParamsArray[0].amount:", sellCreditMarketParamsArray[0].amount);
        console.log("sellCreditMarketParamsArray[1].lender:", sellCreditMarketParamsArray[1].lender);
        console.log("sellCreditMarketParamsArray[1].amount:", sellCreditMarketParamsArray[1].amount);

        // User calls the loop function with multiple lenders
        vm.prank(alice);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            50e6, // flash loan amount
            365 days, // tenor
            0.05e18, // max APR
            sellCreditMarketParamsArray,
            swapParamsArray,
            address(0), // recipient
            targetLeveragePercent
        );

        Vars memory _after = _state();

        console.log("After loop operation:");
        console.log("alice collateral token balance:", _after.alice.collateralTokenBalance);
        console.log("alice debt balance:", _after.alice.debtBalance);
        console.log("alice borrowAToken balance:", _after.alice.borrowATokenBalance);

        // Verify the loop was successful with multiple lenders
        assertGt(_after.alice.debtBalance, _before.alice.debtBalance, "User should have increased debt");
        assertGt(_after.alice.collateralTokenBalance, _before.alice.collateralTokenBalance, "User should have increased collateral");

        // Verify target leverage was achieved
        uint256 currentLeverage = flashLoanLooping.currentLeveragePercent(ISize(address(size)), alice);
        assertGe(currentLeverage, targetLeveragePercent, "Target leverage should be achieved");
    }

    function test_FlashLoanLooping_getActionsBitmap() public {
        // Test that the contract returns the correct actions bitmap
        Action[] memory actions = new Action[](3);
        actions[0] = Action.DEPOSIT;
        actions[2] = Action.SELL_CREDIT_MARKET;
        uint256 expectedBitmap = Authorization.toUint256(Authorization.getActionsBitmap(actions));
        
        assertEq(
            Authorization.toUint256(flashLoanLooping.getActionsBitmap()),
            expectedBitmap,
            "Actions bitmap should match expected value"
        );
    }

    function test_FlashLoanLooping_description() public {
        // Test the description function
        string memory desc = flashLoanLooping.description();
        assertEq(
            desc,
            "FlashLoanLooping (DexSwap takes SwapParams[] as input)",
            "Description should match expected value"
        );
    }

    function test_FlashLoanLooping_currentLeveragePercent() public {
        // Setup initial state
        _setPrice(1e18);
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        
        // Check initial leverage (should be 100% = no leverage)
        uint256 initialLeverage = flashLoanLooping.currentLeveragePercent(ISize(address(size)), alice);
        assertEq(initialLeverage, PERCENT, "Initial leverage should be 100%");
        
        // Borrow some USDC to increase leverage
        _deposit(bob, usdc, 50e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        
        // User borrows some USDC
        vm.prank(alice);
        size.sellCreditMarket(
            SellCreditMarketParams({
                lender: bob,
                creditPositionId: RESERVED_ID,
                amount: 20e6,
                tenor: 365 days,
                deadline: block.timestamp + 1 hours,
                maxAPR: 0.05e18,
                exactAmountIn: false
            })
        );
        
        // Check leverage after borrowing (should be > 100%)
        uint256 leveragedLeverage = flashLoanLooping.currentLeveragePercent(ISize(address(size)), alice);
        assertGt(leveragedLeverage, PERCENT, "Leverage should be greater than 100% after borrowing");
    }
} 