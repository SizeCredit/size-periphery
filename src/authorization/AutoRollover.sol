// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@size/src/market/interfaces/ISize.sol";
import {DebtPosition, RESERVED_ID} from "@size/src/market/libraries/LoanLibrary.sol";
import {DataView} from "@size/src/market/SizeViewData.sol";
import {PeripheryErrors} from "src/libraries/PeripheryErrors.sol";
import {RepayParams} from "@size/src/market/libraries/actions/Repay.sol";
import {WithdrawParams, WithdrawOnBehalfOfParams} from "@size/src/market/libraries/actions/Withdraw.sol";
import {
    SellCreditMarketParams,
    SellCreditMarketOnBehalfOfParams
} from "@size/src/market/libraries/actions/SellCreditMarket.sol";
import {FlashLoanReceiverBase} from "@aave/flashloan/base/FlashLoanReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/interfaces/IPoolAddressesProvider.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "@size/src/market/libraries/Errors.sol";
import {DexSwap, SwapParams, BoringPtSellerParams} from "src/liquidator/DexSwap.sol";
import {SwapMethod} from "src/liquidator/DexSwap.sol";
import {console} from "forge-std/console.sol";
import {DepositOnBehalfOfParams, DepositParams} from "@size/src/market/libraries/actions/Deposit.sol";

contract AutoRollover is Ownable2Step, FlashLoanReceiverBase, DexSwap {
    using SafeERC20 for IERC20Metadata;
    using console for uint256;
    using console for address;
    using console for bool;

    bool public constant ROLLOVER = true;
    bool public constant REPAY = false;

    uint256 public constant EARLY_REPAYMENT_BUFFER = 1 hours;
    uint256 public constant MIN_TENOR = 1 hours;
    uint256 public constant MAX_TENOR = 7 days;

    struct RepayOperationParams {
        uint256 collateralWithdrawAmount;
        SwapParams swapParams;
    }

    struct OperationParams {
        bool isRollover;  // true for rollover, false for repay
        ISize market;
        uint256 debtPositionId;
        address onBehalfOf;
        // Rollover specific fields
        address lender;
        uint256 tenor;
        uint256 maxAPR;
        uint256 deadline;
        // Repay specific fields
        RepayOperationParams repayParams;
    }

    constructor(
        address _owner,
        IPoolAddressesProvider _addressProvider,
        address _oneInchAggregator,
        address _unoswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router
    )
        Ownable(_owner)
        FlashLoanReceiverBase(_addressProvider)
        DexSwap(_oneInchAggregator, _unoswapRouter, _uniswapV2Router, _uniswapV3Router)
    {}

    function rollover(
        ISize market,
        uint256 debtPositionId,
        address onBehalfOf,
        address lender,
        uint256 tenor,
        uint256 maxAPR,
        uint256 deadline
    ) external onlyOwner {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);
        DataView memory data = market.data();

        if (debtPosition.dueDate > block.timestamp + EARLY_REPAYMENT_BUFFER) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        if (tenor < MIN_TENOR || tenor > MAX_TENOR) {
            revert Errors.TENOR_OUT_OF_RANGE(tenor, MIN_TENOR, MAX_TENOR);
        }

        OperationParams memory operationParams = OperationParams({
            isRollover: ROLLOVER,
            market: market,
            debtPositionId: debtPositionId,
            onBehalfOf: onBehalfOf,
            lender: lender,
            tenor: tenor,
            maxAPR: maxAPR,
            deadline: deadline,
            repayParams: RepayOperationParams({
                collateralWithdrawAmount: 0,
                swapParams: SwapParams({
                    method: SwapMethod.OneInch,
                    data: "",
                    minimumReturnAmount: 0,
                    deadline: 0,
                    hasPtSellerStep: false,
                    ptSellerParams: BoringPtSellerParams({
                        market: address(0),
                        tokenOutIsYieldToken: false
                    })
                })
            })
        });

        bytes memory params = abi.encode(operationParams);

        address[] memory assets = new address[](1);
        assets[0] = address(data.underlyingBorrowToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtPosition.futureValue;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function repay(
        ISize market,
        uint256 debtPositionId,
        address onBehalfOf,
        uint256 collateralWithdrawAmount,
        SwapParams memory swapParams
    ) external onlyOwner {
        DebtPosition memory debtPosition = market.getDebtPosition(debtPositionId);
        DataView memory data = market.data();

        if (debtPosition.dueDate > block.timestamp + EARLY_REPAYMENT_BUFFER) {
            revert PeripheryErrors.AUTO_REPAY_TOO_EARLY(debtPosition.dueDate, block.timestamp);
        }

        OperationParams memory operationParams = OperationParams({
            isRollover: REPAY,
            market: market,
            debtPositionId: debtPositionId,
            onBehalfOf: onBehalfOf,
            lender: address(0),
            tenor: 0,
            maxAPR: 0,
            deadline: 0,
            repayParams: RepayOperationParams({
                collateralWithdrawAmount: collateralWithdrawAmount,
                swapParams: swapParams
            })
        });

        bytes memory params = abi.encode(operationParams);

        address[] memory assets = new address[](1);
        assets[0] = address(data.underlyingBorrowToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtPosition.futureValue;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        console.log("\n=== AutoRollover.executeOperation ===");
        console.log("Assets[0] (Token Address):", assets[0]);
        console.log("Token Symbol:", IERC20Metadata(assets[0]).symbol());
        console.log("Token Decimals:", IERC20Metadata(assets[0]).decimals());
        console.log("Amounts[0]:", amounts[0]);
        console.log("Premiums[0]:", premiums[0]);
        console.log("Initiator:", initiator);
        console.log("Initiator Token Balance:", IERC20Metadata(assets[0]).balanceOf(initiator));
        console.log("Contract Token Balance:", IERC20Metadata(assets[0]).balanceOf(address(this)));
        console.log("POOL Token Balance:", IERC20Metadata(assets[0]).balanceOf(address(POOL)));

        if (msg.sender != address(POOL)) {
            console.log("Error: Not AAVE Pool");
            revert PeripheryErrors.NOT_AAVE_POOL();
        }
        if (initiator != address(this)) {
            console.log("Error: Not Initiator");
            revert PeripheryErrors.NOT_INITIATOR();
        }

        OperationParams memory operationParams = abi.decode(params, (OperationParams));
        console.log("Operation Type:", operationParams.isRollover ? "ROLLOVER" : "REPAY");
        console.log("Market:", address(operationParams.market));
        console.log("Debt Position ID:", operationParams.debtPositionId);
        console.log("On Behalf Of:", operationParams.onBehalfOf);

        if (operationParams.isRollover) {
            console.log("\n=== Executing Rollover ===");
            console.log("New Future Value:", amounts[0] + premiums[0]);
            console.log("Lender:", operationParams.lender);
            console.log("Tenor:", operationParams.tenor);
            console.log("Max APR:", operationParams.maxAPR);
            console.log("Deadline:", operationParams.deadline);

            console.log("Calling sellCreditMarketOnBehalfOf...");
            operationParams.market.sellCreditMarketOnBehalfOf(
                SellCreditMarketOnBehalfOfParams({
                    params: SellCreditMarketParams({
                        lender: operationParams.lender,
                        creditPositionId: RESERVED_ID,
                        amount: amounts[0] + premiums[0],
                        tenor: operationParams.tenor,
                        maxAPR: operationParams.maxAPR,
                        deadline: operationParams.deadline,
                        exactAmountIn: false
                    }),
                    onBehalfOf: operationParams.onBehalfOf,
                    recipient: address(this)
                })
            );
            console.log("sellCreditMarketOnBehalfOf succeeded");

            console.log("Calling repay...");
            operationParams.market.repay(
                RepayParams({debtPositionId: operationParams.debtPositionId, borrower: operationParams.onBehalfOf})
            );
            console.log("repay succeeded");

            console.log("Approving flash loan repayment...");
            IERC20Metadata(assets[0]).forceApprove(address(POOL), amounts[0] + premiums[0]);
            console.log("Approval succeeded");
        } else {
            console.log("\n=== Executing Repay ===");
            console.log("Total Debt (including premium):", amounts[0] + premiums[0]);
            console.log("Collateral Withdraw Amount:", operationParams.repayParams.collateralWithdrawAmount);
            console.log("Swap Method:", uint8(operationParams.repayParams.swapParams.method));
            console.log("Swap Minimum Return:", operationParams.repayParams.swapParams.minimumReturnAmount);
            console.log("Swap Deadline:", operationParams.repayParams.swapParams.deadline);

            // First approve the protocol to spend our borrow token
            console.log("Approving protocol to spend borrow token...");
            IERC20Metadata(assets[0]).forceApprove(address(operationParams.market), amounts[0]);
            console.log("Protocol approval succeeded");

            // Then deposit the borrow token into the protocol
            console.log("Depositing borrow token...");
            operationParams.market.depositOnBehalfOf(
                DepositOnBehalfOfParams({
                    params: DepositParams({
                        token: assets[0],
                        amount: amounts[0],
                        to: address(this)
                    }),
                    onBehalfOf: address(this)
                })
            );
            console.log("Deposit succeeded");

            // Log balances after deposit
            console.log("\n=== Post-Deposit Balances ===");
            console.log("Contract USDC Balance:", IERC20Metadata(assets[0]).balanceOf(address(this)));
            console.log("Contract USDC Allowance:", IERC20Metadata(assets[0]).allowance(address(this), address(operationParams.market)));
            console.log("Borrower USDC Balance:", IERC20Metadata(assets[0]).balanceOf(operationParams.onBehalfOf));
            console.log("Borrower USDC Allowance:", IERC20Metadata(assets[0]).allowance(operationParams.onBehalfOf, address(operationParams.market)));
            console.log("Market USDC Balance:", IERC20Metadata(assets[0]).balanceOf(address(operationParams.market)));
            console.log("Borrower aToken Balance:", IERC20Metadata(operationParams.market.data().borrowAToken).balanceOf(operationParams.onBehalfOf));
            console.log("Contract aToken Balance:", IERC20Metadata(operationParams.market.data().borrowAToken).balanceOf(address(this)));

            console.log("Calling repay...");
            operationParams.market.repay(
                RepayParams({debtPositionId: operationParams.debtPositionId, borrower: operationParams.onBehalfOf})
            );
            console.log("repay succeeded");

            console.log("Calling withdraw...");
            console.log("Withdraw Parameters:");
            console.log("Token:", address(operationParams.market.data().underlyingCollateralToken));
            console.log("Amount:", operationParams.repayParams.collateralWithdrawAmount);
            console.log("To:", address(this));
            console.log("Contract Collateral Balance Before:", IERC20Metadata(operationParams.market.data().underlyingCollateralToken).balanceOf(address(this)));
            console.log("Borrower Collateral Balance Before:", IERC20Metadata(operationParams.market.data().underlyingCollateralToken).balanceOf(operationParams.onBehalfOf));
            console.log("Market Collateral Balance Before:", IERC20Metadata(operationParams.market.data().underlyingCollateralToken).balanceOf(address(operationParams.market)));
            
            operationParams.market.withdrawOnBehalfOf(
                WithdrawOnBehalfOfParams({
                    params: WithdrawParams({
                        token: address(operationParams.market.data().underlyingCollateralToken),
                        amount: operationParams.repayParams.collateralWithdrawAmount,
                        to: address(this)
                    }),
                    onBehalfOf: operationParams.onBehalfOf
                })
            );
            console.log("withdraw succeeded");
            
            console.log("Contract Collateral Balance After:", IERC20Metadata(operationParams.market.data().underlyingCollateralToken).balanceOf(address(this)));
            console.log("Borrower Collateral Balance After:", IERC20Metadata(operationParams.market.data().underlyingCollateralToken).balanceOf(operationParams.onBehalfOf));
            console.log("Market Collateral Balance After:", IERC20Metadata(operationParams.market.data().underlyingCollateralToken).balanceOf(address(operationParams.market)));

            console.log("Calling _swapCollateral...");
            _swapCollateral(
                address(operationParams.market.data().underlyingCollateralToken),
                address(operationParams.market.data().underlyingBorrowToken),
                operationParams.repayParams.swapParams
            );
            console.log("_swapCollateral succeeded");

            console.log("Approving flash loan repayment...");
            IERC20Metadata(assets[0]).forceApprove(address(POOL), amounts[0] + premiums[0]);
            console.log("Approval succeeded");
        }

        console.log("\n=== Operation Completed Successfully ===");
        return true;
    }
}
