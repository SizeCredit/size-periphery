// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {ISizeFactory} from "@size/src/v1.5/interfaces/ISizeFactory.sol";
import {BuyCreditLimitParams, SellCreditLimitParams} from "@size/src/interfaces/ISize.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {WithdrawParams} from "@size/src/interfaces/ISize.sol";
import {DataView} from "@size/src/SizeViewData.sol";

contract Manager is UUPSUpgradeable, Ownable2StepUpgradeable {
    ISizeFactory public sizeFactory;
    address public bot;

    event BotSet(address indexed oldBot, address indexed newBot);
    event FactorySet(ISizeFactory indexed oldFactory, ISizeFactory indexed newFactory);

    error NullAddress();
    error ArrayLengthsMismatch();
    error OnlyBot();

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _bot, ISizeFactory _sizeFactory) public initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        _setBot(_bot);
        _setFactory(_sizeFactory);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyBot() {
        if (msg.sender != bot) {
            revert OnlyBot();
        }
        _;
    }

    function setBot(address _bot) external onlyOwner {
        _setBot(_bot);
    }

    function setFactory(ISizeFactory _sizeFactory) external onlyOwner {
        _setFactory(_sizeFactory);
    }

    function _setBot(address _bot) internal {
        emit BotSet(bot, _bot);
        bot = _bot;
    }

    function _setFactory(ISizeFactory _sizeFactory) internal {
        emit FactorySet(sizeFactory, _sizeFactory);
        sizeFactory = _sizeFactory;
    }

    function proxy(address target, bytes memory data) public onlyOwner returns (bytes memory returnData) {
        if (target == address(0)) {
            revert NullAddress();
        }
        bool success;
        (success, returnData) = address(target).call(data);
        Address.verifyCallResult(success, returnData);
    }

    function proxy(address target, bytes memory data, uint256 value)
        public
        onlyOwner
        returns (bytes memory returnData)
    {
        if (target == address(0)) {
            revert NullAddress();
        }
        bool success;
        (success, returnData) = address(target).call{value: value}(data);
        Address.verifyCallResult(success, returnData);
    }

    function proxy(address[] memory targets, bytes[] memory datas)
        public
        onlyOwner
        returns (bytes[] memory returnDatas)
    {
        if (targets.length != datas.length) {
            revert ArrayLengthsMismatch();
        }

        returnDatas = new bytes[](datas.length);
        bool success;
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) {
                revert NullAddress();
            }
            // slither-disable-next-line calls-loop
            (success, returnDatas[i]) = address(targets[i]).call(datas[i]);
            Address.verifyCallResult(success, returnDatas[i]);
        }
    }

    function emergencyWithdraw() external onlyOwner {
        ISize[] memory sizes = sizeFactory.getMarkets();
        for (uint256 i = 0; i < sizes.length; i++) {
            DataView memory data = sizes[i].data();
            sizes[i].withdraw(
                WithdrawParams({to: owner(), token: address(data.underlyingCollateralToken), amount: type(uint256).max})
            );
            sizes[i].withdraw(
                WithdrawParams({to: owner(), token: address(data.underlyingBorrowToken), amount: type(uint256).max})
            );
        }
    }

    function buyCreditLimit(ISize size, BuyCreditLimitParams memory params) external onlyBot {
        size.buyCreditLimit(params);
    }

    function sellCreditLimit(ISize size, SellCreditLimitParams memory params) external onlyBot {
        size.sellCreditLimit(params);
    }

    receive() external payable {}
}
