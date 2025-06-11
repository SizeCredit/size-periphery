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

contract ForkAutoRepayTest is ForkTestVirtualsUSDC, Addresses {
    // https://basescan.org/tx/0x93cb5935b1d8bf8b11990671aad0008c31ceb1bca5511c900d84ed0944271e40
    address constant BORROWER = 0x0f0B08CE5Cf394C77CA9763366656C629FDba449;
    uint256 constant DEBT_POSITION_ID = 181;
    uint24 constant FEE = 3000;

    AutoRepay public autoRepay;

    function setUp() public override {
        vm.createSelectFork("base", 31138987);
        vm.warp(1717430523);
        super.setUp();

        console.log("Deploying AutoRepay with:");
        console.log("UNISWAP_V3_ROUTER:", addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER]);
        console.log("Owner:", address(this));
        console.log("size:", address(size));
        console.log("usdc:", address(usdc));
        console.log("virtuals:", address(virtuals));

        // Deploy implementation and proxy (format exactly as in working setup)
        AutoRepay autoRepayImplementation = new AutoRepay();
        bytes memory initData = abi.encodeCall(
            AutoRepay.initialize,
            (address(this), IPoolAddressesProvider(addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER]), 1 hours)
        );
        autoRepay = AutoRepay(address(new ERC1967Proxy(address(autoRepayImplementation), initData)));

        vm.label(BORROWER, "BORROWER");
        vm.label(addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER], "ADDRESS_PROVIDER");
        vm.label(addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER], "UNISWAP_V3_ROUTER");
        vm.label(address(this), "OWNER");
        vm.label(address(size), "SIZE");
        vm.label(address(usdc), "USDC");
        vm.label(address(virtuals), "VIRTUALS");
        vm.label(address(autoRepay), "AUTO_REPAY");
    }

    function testFork_AutoRepay() public {
        autoRepay.setEarlyRepaymentBuffer(2 * 30 days);
        console.log("AutoRepay proxy deployed at:", address(autoRepay));

        console.log("Authorizing AutoRepay contract");
        ActionsBitmap actionsBitmap = autoRepay.getActionsBitmap();
        vm.prank(BORROWER);
        ISizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]).setAuthorization(
            address(autoRepay), actionsBitmap
        );

        // Fetch debt position
        DebtPosition memory debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        uint256 collateralAmount = size.getUserView(BORROWER).collateralTokenBalance;
        console.log("Debt position futureValue:", debtPosition.futureValue);
        console.log("Collateral amount:", collateralAmount);

        // Prepare UniswapV3Params
        UniswapV3Params memory uniParams = UniswapV3Params({
            router: addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER],
            tokenIn: address(virtuals),
            tokenOut: address(usdc),
            fee: FEE,
            sqrtPriceLimitX96: 0,
            amountOutMinimum: 0
        });
        SwapParams[] memory swapParams = new SwapParams[](1);
        swapParams[0] = SwapParams({method: SwapMethod.UniswapV3, data: abi.encode(uniParams)});

        // Impersonate bot and call repayWithCollateral
        vm.startPrank(address(this));
        console.log("Calling repayWithCollateral...");
        autoRepay.repayWithCollateral(size, DEBT_POSITION_ID, BORROWER, collateralAmount, swapParams);
        vm.stopPrank();
        console.log("repayWithCollateral called");

        // Assert debt is repaid (futureValue == 0)
        debtPosition = size.getDebtPosition(DEBT_POSITION_ID);
        console.log("Debt position futureValue after:", debtPosition.futureValue);
        assertEq(debtPosition.futureValue, 0, "Debt should be repaid");
    }
}
