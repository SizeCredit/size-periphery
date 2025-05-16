// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.sol";
import {Addresses, CONTRACT} from "script/Addresses.s.sol";
import {SizeFactory} from "@size/src/factory/SizeFactory.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FlashLoanLiquidator} from "src/liquidator/FlashLoanLiquidator.sol";
import {SellCreditMarketParams} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {AssertsHelper} from "@test/helpers/AssertsHelper.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {SizeMock} from "@test/mocks/SizeMock.sol";
import {IPriceFeed} from "@size/src/oracle/IPriceFeed.sol";
import {DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";
import {PriceFeedMock} from "@test/mocks/PriceFeedMock.sol";
import {SwapParams, SwapMethod} from "src/liquidator/DexSwap.sol";
import {UpdateConfigParams} from "@size/src/market/libraries/actions/UpdateConfig.sol";

contract FlashLoanLiquidatorVnetTest is BaseTest, Addresses {
    FlashLoanLiquidator public flashLoanLiquidator;
    IERC20Metadata public underlyingCollateralToken;
    IERC20Metadata public underlyingBorrowToken;
    address public borrower;
    address public lender;
    address public owner;
    address public bot;

    function setUp() public override {
        vm.createSelectFork("vnet");
        sizeFactory = SizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]);
        flashLoanLiquidator = FlashLoanLiquidator(addresses[block.chainid][CONTRACT.FLASH_LOAN_LIQUIDATOR]);
        owner = addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE];
        bot = flashLoanLiquidator.owner();
        borrower = makeAddr("borrower");
        lender = makeAddr("lender");

        ISize[] memory markets = sizeFactory.getMarkets();
        size = SizeMock(address(markets[2]));

        DataView memory data = size.data();

        underlyingCollateralToken = IERC20Metadata(data.underlyingCollateralToken);
        underlyingBorrowToken = IERC20Metadata(data.underlyingBorrowToken);

        assertEq(underlyingCollateralToken.symbol(), "PT-sUSDE-31JUL2025");
        assertEq(underlyingBorrowToken.symbol(), "USDC");

        vm.label(address(flashLoanLiquidator), "FlashLoanLiquidator");
        vm.label(address(size), "Size");
        vm.label(address(sizeFactory), "SizeFactory");
        vm.label(address(underlyingCollateralToken), underlyingCollateralToken.symbol());
        vm.label(address(underlyingBorrowToken), underlyingBorrowToken.symbol());
    }

    function _flashLoanLiquidate(address _liquidator, uint256 debtPositionId) internal {
        vm.startPrank(_liquidator);
        bytes memory genericRouteData = hex"1337"; // TODO: fix this
        flashLoanLiquidator.liquidatePositionWithFlashLoan(
            address(size),
            address(underlyingCollateralToken),
            address(underlyingBorrowToken),
            debtPositionId,
            0,
            SwapParams({
                method: SwapMethod.GenericRoute,
                data: genericRouteData,
                deadline: block.timestamp,
                minimumReturnAmount: 0
            }),
            0,
            _liquidator
        );
    }

    function testFork_FlashLoanLiquidatorVnet_liquidate_PT_token() public {
        assertEqApprox(IPriceFeed(size.oracle().priceFeed).getPrice(), 0.95e18, 0.01e18);

        uint256 collateralAmount = 1_200e18;
        uint256 borrowAmount = 1_000e6;

        _deposit(borrower, underlyingCollateralToken, collateralAmount);
        _deposit(lender, underlyingBorrowToken, 2 * borrowAmount);
        _buyCreditLimit(lender, block.timestamp + 30 days, YieldCurveHelper.pointCurve(30 days, 0.03e18));

        assertEq(size.collateralRatio(borrower), type(uint256).max);

        uint256 debtPositionId = _sellCreditMarket(borrower, lender, RESERVED_ID, borrowAmount, 30 days, false);

        assertEqApprox(size.collateralRatio(borrower), 1.14e18, 0.01e18);

        PriceFeedMock priceFeedMock = new PriceFeedMock(address(this));

        vm.prank(owner);
        size.updateConfig(UpdateConfigParams({key: "priceFeed", value: uint256(uint160(address(priceFeedMock)))}));

        priceFeedMock.setPrice(0.9e18);

        assertEqApprox(size.collateralRatio(borrower), 1.07e18, 0.01e18);

        _flashLoanLiquidate(bot, debtPositionId);
    }
}
