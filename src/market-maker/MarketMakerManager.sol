// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PAUSER_ROLE} from "@size/src/Size.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {ISizeAdmin} from "@size/src/interfaces/ISizeAdmin.sol";
import {ISizeView} from "@size/src/interfaces/ISizeView.sol";
import {DataView, UserView} from "@size/src/SizeViewData.sol";
import {
    DepositParams, WithdrawParams, BuyCreditLimitParams, SellCreditLimitParams
} from "@size/src/interfaces/ISize.sol";
import {ISizeFactory} from "@size/src/v1.5/interfaces/ISizeFactory.sol";
import {VariablePoolBorrowRateParams} from "@src/libraries/YieldCurveLibrary.sol";
import {YieldCurve} from "@size/src/libraries/YieldCurveLibrary.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {YieldCurvesValidationLibrary} from "src/libraries/YieldCurvesValidationLibrary.sol";
import {MarketMakerManagerFactory} from "src/market-maker/MarketMakerManagerFactory.sol";

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
    event CallFailed(address indexed target, bytes data);

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

    /// @notice Deposit tokens into a Size market
    /// @param size The Size market to deposit into
    /// @param token The token to deposit
    /// @param amount The amount of tokens to deposit
    /// @dev This function does not support ETH deposits, but WETH can be used
    function deposit(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.forceApprove(address(size), amount);
        size.deposit(DepositParams({token: address(token), amount: amount, to: address(this)}));
    }

    /// @notice Withdraw tokens from a Size market
    /// @param size The Size market to withdraw from
    /// @param token The token to withdraw
    /// @param amount The amount of tokens to withdraw
    function withdraw(ISize size, IERC20Metadata token, uint256 amount) external onlyOwner {
        size.withdraw(WithdrawParams({token: address(token), amount: amount, to: owner()}));
    }

    /*//////////////////////////////////////////////////////////////
                            BOT (NOT PAUSED)/OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit tokens held by the manager contract into a Size market
    /// @param size The Size market to deposit into
    /// @param token The token to deposit
    /// @param amount The amount of tokens to deposit
    /// @dev This function does not support ETH deposits, but WETH can be used
    /// @dev This function should be called after a `token.transfer` from the owner to this contract
    function depositDirect(ISize size, IERC20Metadata token, uint256 amount) external onlyBotWhenNotPausedOrOwner {
        token.forceApprove(address(size), amount);
        size.deposit(DepositParams({token: address(token), amount: amount, to: address(this)}));
    }

    /// @notice Create a buy credit limit curve for a Size market
    /// @param size The Size market to create a buy credit limit curve for
    /// @param params The parameters for the buy credit limit curve
    function buyCreditLimit(ISize size, BuyCreditLimitParams memory params) external onlyBotWhenNotPausedOrOwner {
        _validateCurvesIsBelow(
            ISizeView(address(size)).getUserView(address(this)).user.borrowOffer.curveRelativeTime,
            params.curveRelativeTime
        );
        size.buyCreditLimit(params);
    }

    /// @notice Create a sell credit limit curve for a Size market
    /// @param size The Size market to create a sell credit limit curve for
    /// @param params The parameters for the sell credit limit curve
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

    /// @notice Emergency withdraw all tokens from the manager contract
    /// @dev This function will withdraw all tokens from all markets
    function emergencyWithdraw() external onlyEmergencyWithdrawerOrOwner {
        _emergencyWithdraw(IERC20Metadata(address(0)));
    }

    /// @notice Emergency withdraw a specific token from the manager contract
    /// @param token The token to withdraw
    function emergencyWithdraw(IERC20Metadata token) external onlyEmergencyWithdrawerOrOwner {
        _emergencyWithdraw(token);
    }

    /// @notice Recover tokens from the manager contract
    /// @param token The token to recover
    function recoverTokens(IERC20Metadata token) external onlyEmergencyWithdrawerOrOwner {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validate that all multipliers in a curve are zero
    /// @param curve The curve to validate
    function _validateNullMultipliers(YieldCurve memory curve) private pure {
        for (uint256 i = 0; i < curve.marketRateMultipliers.length; i++) {
            if (curve.marketRateMultipliers[i] != 0) {
                revert OnlyNullMultipliersAllowed();
            }
        }
    }

    /// @notice Validate that one curve is below another
    /// @param a The first curve
    /// @param b The second curve
    /// @dev Also validates that both curves have no multipliers
    function _validateCurvesIsBelow(YieldCurve memory a, YieldCurve memory b) private view {
        VariablePoolBorrowRateParams memory variablePoolBorrowRateParams;
        _validateNullMultipliers(a);
        _validateNullMultipliers(b);
        if (!YieldCurvesValidationLibrary.isBelow(a, b, variablePoolBorrowRateParams)) {
            revert InvalidCurves();
        }
    }

    /// @notice Set the factory for the manager contract
    /// @param _factory The new factory
    function _setFactory(MarketMakerManagerFactory _factory) private {
        emit FactorySet(address(factory), address(_factory));
        factory = _factory;
    }

    /// @notice Emergency withdraw a specific token from all Size markets
    /// @param token The token to emergency withdraw. If token is address(0), all tokens will be withdrawn.
    function _emergencyWithdraw(IERC20Metadata token) private {
        ISizeFactory sizeFactory = ISizeFactory(factory.sizeFactory());
        ISize[] memory markets = sizeFactory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            ISize size = markets[i];
            DataView memory data = size.data();
            UserView memory userView = ISizeView(address(size)).getUserView(address(this));
            IERC20Metadata underlyingBorrowToken = data.underlyingBorrowToken;
            IERC20Metadata underlyingCollateralToken = data.underlyingCollateralToken;

            bool wasPausedAndHasPauserRole = _tryUnpause(size);

            if (token == IERC20Metadata(address(0))) {
                _tryWithdrawBorrowToken(size, data, userView);
                _tryWithdrawCollateralToken(size, data, userView);
            } else {
                if (underlyingBorrowToken == token) {
                    _tryWithdrawBorrowToken(size, data, userView);
                } else if (underlyingCollateralToken == token) {
                    _tryWithdrawCollateralToken(size, data, userView);
                }
            }

            if (wasPausedAndHasPauserRole) {
                _tryPause(size);
            }
        }
    }

    /// @notice Try to unpause a Size market
    /// @param size The Size market to unpause
    /// @return wasPausedAndHasPauserRole True if the market was paused and the caller has the PAUSER_ROLE
    function _tryUnpause(ISize size) private returns (bool wasPausedAndHasPauserRole) {
        wasPausedAndHasPauserRole = PausableUpgradeable(address(size)).paused()
            && AccessControlUpgradeable(address(size)).hasRole(PAUSER_ROLE, address(this));
        if (wasPausedAndHasPauserRole) {
            _tryCall(address(size), abi.encodeCall(ISizeAdmin.unpause, ()));
        }
    }

    /// @notice Try to pause a Size market
    /// @param size The Size market to pause
    /// @dev Assumes the caller has the PAUSER_ROLE
    /// @dev Should only be called if the market was unpaused first
    function _tryPause(ISize size) private {
        _tryCall(address(size), abi.encodeCall(ISizeAdmin.pause, ()));
    }

    /// @notice Try to withdraw a borrow token from a Size market
    /// @param size The Size market to withdraw from
    /// @param data The data of the market
    /// @param userView The user view of the market
    function _tryWithdrawBorrowToken(ISize size, DataView memory data, UserView memory userView) private {
        uint256 borrowATokenBalance = userView.borrowATokenBalance;
        if (borrowATokenBalance > 0) {
            _tryCall(
                address(size),
                abi.encodeCall(
                    ISize.withdraw,
                    WithdrawParams({
                        token: address(data.underlyingBorrowToken),
                        amount: borrowATokenBalance,
                        to: owner()
                    })
                )
            );
        }
        uint256 balance = data.underlyingBorrowToken.balanceOf(address(this));
        if (balance > 0) {
            _tryCall(address(data.underlyingBorrowToken), abi.encodeCall(IERC20.transfer, (owner(), balance)));
        }
    }

    /// @notice Try to withdraw a collateral token from a Size market
    /// @param size The Size market to withdraw from
    /// @param data The data of the market
    /// @param userView The user view of the market
    function _tryWithdrawCollateralToken(ISize size, DataView memory data, UserView memory userView) private {
        uint256 collateralTokenBalance = userView.collateralTokenBalance;
        if (collateralTokenBalance > 0) {
            _tryCall(
                address(size),
                abi.encodeCall(
                    ISize.withdraw,
                    WithdrawParams({
                        token: address(data.underlyingCollateralToken),
                        amount: collateralTokenBalance,
                        to: owner()
                    })
                )
            );
        }
        uint256 balance = data.underlyingCollateralToken.balanceOf(address(this));
        if (balance > 0) {
            _tryCall(address(data.underlyingCollateralToken), abi.encodeCall(IERC20.transfer, (owner(), balance)));
        }
    }

    /// @notice Try to call a function on a target
    /// @param target The target to call
    /// @param data The data to call
    /// @dev This function does not revert, it only emits an event if it fails
    function _tryCall(address target, bytes memory data) private {
        // slither-disable-next-line unused-return
        (bool success,) = target.call(data);
        if (!success) {
            emit CallFailed(target, data);
        }
    }
}
