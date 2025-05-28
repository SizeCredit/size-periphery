// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {MockAavePool} from "@test/mocks/MockAavePool.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutoRollover} from "src/authorization/AutoRollover.sol";
import {Authorization, Action} from "@size/src/factory/libraries/Authorization.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {LoanStatus} from "@size/src/market/libraries/LoanLibrary.sol";
import {SwapMethod, SwapParams, BoringPtSellerParams} from "src/liquidator/DexSwap.sol";
import {console} from "forge-std/console.sol";

contract AutoRolloverTest is BaseTest {
    MockAavePool public mockAavePool;
    Mock1InchAggregator public mock1InchAggregator;
    AutoRollover public autoRollover;

    function setUp() public override {
        super.setUp();
        mockAavePool = new MockAavePool();
        mock1InchAggregator = new Mock1InchAggregator(address(priceFeed));
        
        // Fund the mock aggregator and pool with WETH and USDC
        _mint(address(weth), address(mock1InchAggregator), 100_000e18);
        _mint(address(usdc), address(mock1InchAggregator), 100_000e6);
        _mint(address(weth), address(mockAavePool), 100_000e18);
        _mint(address(usdc), address(mockAavePool), 100_000e6);

        vm.warp(block.timestamp + 123 days);
        IPoolAddressesProvider addressProvider = IPoolAddressesProvider(address(mockAavePool));
        autoRollover = new AutoRollover(
            james,
            addressProvider,
            address(mock1InchAggregator),
            address(1), // placeholder for unoswap router
            address(1), // placeholder for uniswapv2 router
            address(1)  // placeholder for uniswapv3 router
        );
    }

    function test_AutoRollover_initialState() public view {
        assertEq(autoRollover.owner(), james);
        assertEq(autoRollover.EARLY_REPAYMENT_BUFFER(), 1 hours);
        assertTrue(autoRollover.ROLLOVER());
        assertFalse(autoRollover.REPAY());
    }

    function _setupLoan(uint256 tenor) private returns (uint256) {
        _deposit(alice, usdc, 300e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(
            alice,
            block.timestamp + 5 * tenor,
            YieldCurveHelper.customCurve(tenor, uint256(0.03e18), 2 * tenor, uint256(0.05e18))
        );

        uint256 amount = 100e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, tenor, false);
        _withdraw(bob, address(usdc), type(uint256).max);

        return debtPositionId;
    }

    function _createSwapParams() private view returns (SwapParams memory) {
        return SwapParams({
            method: SwapMethod.OneInch,
            data: abi.encode(""), // Data is not used in the mock
            minimumReturnAmount: 0,
            deadline: block.timestamp,
            hasPtSellerStep: false,
            ptSellerParams: BoringPtSellerParams({
                market: address(0),
                tokenOutIsYieldToken: false
            })
        });
    }

    function test_AutoRollover_rollover_success() public {
        uint256 tenor = 2 days;
        uint256 debtPositionId = _setupLoan(tenor);
        uint256 dueDate = block.timestamp + tenor;

        Vars memory _before = _state();
        assertEq(_before.bob.debtBalance, size.getDebtPosition(debtPositionId).futureValue);

        _setAuthorization(bob, address(autoRollover), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        // Move time to just before early repayment buffer
        vm.warp(dueDate - 30 minutes);
        assertEq(size.getLoanStatus(debtPositionId), LoanStatus.ACTIVE);

        uint256 rollover = 2 * tenor;
        SwapParams memory swapParams = _createSwapParams();

        vm.prank(james);
        autoRollover.rollover(
            size,
            debtPositionId,
            bob,
            alice,
            rollover,
            type(uint256).max,
            block.timestamp + 1 hours
        );

        Vars memory _after = _state();
        assertGt(_after.bob.debtBalance, _before.bob.debtBalance);
        assertEq(_after.bob.borrowATokenBalance, 0);
    }

    function test_AutoRollover_repay_success() public {
        uint256 tenor = 2 days;
        uint256 debtPositionId = _setupLoan(tenor);
        uint256 dueDate = block.timestamp + tenor;

        // Log initial state
        console.log("=== Initial State ===");
        Vars memory _before = _state();
        uint256 debtAmount = size.getDebtPosition(debtPositionId).futureValue;
        console.log("Debt Amount:", debtAmount);
        console.log("Bob's Debt Balance:", _before.bob.debtBalance);
        console.log("Bob's Collateral Balance:", _before.bob.collateralTokenBalance);
        console.log("Bob's Borrow Token Balance:", _before.bob.borrowATokenBalance);
        console.log("Price Feed Value:", priceFeed.getPrice());
        console.log("WETH Decimals:", weth.decimals());
        console.log("USDC Decimals:", usdc.decimals());
        assertEq(_before.bob.debtBalance, debtAmount);

        _setAuthorization(bob, address(autoRollover), Authorization.getActionsBitmap(Action.WITHDRAW));

        // Move time to just before early repayment buffer
        vm.warp(dueDate - 30 minutes);
        assertEq(size.getLoanStatus(debtPositionId), LoanStatus.ACTIVE);

        // Calculate collateral amount needed (105% of debt value to account for swap slippage)
        uint256 collateralAmount = (debtAmount * 105) / 100;
        console.log("\n=== Repay Parameters ===");
        console.log("Collateral Amount to Withdraw:", collateralAmount);
        console.log("Debt Amount to Repay:", debtAmount);
        console.log("Required Collateral Ratio:", (collateralAmount * 1e18) / debtAmount);
        
        // Calculate expected swap amounts
        uint256 price = priceFeed.getPrice();
        uint256 expectedUsdcAmount = (collateralAmount * price) / 1e26;
        console.log("\n=== Expected Swap Calculation ===");
        console.log("Price Feed Value:", price);
        console.log("Collateral Amount (WETH):", collateralAmount);
        console.log("Expected USDC Amount:", expectedUsdcAmount);
        console.log("Required USDC for Debt:", debtAmount);
        console.log("Required USDC for Flash Loan Fee:", (debtAmount * 9) / 10000); // 0.09% flash loan fee

        // Log balances before flash loan
        console.log("\n=== Pre-Flash Loan Balances ===");
        console.log("Mock1Inch WETH Balance:", weth.balanceOf(address(mock1InchAggregator)));
        console.log("Mock1Inch USDC Balance:", usdc.balanceOf(address(mock1InchAggregator)));
        console.log("MockAave WETH Balance:", weth.balanceOf(address(mockAavePool)));
        console.log("MockAave USDC Balance:", usdc.balanceOf(address(mockAavePool)));
        console.log("AutoRollover WETH Balance:", weth.balanceOf(address(autoRollover)));
        console.log("AutoRollover USDC Balance:", usdc.balanceOf(address(autoRollover)));
        console.log("Bob's WETH Balance:", weth.balanceOf(bob));
        console.log("Bob's USDC Balance:", usdc.balanceOf(bob));

        SwapParams memory swapParams = _createSwapParams();
        console.log("\n=== Swap Parameters ===");
        console.log("Swap Method:", uint8(swapParams.method));
        console.log("Minimum Return Amount:", swapParams.minimumReturnAmount);
        console.log("Deadline:", swapParams.deadline);

        // Try the repay operation
        vm.prank(james);
        try autoRollover.repay(
            size,
            debtPositionId,
            bob,
            collateralAmount,
            swapParams
        ) {
            console.log("\n=== Repay Operation Succeeded ===");
        } catch Error(string memory reason) {
            console.log("\n=== Repay Operation Failed with Error ===");
            console.log("Error:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n=== Repay Operation Failed with Low Level Error ===");
            console.logBytes(lowLevelData);
            
            // Log balances at time of failure
            console.log("\n=== Balances at Failure ===");
            console.log("Mock1Inch WETH Balance:", weth.balanceOf(address(mock1InchAggregator)));
            console.log("Mock1Inch USDC Balance:", usdc.balanceOf(address(mock1InchAggregator)));
            console.log("MockAave WETH Balance:", weth.balanceOf(address(mockAavePool)));
            console.log("MockAave USDC Balance:", usdc.balanceOf(address(mockAavePool)));
            console.log("AutoRollover WETH Balance:", weth.balanceOf(address(autoRollover)));
            console.log("AutoRollover USDC Balance:", usdc.balanceOf(address(autoRollover)));
            console.log("Bob's WETH Balance:", weth.balanceOf(bob));
            console.log("Bob's USDC Balance:", usdc.balanceOf(bob));
            
            revert("Low level error in repay operation");
        }

        // Log final state
        console.log("\n=== Final State ===");
        Vars memory _after = _state();
        console.log("Bob's Debt Balance:", _after.bob.debtBalance);
        console.log("Bob's Collateral Balance:", _after.bob.collateralTokenBalance);
        console.log("Bob's Borrow Token Balance:", _after.bob.borrowATokenBalance);
        console.log("AutoRollover WETH Balance:", weth.balanceOf(address(autoRollover)));
        console.log("AutoRollover USDC Balance:", usdc.balanceOf(address(autoRollover)));

        assertEq(_after.bob.debtBalance, 0, "Bob's debt should be 0");
        assertEq(_after.bob.collateralTokenBalance, 0, "Bob's collateral should be 0");
    }

    function test_AutoRollover_rollover_too_early() public {
        uint256 tenor = 2 days;
        uint256 debtPositionId = _setupLoan(tenor);
        uint256 dueDate = block.timestamp + tenor;

        // Move time to before early repayment buffer
        vm.warp(dueDate - 2 hours);

        uint256 rollover = 2 * tenor;
        SwapParams memory swapParams = _createSwapParams();

        vm.prank(james);
        vm.expectRevert(
            abi.encodeWithSelector(PeripheryErrors.AUTO_REPAY_TOO_EARLY.selector, dueDate, block.timestamp)
        );
        autoRollover.rollover(
            size,
            debtPositionId,
            bob,
            alice,
            rollover,
            type(uint256).max,
            block.timestamp + 1 hours
        );
    }

    function test_AutoRollover_repay_too_early() public {
        uint256 tenor = 2 days;
        uint256 debtPositionId = _setupLoan(tenor);
        uint256 dueDate = block.timestamp + tenor;

        // Move time to before early repayment buffer
        vm.warp(dueDate - 2 hours);

        uint256 debtAmount = size.getDebtPosition(debtPositionId).futureValue;
        uint256 collateralAmount = (debtAmount * 105) / 100;
        SwapParams memory swapParams = _createSwapParams();

        vm.prank(james);
        vm.expectRevert(
            abi.encodeWithSelector(PeripheryErrors.AUTO_REPAY_TOO_EARLY.selector, dueDate, block.timestamp)
        );
        autoRollover.repay(
            size,
            debtPositionId,
            bob,
            collateralAmount,
            swapParams
        );
    }

    function test_AutoRollover_rollover_unauthorized() public {
        uint256 tenor = 2 days;
        uint256 debtPositionId = _setupLoan(tenor);
        uint256 dueDate = block.timestamp + tenor;

        // Move time to just before early repayment buffer
        vm.warp(dueDate - 30 minutes);

        uint256 rollover = 2 * tenor;
        SwapParams memory swapParams = _createSwapParams();

        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, candy));
        autoRollover.rollover(
            size,
            debtPositionId,
            bob,
            alice,
            rollover,
            type(uint256).max,
            block.timestamp + 1 hours
        );
    }

    function test_AutoRollover_repay_unauthorized() public {
        uint256 tenor = 2 days;
        uint256 debtPositionId = _setupLoan(tenor);
        uint256 dueDate = block.timestamp + tenor;

        // Move time to just before early repayment buffer
        vm.warp(dueDate - 30 minutes);

        uint256 debtAmount = size.getDebtPosition(debtPositionId).futureValue;
        uint256 collateralAmount = (debtAmount * 105) / 100;
        SwapParams memory swapParams = _createSwapParams();

        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, candy));
        autoRollover.repay(
            size,
            debtPositionId,
            bob,
            collateralAmount,
            swapParams
        );
    }

}
