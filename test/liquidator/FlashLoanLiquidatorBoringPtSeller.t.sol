// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.sol";
import {Addresses, CONTRACT} from "script/Addresses.s.sol";
import {SizeFactory} from "@size/src/factory/SizeFactory.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FlashLoanLiquidator} from "src/liquidator/FlashLoanLiquidator.sol";
import {RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {AssertsHelper} from "@test/helpers/AssertsHelper.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";
import {SizeMock} from "@test/mocks/SizeMock.sol";
import {IPriceFeed} from "@size/src/oracle/IPriceFeed.sol";
import {PriceFeedMock} from "@test/mocks/PriceFeedMock.sol";
import {SwapParams, SwapMethod} from "src/liquidator/DexSwap.sol";
import {UpdateConfigParams} from "@size/src/market/libraries/actions/UpdateConfig.sol";
import {console} from "forge-std/console.sol";

contract FlashLoanLiquidatorBoringPtSellerTest is BaseTest, Addresses {
    FlashLoanLiquidator public flashLoanLiquidator;
    address public owner;
    address public borrower;
    address public lender;
    address public bot;

    function setUp() public override {}

    function _flashLoanLiquidate(
        address _liquidator,
        uint256 debtPositionId,
        address pendleMarket,
        IERC20Metadata underlyingCollateralToken,
        IERC20Metadata underlyingBorrowToken
    ) internal {
        vm.startPrank(_liquidator);

        uint24 fee = 500;
        uint160 sqrtPriceLimitX96 = 0;

        flashLoanLiquidator = new FlashLoanLiquidator(
            addresses[block.chainid][CONTRACT.ADDRESS_PROVIDER],
            address(0x1111),
            address(0x2222),
            address(0x3333),
            addresses[block.chainid][CONTRACT.UNISWAP_V3_ROUTER]
        );

        flashLoanLiquidator.liquidatePositionWithFlashLoan(
            address(size),
            address(underlyingCollateralToken),
            address(underlyingBorrowToken),
            debtPositionId,
            0,
            SwapParams({
                method: SwapMethod.BoringPtSeller,
                data: abi.encode(pendleMarket, fee, sqrtPriceLimitX96),
                deadline: block.timestamp,
                minimumReturnAmount: 0
            }),
            0,
            _liquidator
        );

        vm.stopPrank();
    }

    function testFork_FlashLoanLiquidatorBoringPtSeller_liquidate_PT_sUSDE_29MAY2025() public {
        vm.createSelectFork("mainnet");
        vm.rollFork(22524065);

        _testFork_FlashLoanLiquidatorBoringPtSeller_liquidate_PT(
            1, 0.99e18, 0.9e18, 0xB162B764044697cf03617C2EFbcB1f42e31E4766, "PT-sUSDE-29MAY2025", "USDC"
        );
    }

    function testFork_FlashLoanLiquidatorBoringPtSeller_liquidate_PT_sUSDE_31JUL2025() public {
        vm.createSelectFork("vnet");

        _testFork_FlashLoanLiquidatorBoringPtSeller_liquidate_PT(
            2, 0.96e18, 0.9e18, 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac, "PT-sUSDE-31JUL2025", "USDC"
        );
    }

    function _testFork_FlashLoanLiquidatorBoringPtSeller_liquidate_PT(
        uint256 marketIndex,
        uint256 price,
        uint256 newPrice,
        address pendleMarket,
        string memory underlyingCollateralSymbol,
        string memory underlyingBorrowSymbol
    ) internal {
        sizeFactory = SizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]);
        owner = addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE];
        borrower = makeAddr("borrower");
        lender = makeAddr("lender");
        bot = makeAddr("bot");

        ISize[] memory markets = sizeFactory.getMarkets();
        size = SizeMock(address(markets[marketIndex]));

        DataView memory data = size.data();

        IERC20Metadata underlyingCollateralToken = IERC20Metadata(data.underlyingCollateralToken);
        IERC20Metadata underlyingBorrowToken = IERC20Metadata(data.underlyingBorrowToken);

        assertEq(underlyingCollateralToken.symbol(), underlyingCollateralSymbol);
        assertEq(underlyingBorrowToken.symbol(), underlyingBorrowSymbol);

        assertEqApprox(IPriceFeed(size.oracle().priceFeed).getPrice(), price, 0.01e18);

        uint256 collateralAmount = 1_200e18;
        uint256 borrowAmount = 1_000e6;

        _deposit(borrower, underlyingCollateralToken, collateralAmount);
        _deposit(lender, underlyingBorrowToken, 2 * borrowAmount);
        _buyCreditLimit(lender, block.timestamp + 30 days, YieldCurveHelper.pointCurve(30 days, 0.03e18));

        assertEq(size.collateralRatio(borrower), type(uint256).max);

        uint256 debtPositionId = _sellCreditMarket(borrower, lender, RESERVED_ID, borrowAmount, 30 days, false);

        assertGt(size.collateralRatio(borrower), size.riskConfig().crLiquidation);

        PriceFeedMock priceFeedMock = new PriceFeedMock(address(this));

        vm.prank(owner);
        size.updateConfig(UpdateConfigParams({key: "priceFeed", value: uint256(uint160(address(priceFeedMock)))}));

        priceFeedMock.setPrice(newPrice);

        assertLt(size.collateralRatio(borrower), size.riskConfig().crLiquidation);

        uint256 flashLoanLiquidatorBalanceBefore = size.getUserView(bot).borrowATokenBalance;

        _flashLoanLiquidate(bot, debtPositionId, pendleMarket, underlyingCollateralToken, underlyingBorrowToken);

        uint256 flashLoanLiquidatorBalanceAfter = size.getUserView(bot).borrowATokenBalance;

        assertGt(flashLoanLiquidatorBalanceAfter, flashLoanLiquidatorBalanceBefore);
    }
}
