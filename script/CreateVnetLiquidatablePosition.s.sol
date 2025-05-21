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
import {SellCreditMarketParams} from "@src/market/libraries/actions/SellCreditMarket.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";
import {ICreateX} from "./interfaces/ICreateX.sol";

contract CreateVnetLiquidatablePosition is Script, Addresses {
    using Tenderly for *;

    address owner;
    Tenderly.Client tenderly;
    string vnetId;
    ISizeFactory sizeFactory;
    ISize size;

    address borrower = address(0x1111);
    address lender = address(0x2222);

    ICreateX CreateX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    constructor() {
        vnetId = vm.envString("VNET_ID");
        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        Tenderly.VirtualTestnet memory vnet = tenderly.getVirtualTestnetById(vnetId);
        vm.createSelectFork(vnet.getAdminRpcUrl());

        sizeFactory = ISizeFactory(addresses[block.chainid][CONTRACT.SIZE_FACTORY]);
        owner = addresses[block.chainid][CONTRACT.SIZE_GOVERNANCE];
    }

    function _tenderlyDeployPriceFeedMock(address _owner) internal returns (address) {
        bytes memory initCode = abi.encodePacked(type(PriceFeedMock).creationCode, abi.encode(_owner));
        // https://github.com/pcaversaccio/createx/blob/f83e2a40dbc2db26804e9c8540cd7f1bfd7b323c/src/CreateX.sol#L874
        bytes32 salt = bytes32(abi.encodePacked(_owner, hex"00", hex"1212121212121212121212"));
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 guardedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(_owner))), salt));
        tenderly.sendTransaction(
            vnetId, _owner, address(CreateX), abi.encodeCall(ICreateX.deployCreate2, (salt, initCode))
        );
        address computedAddress = CreateX.computeCreate2Address(guardedSalt, initCodeHash);
        return computedAddress;
    }

    function _tenderlyDeposit(address _user, address _token, uint256 _amount) internal {
        Tenderly.VirtualTestnet memory vnet = tenderly.getVirtualTestnetById(vnetId);
        tenderly.setErc20Balance(vnet, _token, _user, _amount);
        tenderly.sendTransaction(vnetId, _user, _token, abi.encodeCall(IERC20.approve, (address(size), _amount)));
        tenderly.sendTransaction(
            vnetId,
            _user,
            address(size),
            abi.encodeCall(ISize.deposit, (DepositParams({token: _token, amount: _amount, to: _user})))
        );
    }

    function _tenderlyBuyCreditLimit(address _user, uint256 _maxDueDate, YieldCurve memory _curve) internal {
        tenderly.sendTransaction(
            vnetId,
            _user,
            address(size),
            abi.encodeCall(
                ISize.buyCreditLimit, (BuyCreditLimitParams({maxDueDate: _maxDueDate, curveRelativeTime: _curve}))
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

    function _tenderlyUpdatePrice(address _owner, address _priceFeedMock, uint256 _price) internal {
        tenderly.sendTransaction(vnetId, _owner, _priceFeedMock, abi.encodeCall(PriceFeedMock.setPrice, (_price)));
    }

    function run() external {
        address priceFeedMock = _tenderlyDeployPriceFeedMock(owner);

        for (uint256 i = 0; i < sizeFactory.getMarkets().length; i++) {
            size = sizeFactory.getMarket(i);
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

            _tenderlyUpdateConfig(owner, "priceFeed", uint256(uint160(address(priceFeedMock))));
            _tenderlyUpdatePrice(owner, priceFeedMock, 1.0e18);

            _tenderlyBuyCreditLimit(lender, block.timestamp + 90 days, curve);
            _tenderlySellCreditMarket(borrower, lender, RESERVED_ID, borrowAmount, 45 days, false);

            _tenderlyUpdatePrice(owner, priceFeedMock, 0.9e18);
        }
    }
}
