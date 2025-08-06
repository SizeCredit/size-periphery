// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SwapMethod, BuyPtParams, UniswapV3Params, SwapParams} from "src/liquidator/DexSwap.sol";
import {LeverageUp} from "src/zaps/LeverageUp.sol";
import {Mock1InchAggregator} from "test/mocks/Mock1InchAggregator.sol";

import {BaseTest, Vars} from "@size/test/BaseTest.sol";
import {SizeFactory} from "@size/src/factory/SizeFactory.sol";
import {SizeMock} from "@size/test/mocks/SizeMock.sol";
import {IPriceFeed} from "@size/src/oracle/IPriceFeed.sol";
import {SellCreditMarketParams} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {IPMarket} from "@pendle/contracts/interfaces/IPMarket.sol";

import {YieldCurveHelper} from "@size/test/helpers/libraries/YieldCurveHelper.sol";

import {Addresses, CONTRACT} from "script/Addresses.s.sol";

import {console} from "forge-std/console.sol";

contract LeverageUpTest is BaseTest, Addresses {
    LeverageUp public leverageUp;
    address public pendleMarket;
    address public borrower;
    address public lender = 0x04B4c8281B5d2D7aBee794bf3Ab3c95a02FF246f;

    function setUp() public override {
        vm.createSelectFork("mainnet");
        vm.rollFork(22631725);

        borrower = makeAddr("borrower");

        sizeFactory = SizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]);
        size = SizeMock(address(sizeFactory.getMarkets()[3]));
        pendleMarket = PT_wstUSR_25SEP2025_MARKET;

        assertEq(size.data().underlyingCollateralToken.symbol(), "PT-wstUSR-25SEP2025");
        assertEq(size.data().underlyingBorrowToken.symbol(), "USDC");

        assertEqApprox(IPriceFeed(size.oracle().priceFeed).getPrice(), 0.98e18, 0.01e18);

        leverageUp = new LeverageUp(
            address(type(uint160).max),
            address(type(uint160).max),
            addresses[block.chainid][CONTRACT.UNISWAP_V2_ROUTER],
            addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER]
        );

        vm.label(pendleMarket, "PendleMarket");
        vm.label(address(size), "Size");
        vm.label(address(size.data().underlyingCollateralToken), "UnderlyingCollateralToken");
        vm.label(address(size.data().underlyingBorrowToken), "UnderlyingBorrowToken");
        vm.label(address(size.data().collateralToken), "CollateralToken");
        vm.label(address(size.data().borrowTokenVault), "BorrowTokenVault");
        vm.label(address(size.data().debtToken), "DebtToken");
    }

    function _leverageUpWithSwap(
        address user_,
        address tokenIn_,
        uint256 amount_,
        address lender_,
        uint256 leveragePercent_,
        uint256 borrowPercent_
    ) internal {
        SellCreditMarketParams[] memory sellCreditMarketParamsArray = new SellCreditMarketParams[](1);
        uint256 tenor = IPMarket(pendleMarket).expiry() - block.timestamp;
        uint256 apr = size.getLoanOfferAPR(lender_, RESERVED_ID, address(0), tenor);
        sellCreditMarketParamsArray[0] = SellCreditMarketParams({
            lender: lender_,
            creditPositionId: RESERVED_ID,
            amount: 0, // unused
            tenor: tenor,
            deadline: block.timestamp,
            maxAPR: apr,
            exactAmountIn: false,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });

        address tokenOut = leverageUp.getPtSellerTokenOut(pendleMarket, false);

        UniswapV3Params memory uniswapV3Params = UniswapV3Params({
            tokenIn: address(size.data().underlyingBorrowToken),
            tokenOut: address(tokenOut),
            fee: 500,
            sqrtPriceLimitX96: 0,
            amountOutMinimum: 0
        });

        BuyPtParams memory buyPtParams =
            BuyPtParams({market: pendleMarket, tokenIn: address(tokenOut), router: PENDLE_ROUTER, minPtOut: 0});

        SwapParams[] memory swapParamsArray = new SwapParams[](2);
        swapParamsArray[0] = SwapParams({method: SwapMethod.UniswapV3, data: abi.encode(uniswapV3Params)});
        swapParamsArray[1] = SwapParams({method: SwapMethod.BuyPt, data: abi.encode(buyPtParams)});

        vm.prank(user_);
        leverageUp.leverageUpWithSwap(
            size, sellCreditMarketParamsArray, tokenIn_, amount_, leveragePercent_, borrowPercent_, swapParamsArray
        );
    }

    function testFork_LeverageUp_leverageUp_6x_starting_with_collateral() public {
        uint256 collateralAmount = 10_000e18;
        address underlyingCollateralToken = address(size.data().underlyingCollateralToken);

        _mint(underlyingCollateralToken, borrower, collateralAmount);

        _setAuthorization(borrower, address(leverageUp), leverageUp.getActionsBitmap());
        _approve(borrower, underlyingCollateralToken, address(leverageUp), collateralAmount);
        _leverageUpWithSwap(borrower, underlyingCollateralToken, collateralAmount, lender, 6.0e18, 0.97e18);

        assertEqApprox(leverageUp.currentLeveragePercent(size, borrower), 6.4e18, 0.1e18);
    }

    function testFork_LeverageUp_leverageUp_6x_starting_with_cash() public {
        uint256 cash = 10_000e6;
        address underlyingBorrowToken = address(size.data().underlyingBorrowToken);

        _mint(underlyingBorrowToken, borrower, cash);

        _setAuthorization(borrower, address(leverageUp), leverageUp.getActionsBitmap());
        _approve(borrower, underlyingBorrowToken, address(leverageUp), cash);
        _leverageUpWithSwap(borrower, underlyingBorrowToken, cash, lender, 6.0e18, 0.97e18);

        assertEqApprox(leverageUp.currentLeveragePercent(size, borrower), 6.8e18, 0.1e18);
    }

    function testFork_LeverageUp_leverageUp_max() public {
        uint256 collateralAmount = 10_000e18;
        address underlyingCollateralToken = address(size.data().underlyingCollateralToken);

        _mint(underlyingCollateralToken, borrower, collateralAmount);

        _setAuthorization(borrower, address(leverageUp), leverageUp.getActionsBitmap());
        _approve(borrower, underlyingCollateralToken, address(leverageUp), collateralAmount);
        uint256 maxLeveragePercent = leverageUp.maxLeveragePercent(size);

        assertEqApprox(maxLeveragePercent, 9.3e18, 0.1e18);

        _leverageUpWithSwap(borrower, underlyingCollateralToken, collateralAmount, lender, maxLeveragePercent, 0.973e18);

        assertEqApprox(leverageUp.currentLeveragePercent(size, borrower), 7.9e18, 0.1e18);
    }
}
