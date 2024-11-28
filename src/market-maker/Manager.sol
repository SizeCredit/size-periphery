// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ISize} from "@size/src/interfaces/ISize.sol";
import {BuyCreditLimitParams, SellCreditLimitParams} from "@size/src/interfaces/ISize.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";
import {BaseGuard} from "@safe/contracts/base/GuardManager.sol";
import {Safe} from "@safe/contracts/Safe.sol";

interface ISizeRegistry {
    function isMarket(address candidate) external view returns (bool);
}

contract Manager is Ownable2Step, BaseGuard {
    ISizeRegistry public immutable sizeRegistry;
    address public proposer;

    event ProposerSet(address indexed oldProposer, address indexed newProposer);

    error OnlyProposer();
    error InvalidTarget();
    error InvalidSelector();
    error InvalidData();

    constructor(address _owner, address _proposer, ISizeRegistry _sizeRegistry) Ownable(_owner) {
        proposer = _proposer;
        sizeRegistry = _sizeRegistry;
    }

    function setProposer(address _proposer) external onlyOwner {
        emit ProposerSet(proposer, _proposer);
        proposer = _proposer;
    }

    /// @notice Checks if the transaction is valid by a 1/2 multisig
    ///         If the proposer is the signer, then it can only call buyCreditMarket or sellCreditMarket on Size markets
    ///         If the owner is the signer, then it can always execute the transaction
    /// @dev See https://github.com/safe-global/safe-smart-account/blob/786dadce5ca12fd7f1340c3a7fe6916eb807128a/contracts/examples/guards/DebugTransactionGuard.sol
    ///      for details about how to get the transaction hash on a Safe Guard
    function checkTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address /* msgSender */
    ) external view {
        Safe safe = Safe(payable(msg.sender));
        uint256 nonce = safe.nonce() - 1;
        bytes32 txHash = safe.getTransactionHash(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce);
        bool isProposer = SignatureChecker.isValidSignatureNow(proposer, txHash, signatures);

        if (!isProposer) {
            return;
        }

        bool isMarket = sizeRegistry.isMarket(to);
        if (!isMarket) {
            revert InvalidTarget();
        }

        if (data.length < 4) {
            revert InvalidData();
        }

        bytes4 selector = bytes4(data[:4]);

        if (selector != ISize.buyCreditMarket.selector && selector != ISize.sellCreditMarket.selector) {
            revert InvalidSelector();
        }
    }

    function checkAfterExecution(bytes32, /* txHash */ bool /* success */ ) external pure {
        // no after execution checks
    }
}
