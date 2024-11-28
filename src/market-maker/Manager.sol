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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Manager is UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    ISizeFactory public sizeFactory;
    address public bot;

    event BotSet(address indexed oldBot, address indexed newBot);
    event FactorySet(ISizeFactory indexed oldFactory, ISizeFactory indexed newFactory);

    error NullAddress();
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

    function deposit(ISize size, DepositParams memory params) external onlyOwner {
        params.token.safeTransferFrom(msg.sender, address(this), params.amount);
        size.deposit(params);
    }

    function withdraw(ISize size, WithdrawParams memory params) external onlyOwner {
        size.withdraw(params);
    }

    function buyCreditLimit(ISize size, BuyCreditLimitParams memory params) external onlyBot {
        size.buyCreditLimit(params);
    }

    function sellCreditLimit(ISize size, SellCreditLimitParams memory params) external onlyBot {
        size.sellCreditLimit(params);
    }

    function _setBot(address _bot) internal {
        emit BotSet(bot, _bot);
        bot = _bot;
    }

    function _setFactory(ISizeFactory _sizeFactory) internal {
        emit FactorySet(sizeFactory, _sizeFactory);
        sizeFactory = _sizeFactory;
    }

    receive() external payable {}
}
