// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {BuyCreditLimitParams, SellCreditLimitParams} from "@size/src/interfaces/ISize.sol";
import {DepositParams, WithdrawParams} from "@size/src/interfaces/ISize.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MarketMakerManager is UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20Metadata;

    address public bot;

    event BotSet(address indexed oldBot, address indexed newBot);

    error OnlyBot();

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _bot) public initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        _setBot(_bot);
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

    function deposit(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.forceApprove(address(size), amount);
        size.deposit(DepositParams({token: address(token), amount: amount, to: address(this)}));
    }

    function withdraw(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        size.withdraw(WithdrawParams({token: address(token), amount: amount, to: msg.sender}));
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

    receive() external payable {}
}
