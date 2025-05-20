// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {Addresses, CONTRACT} from "./Addresses.s.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@size/src/market/interfaces/ISizeAdmin.sol";
import {ISizeFactory} from "@size/src/factory/interfaces/ISizeFactory.sol";
import {DEBT_POSITION_ID_START, RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {PriceFeedMock} from "@test/mocks/PriceFeedMock.sol";
import {YieldCurve} from "@src/market/libraries/YieldCurveLibrary.sol";
import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";
import {BuyCreditLimitParams} from "@src/market/libraries/actions/BuyCreditLimit.sol";
import {
    SellCreditMarketParams
} from "@src/market/libraries/actions/SellCreditMarket.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

contract CreateVnetLiquidatablePosition is Script, Addresses {
    using Tenderly for *;

    address owner;
    Tenderly.Client tenderly;
    string vnetId;
    ISizeFactory sizeFactory;
    ISize size;

    address borrower = address(0x1111);
    address lender = address(0x2222);
    address PRICE_FEED_MOCK_ADDRESS = 0xF4a21Ac7e51d17A0e1C8B59f7a98bb7A97806f14;

    constructor() {
        vm.createSelectFork("vnet");

        vnetId = vm.envString("VNET_ID");
        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        sizeFactory = ISizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]);
        owner = addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE];
        size = sizeFactory.getMarket(1);
    }

    function _tenderlyDeposit(address user, address token, uint256 amount) internal {
        Tenderly.VirtualTestnet memory vnet = tenderly.getVirtualTestnetById(vnetId);
        tenderly.setErc20Balance(vnet, token, user, amount);
        tenderly.sendTransaction(vnetId, user, token, abi.encodeCall(IERC20.approve, (address(size), amount)));
        tenderly.sendTransaction(
            vnetId,
            user,
            address(size),
            abi.encodeCall(ISize.deposit, (DepositParams({token: token, amount: amount, to: user})))
        );
    }

    function _tenderlyBuyCreditLimit(address user, uint256 maxDueDate, YieldCurve memory curve) internal {
        tenderly.sendTransaction(
            vnetId,
            user,
            address(size),
            abi.encodeCall(
                ISize.buyCreditLimit, (BuyCreditLimitParams({maxDueDate: maxDueDate, curveRelativeTime: curve}))
            )
        );
    }

    function _tenderlySellCreditMarket(
        address _borrower,
        address _lender,
        uint256 _creditPositionId,
        uint256 _amount,
        uint256 _tenor,
        bool _exactAmountIn
    ) internal {
        tenderly.sendTransaction(
            vnetId,
            _borrower,
            address(size),
            abi.encodeCall(
                ISize.sellCreditMarket,
                (
                    SellCreditMarketParams({
                        lender: _lender,
                        creditPositionId: _creditPositionId,
                        amount: _amount,
                        tenor: _tenor,
                        exactAmountIn: _exactAmountIn,
                        deadline: block.timestamp + 1 days,
                        maxAPR: type(uint256).max
                    })
                )
            )
        );
    }

    function _tenderlyUpdateConfig(address _owner, string memory _key, uint256 _value) internal {
        tenderly.sendTransaction(
            vnetId,
            _owner,
            address(size),
            abi.encodeCall(ISizeAdmin.updateConfig, (UpdateConfigParams({key: _key, value: _value})))
        );
    }

    function _tenderlyUpdatePrice(address _owner, PriceFeedMock _priceFeedMock, uint256 _price) internal {
        tenderly.sendTransaction(
            vnetId, _owner, address(_priceFeedMock), abi.encodeCall(PriceFeedMock.setPrice, (_price))
        );
    }

    function run() external {
        IERC20Metadata underlyingCollateralToken = IERC20Metadata(size.data().underlyingCollateralToken);
        IERC20Metadata underlyingBorrowToken = IERC20Metadata(size.data().underlyingBorrowToken);

        uint256 collateralAmount = 1_200e18;
        uint256 borrowAmount = 1_000e6;

        _tenderlyDeposit(borrower, address(underlyingCollateralToken), collateralAmount);
        _tenderlyDeposit(lender, address(underlyingBorrowToken), 2 * borrowAmount);
        YieldCurve memory curve;
        curve.tenors = new uint256[](2);
        curve.aprs = new int256[](2);
        curve.marketRateMultipliers = new uint256[](2);

        curve.aprs[0] = 0.03e18;
        curve.tenors[0] = 30 days;
        curve.aprs[1] = 0.04e18;
        curve.tenors[1] = 60 days;

        _tenderlyBuyCreditLimit(lender, block.timestamp + 90 days, curve);
        _tenderlySellCreditMarket(borrower, lender, RESERVED_ID, borrowAmount, 45 days, false);
        (uint256 debtPositionsCount,) = size.getPositionsCount();
        uint256 debtPositionId = DEBT_POSITION_ID_START + debtPositionsCount - 1;

        PriceFeedMock priceFeedMock = PriceFeedMock(PRICE_FEED_MOCK_ADDRESS);

        _tenderlyUpdateConfig(owner, "priceFeed", uint256(uint160(address(priceFeedMock))));
        _tenderlyUpdatePrice(owner, priceFeedMock, 0.9e18);

        console.log("debtPositionId", debtPositionId);
    }
}
