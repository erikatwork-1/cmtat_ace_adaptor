// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IACERuleEngineAdapter} from "../interfaces/IACERuleEngineAdapter.sol";

/**
 * @title ACERuleEngineAdapter
 * @author CMTAT ACE Adapter
 * @notice Drop-in replacement for CMTAT RuleEngine that delegates compliance checks to Chainlink ACE PolicyEngine.
 * @dev This adapter implements the CMTAT IRuleEngine interface (via IEIP1404Wrapper) while using
 *      ACE PolicyEngine for the actual compliance validation. It enables existing CMTAT tokens to
 *      use ACE policies without modifying the token contract.
 *
 * ## Architecture
 * ```
 * CMTAT Token
 *     │
 *     ▼
 * ACERuleEngineAdapter.validateTransfer(from, to, amount)
 *     │
 *     ▼
 * Construct Payload { selector, sender, data, context }
 *     │
 *     ▼
 * PolicyEngine.check(payload)
 *     │
 *     ├─── Policies allow ──► Return true (code 0)
 *     │
 *     └─── Policy rejects ──► Return false (code 1+)
 * ```
 *
 * ## Key Features
 * - Implements CMTAT IRuleEngine interface for seamless integration
 * - Maps ACE policy results to CMTAT restriction codes
 * - Supports custom restriction messages
 * - Uses Ownable2Step for secure admin transfers
 *
 * ## Known Limitations
 *
 * **CRITICAL: VIEW Function Constraint**
 * CMTAT's validateTransfer() is a VIEW function. This means:
 * - ✅ Can use PolicyEngine.check() (read-only)
 * - ❌ Cannot use PolicyEngine.run() (state-changing)
 * - ❌ postRun() hooks will NOT execute
 * - ❌ Stateful policies won't update (VolumePolicy, VolumeRatePolicy)
 *
 * **Other Limitations:**
 * - No context parameter (CMTAT doesn't provide context bytes)
 * - Error message granularity is reduced when mapping to restriction codes
 * - Selector detection is inferred from parameters
 *
 * ## Compatible Policies
 * - AllowPolicy, RejectPolicy, MaxPolicy, IntervalPolicy
 * - PausePolicy, OnlyOwnerPolicy, OnlyAuthorizedSenderPolicy
 * - BypassPolicy, SecureMintPolicy, RoleBasedAccessControlPolicy
 * - CredentialRegistryIdentityValidatorPolicy
 *
 * ## Partially Compatible Policies
 * - VolumePolicy (reads work, tracking won't update)
 * - VolumeRatePolicy (reads work, accumulation won't happen)
 *
 * @custom:security-contact security@example.com
 */
contract ACERuleEngineAdapter is IACERuleEngineAdapter, Ownable2Step {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IACERuleEngineAdapter
    uint8 public constant override RESTRICTION_CODE_OK = 0;

    /// @inheritdoc IACERuleEngineAdapter
    uint8 public constant override RESTRICTION_CODE_POLICY_REJECTED = 1;

    /// @inheritdoc IACERuleEngineAdapter
    uint8 public constant override RESTRICTION_CODE_UNKNOWN_ERROR = 255;

    /// @notice Selector for CMTAT's validateTransfer function
    bytes4 internal constant SELECTOR_VALIDATE_TRANSFER =
        bytes4(keccak256("validateTransfer(address,address,uint256)"));

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLE STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IACERuleEngineAdapter
    IPolicyEngine public immutable override policyEngine;

    /// @inheritdoc IACERuleEngineAdapter
    address public immutable override targetToken;

    /// @inheritdoc IACERuleEngineAdapter
    IExtractor public immutable override extractor;

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTABLE STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Mapping of restriction codes to human-readable messages
    mapping(uint8 restrictionCode => string message) private _restrictionMessages;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the adapter with required dependencies.
     * @dev Sets up immutable references and default restriction messages.
     *
     * @param _policyEngine The ACE PolicyEngine contract address
     * @param _targetToken The CMTAT token contract address that will use this adapter
     * @param _extractor The extractor contract for parsing transfer parameters
     * @param _owner The initial owner of the adapter (for admin functions)
     */
    constructor(
        address _policyEngine,
        address _targetToken,
        address _extractor,
        address _owner
    ) Ownable(_owner) {
        if (_policyEngine == address(0)) revert ZeroAddressNotAllowed("policyEngine");
        if (_targetToken == address(0)) revert ZeroAddressNotAllowed("targetToken");
        if (_extractor == address(0)) revert ZeroAddressNotAllowed("extractor");
        if (_owner == address(0)) revert ZeroAddressNotAllowed("owner");

        policyEngine = IPolicyEngine(_policyEngine);
        targetToken = _targetToken;
        extractor = IExtractor(_extractor);

        // Initialize default restriction messages
        _restrictionMessages[RESTRICTION_CODE_OK] = "No restriction";
        _restrictionMessages[RESTRICTION_CODE_POLICY_REJECTED] = "Transfer rejected by compliance policy";
        _restrictionMessages[RESTRICTION_CODE_UNKNOWN_ERROR] = "Unknown compliance error occurred";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CMTAT IRULEENGINE INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc IACERuleEngineAdapter
     * @dev Validates a transfer by calling PolicyEngine.check().
     *
     * ## Implementation Notes
     * - Uses SELECTOR_VALIDATE_TRANSFER for policy lookup
     * - Encodes parameters as (from, to, amount) for the extractor
     * - Empty context is passed (CMTAT limitation)
     * - Returns true only if check() succeeds without reverting
     */
    function validateTransfer(
        address from,
        address to,
        uint256 amount
    ) external view override returns (bool isValid) {
        uint8 code = _checkTransfer(from, to, amount);
        return code == RESTRICTION_CODE_OK;
    }

    /**
     * @inheritdoc IACERuleEngineAdapter
     * @dev Detects restrictions by calling PolicyEngine.check() and mapping results.
     *
     * ## Restriction Code Mapping
     * - 0: Transfer allowed (no restriction)
     * - 1: Policy explicitly rejected the transfer
     * - 255: Unknown error during policy check
     */
    function detectTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) external view override returns (uint8 restrictionCode) {
        return _checkTransfer(from, to, amount);
    }

    /**
     * @inheritdoc IACERuleEngineAdapter
     * @dev Returns the stored message for a restriction code.
     *      Returns "Unknown restriction code" if no message is configured.
     */
    function messageForTransferRestriction(
        uint8 restrictionCode
    ) external view override returns (string memory message) {
        message = _restrictionMessages[restrictionCode];
        if (bytes(message).length == 0) {
            return "Unknown restriction code";
        }
        return message;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc IACERuleEngineAdapter
     * @dev Only the owner can update restriction messages.
     */
    function setRestrictionMessage(
        uint8 restrictionCode,
        string calldata message
    ) external override onlyOwner {
        _restrictionMessages[restrictionCode] = message;
        emit RestrictionMessageUpdated(restrictionCode, message);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function to check transfer against policies.
     * @dev Constructs the payload and calls PolicyEngine.check().
     *
     * ## Payload Construction
     * - selector: SELECTOR_VALIDATE_TRANSFER (for consistent policy lookup)
     * - sender: The 'from' address (transfer initiator)
     * - data: abi.encode(from, to, amount)
     * - context: empty bytes (CMTAT doesn't provide context)
     *
     * ## Error Handling
     * - If check() succeeds: returns RESTRICTION_CODE_OK
     * - If check() reverts with PolicyRejected: returns RESTRICTION_CODE_POLICY_REJECTED
     * - If check() reverts with other error: returns _mapErrorToRestrictionCode result
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return restrictionCode The restriction code (0 = allowed)
     */
    function _checkTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view returns (uint8 restrictionCode) {
        // Construct the ACE payload
        // Using SELECTOR_VALIDATE_TRANSFER for consistent policy lookup
        // The extractor will parse (from, to, amount) from the data
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: SELECTOR_VALIDATE_TRANSFER,
            sender: from,
            data: abi.encode(from, to, amount),
            context: "" // Empty context - CMTAT doesn't provide context bytes
        });

        // Call PolicyEngine.check() with try/catch
        // check() is a VIEW function - it won't modify state
        try policyEngine.check(payload) {
            // Policy check passed - no restriction
            restrictionCode = RESTRICTION_CODE_OK;
        } catch (bytes memory reason) {
            // Policy check failed - map error to restriction code
            restrictionCode = _mapErrorToRestrictionCode(reason);
        }

        // Emit validation event (note: this won't actually emit in a view function,
        // but included for interface compliance and potential future use)
        // emit TransferValidated(from, to, amount, restrictionCode);

        return restrictionCode;
    }

    /**
     * @notice Maps ACE policy errors to CMTAT restriction codes.
     * @dev Attempts to decode specific ACE error types:
     *      - PolicyRejected(string) → RESTRICTION_CODE_POLICY_REJECTED
     *      - PolicyRunRejected(bytes4, address, string) → RESTRICTION_CODE_POLICY_REJECTED
     *      - Other errors → RESTRICTION_CODE_UNKNOWN_ERROR
     *
     * ## Error Selectors
     * - PolicyRejected: keccak256("PolicyRejected(string)")[:4] = 0xa5bd5e80
     * - PolicyRunRejected: keccak256("PolicyRunRejected(bytes4,address,string)")[:4] = 0x...
     *
     * @param reason The revert reason bytes from the policy engine
     * @return restrictionCode The mapped restriction code
     */
    function _mapErrorToRestrictionCode(
        bytes memory reason
    ) internal pure returns (uint8 restrictionCode) {
        // If empty reason, return unknown error
        if (reason.length < 4) {
            return RESTRICTION_CODE_UNKNOWN_ERROR;
        }

        // Extract the error selector (first 4 bytes)
        bytes4 errorSelector;
        assembly {
            errorSelector := mload(add(reason, 32))
        }

        // PolicyRejected(string) selector
        // keccak256("PolicyRejected(string)") = 0xa5bd5e8031d5e38ddec6d4c0418dd5a6f4d57e0d4c3e89f77e5e8c1afe8c9d7b
        // First 4 bytes: 0xa5bd5e80
        bytes4 policyRejectedSelector = bytes4(keccak256("PolicyRejected(string)"));

        // PolicyRunRejected(bytes4,address,string) selector
        bytes4 policyRunRejectedSelector = bytes4(keccak256("PolicyRunRejected(bytes4,address,string)"));

        if (errorSelector == policyRejectedSelector || errorSelector == policyRunRejectedSelector) {
            return RESTRICTION_CODE_POLICY_REJECTED;
        }

        // For any other error, return unknown error code
        return RESTRICTION_CODE_UNKNOWN_ERROR;
    }
}
