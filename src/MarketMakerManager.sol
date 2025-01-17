// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {ISizeView} from "@size/src/interfaces/ISizeView.sol";
import {
    DepositParams, WithdrawParams, BuyCreditLimitParams, SellCreditLimitParams
} from "@size/src/interfaces/ISize.sol";
import {ISizeFactory} from "@size/src/v1.5/interfaces/ISizeFactory.sol";
import {VariablePoolBorrowRateParams} from "@src/libraries/YieldCurveLibrary.sol";
import {YieldCurve} from "@size/src/libraries/YieldCurveLibrary.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {YieldCurvesValidationLibrary} from "src/libraries/YieldCurvesValidationLibrary.sol";
import {MarketMakerManagerFactory} from "src/MarketMakerManagerFactory.sol";

contract MarketMakerManager is Initializable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    MarketMakerManagerFactory public factory;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event FactorySet(address indexed oldFactory, address indexed newFactory);

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyBotWhenNotPausedOrOwner();
    error InvalidCurves();
    error OnlyNullMultipliersAllowed();
    error OnlyEmergencyWithdrawerOrOwner();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR/INITIALIZER
    //////////////////////////////////////////////////////////////*/

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(MarketMakerManagerFactory _factory, address _owner) public initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);

        _setFactory(_factory);
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyBotWhenNotPausedOrOwner() {
        if ((msg.sender == factory.bot() && !factory.paused()) || msg.sender == owner()) {
            _;
        } else {
            revert OnlyBotWhenNotPausedOrOwner();
        }
    }

    modifier onlyEmergencyWithdrawerOrOwner() {
        if (!factory.isEmergencyWithdrawer(msg.sender) && msg.sender != owner()) {
            revert OnlyEmergencyWithdrawerOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.forceApprove(address(size), amount);
        size.deposit(DepositParams({token: address(token), amount: amount, to: address(this)}));
    }

    function withdraw(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        size.withdraw(WithdrawParams({token: address(token), amount: amount, to: msg.sender}));
    }

    /*//////////////////////////////////////////////////////////////
                            BOT (NOT PAUSED)/OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositDirect(ISize size, IERC20Metadata token, uint256 amount) external onlyBotWhenNotPausedOrOwner {
        token.forceApprove(address(size), amount);
        size.deposit(DepositParams({token: address(token), amount: amount, to: address(this)}));
    }

    function buyCreditLimit(ISize size, BuyCreditLimitParams memory params) external onlyBotWhenNotPausedOrOwner {
        _validateCurvesIsBelow(
            ISizeView(address(size)).getUserView(address(this)).user.borrowOffer.curveRelativeTime,
            params.curveRelativeTime
        );
        size.buyCreditLimit(params);
    }

    function sellCreditLimit(ISize size, SellCreditLimitParams memory params) external onlyBotWhenNotPausedOrOwner {
        _validateCurvesIsBelow(
            params.curveRelativeTime,
            ISizeView(address(size)).getUserView(address(this)).user.loanOffer.curveRelativeTime
        );
        size.sellCreditLimit(params);
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY WITHDRAWER/OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function emergencyWithdraw() external onlyEmergencyWithdrawerOrOwner {
        _emergencyWithdrawToken(address(0));
    }

    function emergencyWithdrawToken(address token) external onlyEmergencyWithdrawerOrOwner {
        _emergencyWithdrawToken(token);
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    function _setFactory(MarketMakerManagerFactory _factory) private {
        emit FactorySet(address(factory), address(_factory));
        factory = _factory;
    }

    /// @param token The token to emergency withdraw. If token is address(0), all tokens will be withdrawn.
    function _emergencyWithdrawToken(address token) private {
        ISizeFactory sizeFactory = ISizeFactory(factory.sizeFactory());
        ISize[] memory markets = sizeFactory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            IERC20Metadata underlyingBorrowToken = markets[i].data().underlyingBorrowToken;
            if (address(underlyingBorrowToken) != token && token != address(0)) {
                continue;
            }
            uint256 borrowATokenBalance = markets[i].getUserView(address(this)).borrowATokenBalance;
            if (borrowATokenBalance > 0) {
                try markets[i].withdraw(
                    WithdrawParams({token: address(underlyingBorrowToken), amount: borrowATokenBalance, to: owner()})
                ) {} catch {
                    continue;
                }
            }
            uint256 balance = underlyingBorrowToken.balanceOf(address(this));
            if (balance > 0) {
                underlyingBorrowToken.safeTransfer(owner(), balance);
            }
        }
    }
}
