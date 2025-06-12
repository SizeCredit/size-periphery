// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ForkTestVirtualsUSDC} from "./ForkTestVirtualsUSDC.sol";
import {AutoRepay} from "src/authorization/AutoRepay.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {SwapParams, SwapMethod, UniswapV3Params} from "src/liquidator/DexSwap.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DebtPosition} from "@src/market/libraries/LoanLibrary.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Addresses, CONTRACT} from "script/Addresses.s.sol";
import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {ActionsBitmap} from "@size/src/factory/libraries/Authorization.sol";
import {IPriceFeed} from "@size/src/oracle/IPriceFeed.sol";

contract ForkAutoRepayTest is ForkTestVirtualsUSDC, Addresses {
    // https://basescan.org/tx/0x93cb5935b1d8bf8b11990671aad0008c31ceb1bca5511c900d84ed0944271e40
    address constant BORROWER = 0x0f0B08CE5Cf394C77CA9763366656C629FDba449;
    uint256 constant DEBT_POSITION_ID = 181;
    uint24 constant FEE = 3000;
    address constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; // Base mainnet Uniswap V3 router
    address constant ONE_INCH = address(1); // placeholder
    address constant UNOSWAP = address(1); // placeholder
    address constant UNISWAP_V2 = address(1); // placeholder
    address constant POOL_ADDRESSES_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D; // Base mainnet Aave V3

    function setUp() public override {
        vm.createSelectFork("base", 31138987);
        super.setUp();
    }

    function testFork_AutoRepay() public {
        // Log addresses and parameters
        console.log("Deploying AutoRepay with:");
        console.log("ONE_INCH:", ONE_INCH);
        console.log("UNOSWAP:", UNOSWAP);
        console.log("UNISWAP_V2:", UNISWAP_V2);
        console.log("UNISWAP_V3_ROUTER:", UNISWAP_V3_ROUTER);
        console.log("POOL_ADDRESSES_PROVIDER:", POOL_ADDRESSES_PROVIDER);
        console.log("Owner:", address(this));
        console.log("size:", address(size));
        console.log("usdc:", address(usdc));
        console.log("virtuals:", address(virtuals));

        // Deploy implementation and proxy (format exactly as in working setup)
        AutoRepay autoRepayImplementation = new AutoRepay(ONE_INCH, UNOSWAP, UNISWAP_V2, UNISWAP_V3_ROUTER);
        bytes memory initData = abi.encodeWithSelector(
            AutoRepay.initialize.selector,
            address(this),
            IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER),
            48 days
        );
        AutoRepay autoRepay = AutoRepay(address(new ERC1967Proxy(address(autoRepayImplementation), initData)));
        console.log("AutoRepay proxy deployed at:", address(autoRepay));

        // Authorize AutoRepay contract
        console.log("Authorizing AutoRepay contract");
        ActionsBitmap actionsBitmap = autoRepay.getActionsBitmap();
        vm.prank(BORROWER);
        ISizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]).setAuthorization(
            address(autoRepay), actionsBitmap
        );

        // Fetch debt position
        DebtPosition memory debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        console.log("Debt position futureValue:", debtPosition.futureValue);
        
        // Calculate exact collateral amount needed using the Size contract's oracle
        uint256 collateralAmount = size.debtTokenAmountToCollateralTokenAmount(debtPosition.futureValue);
        // Increase collateral amount by 10%
        collateralAmount = collateralAmount * 110 / 100;
        
        console.log("Calculated collateral amount needed:", collateralAmount);
        
        // Get price feed for additional logging
        IPriceFeed priceFeedInterface = IPriceFeed(priceFeed);
        uint256 currentPrice = priceFeedInterface.getPrice();
        console.log("Current price from oracle:", currentPrice);
        console.log("Price feed decimals:", priceFeedInterface.decimals());

        // Prepare UniswapV3Params
        UniswapV3Params memory uniParams = UniswapV3Params({
            tokenIn: address(virtuals),
            tokenOut: address(usdc),
            fee: FEE,
            sqrtPriceLimitX96: 0,
            amountOutMinimum: 0
        });
        SwapParams[] memory swapParams = new SwapParams[](1);
        swapParams[0] = SwapParams({
            method: SwapMethod.UniswapV3,
            data: abi.encode(uniParams)
        });

        // Impersonate bot and call repayWithCollateral
        vm.startPrank(address(this));
        console.log("Calling repayWithCollateral...");
        autoRepay.repayWithCollateral(
            size,
            DEBT_POSITION_ID,
            BORROWER,
            collateralAmount,
            swapParams
        );
        vm.stopPrank();
        console.log("repayWithCollateral called");

        // Assert debt is repaid (futureValue == 0)
        debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        console.log("Debt position futureValue after:", debtPosition.futureValue);
        assertEq(debtPosition.futureValue, 0, "Debt should be repaid");
    }
} 