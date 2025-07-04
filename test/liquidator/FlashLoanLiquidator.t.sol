// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SwapMethod, BoringPtSellerParams, SwapParams, OneInchParams} from "src/liquidator/DexSwap.sol";
import {FlashLoanLiquidator, ReplacementParams} from "src/liquidator/FlashLoanLiquidator.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";

import {BaseTest, Vars} from "@size/test/BaseTest.sol";

import {DebtPosition} from "@size/src/market/libraries/LoanLibrary.sol";
import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";

import {console} from "forge-std/console.sol";

contract FlashLoanLiquidatorTest is BaseTest {
    MockAavePool public mockAavePool;
    Mock1InchAggregator public mock1InchAggregator;
    FlashLoanLiquidator public flashLoanLiquidator;

    function test_FlashLoanLiquidator_liquidator_liquidate_and_swap_1inch_withdraw() public {
        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));

        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 100_000e18);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 100_000e6);

        // Initialize the FlashLoanLiquidator contract
        flashLoanLiquidator = new FlashLoanLiquidator(
            address(mockAavePool),
            address(mock1InchAggregator),
            address(1), // placeholder for the unoswap router
            address(1), // placeholder for the uniswapv2 aggregator
            address(1) // placeholder for the uniswapv3 router
        );

        // Set the FlashLoanLiquidator contract as the keeper
        _setKeeperRole(address(flashLoanLiquidator));

        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);

        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        uint256 amount = 15e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, amount, 365 days, false);
        DebtPosition memory debtPosition = size.getDebtPosition(debtPositionId);
        uint256 debt = debtPosition.futureValue;

        _setPrice(0.2e18);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));

        Vars memory _before = _state();
        uint256 beforeLiquidatorUSDC = usdc.balanceOf(liquidator);

        OneInchParams memory oneInchParams =
            OneInchParams({fromToken: address(weth), toToken: address(usdc), minReturn: 0, data: ""});

        // Create SwapParams for a 1inch swap
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Call the liquidatePositionWithFlashLoan function
        vm.prank(liquidator);
        flashLoanLiquidator.liquidatePositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            debtPositionId,
            0, // minimumCollateralProfit
            block.timestamp + 1 days,
            swapParamsArray, // Pass the swapParams
            0, // supplementAmount
            address(0)
        );

        Vars memory _after = _state();
        uint256 afterLiquidatorUSDC = usdc.balanceOf(liquidator);

        assertEq(_after.bob.debtBalance, _before.bob.debtBalance - debt, 0);
        assertEq(_after.liquidator.borrowATokenBalance, _before.liquidator.borrowATokenBalance, 0);
        assertEq(_after.liquidator.collateralTokenBalance, _before.liquidator.collateralTokenBalance, 0);
        assertGt(
            _after.feeRecipient.collateralTokenBalance,
            _before.feeRecipient.collateralTokenBalance,
            "feeRecipient has liquidation split"
        );
        assertGt(afterLiquidatorUSDC, beforeLiquidatorUSDC, "Liquidator should have more USDC after liquidation");
    }

    function test_FlashLoanLiquidator_liquidator_liquidate_with_replacement() public {
        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));

        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 10_000_000_000_000e18);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 1_000_000e6);

        // Initialize the FlashLoanLiquidator contract
        vm.prank(liquidator);
        flashLoanLiquidator = new FlashLoanLiquidator(
            address(mockAavePool),
            address(mock1InchAggregator),
            address(1), // placeholder for the unoswap router
            address(1), // placeholder for the uniswapv2 aggregator
            address(1) // placeholder for the uniswapv3 router
        );

        // Add debug logs to track balances
        console.log("Initial WETH balance of mock1inch:", weth.balanceOf(address(mock1InchAggregator)));
        console.log("Initial USDC balance of mock1inch:", usdc.balanceOf(address(mock1InchAggregator)));

        // Set the FlashLoanLiquidator contract as the keeper
        _setKeeperRole(address(flashLoanLiquidator));

        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        uint256 amount = 15e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, amount, 365 days, false);
        _setPrice(0.2e18); // Set a price that makes the position undercollateralized

        // Setup replacement borrower
        _deposit(candy, weth, 400e18);
        _deposit(candy, usdc, 1000e6);
        _sellCreditLimit(candy, 400 days, [int256(0.03e18), 0.03e18], [uint256(1 days), 365 days]); // Valid borrow offer

        OneInchParams memory oneInchParams =
            OneInchParams({fromToken: address(weth), toToken: address(usdc), minReturn: 0, data: ""});

        // Create SwapParams for a 1inch swap
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Create ReplacementParams
        ReplacementParams memory replacementParams =
            ReplacementParams({minAPR: 0.03e18, deadline: block.timestamp + 1 days, replacementBorrower: candy});

        // Call the liquidatePositionWithFlashLoanReplacement function
        vm.prank(liquidator);
        flashLoanLiquidator.liquidatePositionWithFlashLoanReplacement(
            address(size),
            address(weth),
            address(usdc),
            debtPositionId,
            0, // minimumCollateralProfit
            block.timestamp + 1 days,
            swapParamsArray,
            0, // supplementAmount
            address(0),
            replacementParams
        );

        // Assertions to verify the state after liquidation
        assertTrue(size.isDebtPositionLiquidatable(debtPositionId) == false, "Debt position should not be liquidatable");
        assertEq(size.getDebtPosition(debtPositionId).borrower, candy, "Debt position should be transferred to candy");
        assertGt(usdc.balanceOf(liquidator), 0, "Liquidator should have received some USDC as profit");
    }

    function test_FlashLoanLiquidator_liquidator_liquidate_and_deposit_profits() public {
        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));

        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 100_000e18);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 100_000e6);

        // Initialize the FlashLoanLiquidator contract
        flashLoanLiquidator = new FlashLoanLiquidator(
            address(mockAavePool),
            address(mock1InchAggregator),
            address(1), // placeholder for the unoswap router
            address(1), // placeholder for the uniswapv2 aggregator
            address(1) // placeholder for the uniswapv3 router
        );

        // Add debug logs
        console.log("Mock AAVE Pool:", address(mockAavePool));
        console.log("Mock 1Inch:", address(mock1InchAggregator));
        console.log("Size Market:", address(size));

        // Set the FlashLoanLiquidator contract as the keeper
        _setKeeperRole(address(flashLoanLiquidator));

        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);

        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        uint256 amount = 15e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, amount, 365 days, false);
        DebtPosition memory debtPosition = size.getDebtPosition(debtPositionId);
        uint256 debt = debtPosition.futureValue;

        _setPrice(0.2e18);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));

        Vars memory _before = _state();
        uint256 beforeLiquidatorUSDC = usdc.balanceOf(liquidator);

        OneInchParams memory oneInchParams =
            OneInchParams({fromToken: address(weth), toToken: address(usdc), minReturn: 0, data: ""});

        // Create SwapParams for a 1inch swap
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Call the liquidatePositionWithFlashLoan function
        vm.prank(liquidator);
        flashLoanLiquidator.liquidatePositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            debtPositionId,
            0, // minimumCollateralProfit
            block.timestamp + 1 days,
            swapParamsArray, // Pass the swapParams
            0, // supplementAmount
            liquidator
        );

        Vars memory _after = _state();
        uint256 afterLiquidatorUSDC = _after.liquidator.borrowATokenBalance;

        assertEq(_after.bob.debtBalance, _before.bob.debtBalance - debt, 0);
        // assertEq(_after.liquidator.borrowATokenBalance, _before.liquidator.borrowATokenBalance, 0);
        assertEq(_after.liquidator.collateralTokenBalance, _before.liquidator.collateralTokenBalance, 0);
        assertGt(
            _after.feeRecipient.collateralTokenBalance,
            _before.feeRecipient.collateralTokenBalance,
            "feeRecipient has repayFee and liquidation split"
        );
        assertGt(afterLiquidatorUSDC, beforeLiquidatorUSDC, "Liquidator should have more USDC after liquidation");
    }

    function test_FlashLoanLiquidator_liquidator_liquidate_unprofitable_with_supplement() public {
        // Initialize mock contracts
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));

        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 100_000e18);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 100_000e6);

        // Initialize the FlashLoanLiquidator contract
        flashLoanLiquidator = new FlashLoanLiquidator(
            address(mockAavePool),
            address(mock1InchAggregator),
            address(1), // placeholder for the unoswap router
            address(1), // placeholder for the uniswapv2 aggregator
            address(1) // placeholder for the uniswapv3 router
        );

        // Set the FlashLoanLiquidator contract as the keeper
        _setKeeperRole(address(flashLoanLiquidator));

        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 30e18);
        _deposit(bob, usdc, 100e6);

        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        uint256 amount = 15e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, amount, 365 days, false);
        DebtPosition memory debtPosition = size.getDebtPosition(debtPositionId);
        uint256 debt = debtPosition.futureValue;

        _setPrice(0.00001e18);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));

        OneInchParams memory oneInchParams =
            OneInchParams({fromToken: address(weth), toToken: address(usdc), minReturn: 0, data: ""});

        // Create SwapParams for a 1inch swap
        SwapParams[] memory swapParamsArray = new SwapParams[](1);
        swapParamsArray[0] = SwapParams({method: SwapMethod.OneInch, data: abi.encode(oneInchParams)});

        // Setup balance and allowance for unprofitable liquidation
        uint256 supplementAmount = 14e6;
        _mint(address(usdc), liquidator, supplementAmount);
        _approve(liquidator, address(usdc), address(flashLoanLiquidator), supplementAmount);

        Vars memory _before = _state();
        uint256 beforeLiquidatorUSDC = usdc.balanceOf(liquidator);

        // Call the liquidatePositionWithFlashLoan function
        vm.prank(liquidator);
        flashLoanLiquidator.liquidatePositionWithFlashLoan(
            address(size),
            address(weth),
            address(usdc),
            debtPositionId,
            0, // minimumCollateralProfit
            block.timestamp + 1 days,
            swapParamsArray, // Pass the swapParams
            supplementAmount,
            liquidator
        );

        Vars memory _after = _state();
        uint256 afterLiquidatorUSDC = _after.liquidator.borrowATokenBalance;

        assertEq(_after.bob.debtBalance, _before.bob.debtBalance - debt, 0);
        // assertEq(_after.liquidator.borrowATokenBalance, _before.liquidator.borrowATokenBalance, 0);
        assertEq(_after.liquidator.collateralTokenBalance, _before.liquidator.collateralTokenBalance, 0);
        assertEq(
            _after.feeRecipient.collateralTokenBalance,
            _before.feeRecipient.collateralTokenBalance,
            "feeRecipient should not receive anything as loan underwater"
        );
        assertLt(
            afterLiquidatorUSDC, beforeLiquidatorUSDC, "Liquidator should have less USDC after unprofitable liquidation"
        );
    }
}
