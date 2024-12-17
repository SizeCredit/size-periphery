// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {ISizeView} from "@size/src/interfaces/ISizeView.sol";
import {
    DepositParams, WithdrawParams, BuyCreditLimitParams, SellCreditLimitParams
} from "@size/src/interfaces/ISize.sol";
import {VariablePoolBorrowRateParams} from "@src/libraries/YieldCurveLibrary.sol";
import {YieldCurve} from "@size/src/libraries/YieldCurveLibrary.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {YieldCurvesValidationLibrary} from "src/libraries/YieldCurvesValidationLibrary.sol";

contract MarketMakerManager is Ownable2StepUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20Metadata;

    address public bot;

    event BotSet(address indexed oldBot, address indexed newBot);

    error OnlyBot();
    error InvalidCurves();
    error OnlyNullMultipliersAllowed();

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _bot) public initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);
        __Pausable_init();
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function deposit(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.forceApprove(address(size), amount);
        size.deposit(DepositParams({token: address(token), amount: amount, to: address(this)}));
    }

    function withdraw(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        size.withdraw(WithdrawParams({token: address(token), amount: amount, to: msg.sender}));
    }

    function buyCreditLimit(ISize size, BuyCreditLimitParams memory params) external onlyBot whenNotPaused {
        _validateCurvesIsBelow(
            ISizeView(address(size)).getUserView(address(this)).user.borrowOffer.curveRelativeTime,
            params.curveRelativeTime
        );
        size.buyCreditLimit(params);
    }

    function sellCreditLimit(ISize size, SellCreditLimitParams memory params) external onlyBot whenNotPaused {
        _validateCurvesIsBelow(
            params.curveRelativeTime,
            ISizeView(address(size)).getUserView(address(this)).user.loanOffer.curveRelativeTime
        );
        size.sellCreditLimit(params);
    }

    function _validateNullMultipliers(YieldCurve memory curve) private pure {
        for (uint256 i = 0; i < curve.marketRateMultipliers.length; i++) {
            if (curve.marketRateMultipliers[i] != 0) {
                revert OnlyNullMultipliersAllowed();
            }
        }
    }

    function _validateCurvesIsBelow(YieldCurve memory a, YieldCurve memory b) private view {
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        _validateNullMultipliers(a);
        _validateNullMultipliers(b);
        if (!YieldCurvesValidationLibrary.isBelow(a, b, variablePoolBorrowRateParams)) {
            revert InvalidCurves();
        }
    }

    function _setBot(address _bot) private {
        emit BotSet(bot, _bot);
        bot = _bot;
    }
}
