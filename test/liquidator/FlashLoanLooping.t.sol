// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SwapMethod, SwapParams, OneInchParams} from "src/liquidator/DexSwap.sol";
import {FlashLoanLooping} from "src/liquidator/FlashLoanLooping.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";

import {BaseTest, Vars} from "@size/test/BaseTest.sol";

import {DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {Action, Authorization} from "@size/src/factory/libraries/Authorization.sol";

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

    function test_FlashLoanLooping_user_loop_with_authorization() public {
        // Setup initial state
        _setPrice(1e18);
        
        // User deposits collateral and USDC
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        
        // Lender provides credit limit
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // User authorizes the FlashLoanLooping contract to act on their behalf
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.DEPOSIT));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.WITHDRAW));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        Vars memory _before = _state();
        uint256 beforeAliceWETH = weth.balanceOf(alice);
        uint256 beforeAliceUSDC = usdc.balanceOf(alice);

        // Create swap parameters to convert USDC to WETH
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // User calls the loop function
        vm.prank(alice);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            50e6, // flash loan amount
            365 days, // tenor
            0.05e18, // max APR
            bob, // lender
            swapParamsArray,
            address(0) // recipient (address(0) means transfer profits to user)
        );

        Vars memory _after = _state();
        uint256 afterAliceWETH = weth.balanceOf(alice);
        uint256 afterAliceUSDC = usdc.balanceOf(alice);

        // Verify the loop was successful
        assertGt(_after.alice.debtBalance, _before.alice.debtBalance, "User should have increased debt");
        assertGt(_after.alice.collateralTokenBalance, _before.alice.collateralTokenBalance, "User should have increased collateral");
        
        // User should have received some USDC as profit from the loop
        assertGt(afterAliceUSDC, beforeAliceUSDC, "User should have received USDC profit");
    }

    function test_FlashLoanLooping_user_loop_with_deposit_profits() public {
        // Setup initial state
        _setPrice(1e18);
        
        // User deposits collateral and USDC
        _deposit(alice, weth, 1000000000e18);
        _deposit(alice, usdc, 10000e6);
        
        // Lender provides credit limit
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        // User authorizes the FlashLoanLooping contract
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.DEPOSIT));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.WITHDRAW));
        _setAuthorization(alice, address(flashLoanLooping), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        Vars memory _before = _state();
        uint256 beforeAliceBorrowAToken = _before.alice.borrowATokenBalance;

        // Create swap parameters
        OneInchParams memory oneInchParams = OneInchParams({
            fromToken: address(usdc),
            toToken: address(weth),
            minReturn: 0,
            data: ""
        });

        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // User calls the loop function with depositProfits = true
        vm.prank(alice);
        flashLoanLooping.loopPositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            10e6, // flash loan amount
            365 days, // tenor
            0.05e18, // max APR
            bob, // lender
            swapParamsArray,
            alice // recipient (deposits profits to user's account)
        );

        Vars memory _after = _state();
        uint256 afterAliceBorrowAToken = _after.alice.borrowATokenBalance;

        // Verify the loop was successful and profits were deposited
        assertGt(_after.alice.debtBalance, _before.alice.debtBalance, "User should have increased debt");
        assertGt(_after.alice.collateralTokenBalance, _before.alice.collateralTokenBalance, "User should have increased collateral");
        assertGt(afterAliceBorrowAToken, beforeAliceBorrowAToken, "User should have received USDC profit as deposit");
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
            bob, // lender (alice has USDC to lend)
            swapParamsArray,
            address(0)
        );
    }

    function test_FlashLoanLooping_getActionsBitmap() public {
        // Test that the contract returns the correct actions bitmap
        Action[] memory actions = new Action[](3);
        actions[0] = Action.DEPOSIT;
        actions[1] = Action.WITHDRAW;
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
} 