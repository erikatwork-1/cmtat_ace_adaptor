// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";
import {IACERule} from "../interfaces/IACERule.sol";

/**
 * @title ACERule
 * @author CMTAT ACE Adapter
 * @notice ACE PolicyEngine integration as a rule within CMTAT RuleEngine (v2.3.0 / v1.0.2.1).
 * @dev This contract implements the IRule interface from CMTAT RuleEngine, allowing ACE validation
 *      to be composed with other compliance rules in a non-destructive manner.
 *
 * ## Architecture
 * ```
 * CMTAT Token
 *     │
 *     ▼
 * RuleEngine
 *     │
 *     ├──► ACERule (this contract) ──► ACE PolicyEngine
 *     │
 *     ├──► WhitelistRule (existing)
 *     │
 *     └──► Other Rules (existing)
 * ```
 *
 * ## Token-Agnostic Design
 * Unlike ACERuleEngineAdapter, ACERule does NOT store a targetToken address. This means:
 * - ✅ One ACERule deployment can serve multiple CMTAT tokens
 * - ✅ One RuleEngine can manage multiple tokens
 * - ✅ Lower deployment costs
 * - ✅ Simplified policy management
 *
 * ## Policy Registration
 * ACE policies must be registered against the **RuleEngine address**, not CMTAT token addresses:
 * ```solidity
 * policyEngine.addPolicy(
 *     ruleEngineAddress,  // ← RuleEngine address
 *     transferSelector,
 *     allowPolicyAddress,
 *     parameters
 * );
 * ```
 *
 * ## Usage Example
 * ```solidity
 * // 1. Deploy ACERule (token-agnostic)
 * ACERule aceRule = new ACERule(policyEngineAddress, extractorAddress);
 *
 * // 2. Add to existing RuleEngine (non-destructive!)
 * ruleEngine.addRule(address(aceRule));
 *
 * // 3. Configure ACE policies for the RuleEngine
 * policyEngine.addPolicy(address(ruleEngine), selector, policy, params);
 * ```
 *
 * ## Key Features
 * - Non-destructive integration with existing rules
 * - Token-agnostic deployment
 * - Composable with multiple rules
 * - AND logic: ALL rules must pass for transfer to succeed
 * - View-only validation (CMTAT v2.3.0 limitation)
 *
 * ## Known Limitations (v2.3.0)
 * - VIEW function constraint: Can only use PolicyEngine.check(), not run()
 * - postRun() hooks will NOT execute
 * - Stateful policies (VolumePolicy, VolumeRatePolicy) won't update state
 * - No context parameter support
 *
 * ## Compatible Policies
 * - AllowPolicy, RejectPolicy, MaxPolicy, IntervalPolicy
 * - PausePolicy, OnlyOwnerPolicy, OnlyAuthorizedSenderPolicy
 * - BypassPolicy, SecureMintPolicy, RoleBasedAccessControlPolicy
 * - CredentialRegistryIdentityValidatorPolicy
 *
 * @custom:security-contact security@example.com
 */
contract ACERule is IACERule {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Selector for CMTAT's validateTransfer function
    bytes4 internal constant SELECTOR_VALIDATE_TRANSFER =
        bytes4(keccak256("validateTransfer(address,address,uint256)"));

    /// @notice Default restriction message for policy rejections
    string internal constant DEFAULT_REJECTION_MESSAGE = "Transfer rejected by ACE policy";

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLE STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IACERule
    IPolicyEngine public immutable override policyEngine;

    /// @inheritdoc IACERule
    IExtractor public immutable override extractor;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes ACERule with required dependencies.
     * @dev Token-agnostic design: NO targetToken parameter.
     *      This ACERule can work with any CMTAT token that uses a compatible RuleEngine.
     *
     * @param _policyEngine The ACE PolicyEngine contract address
     * @param _extractor The extractor contract for parsing transfer parameters
     */
    constructor(
        address _policyEngine,
        address _extractor
    ) {
        if (_policyEngine == address(0)) revert ZeroAddressNotAllowed("policyEngine");
        if (_extractor == address(0)) revert ZeroAddressNotAllowed("extractor");

        policyEngine = IPolicyEngine(_policyEngine);
        extractor = IExtractor(_extractor);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CMTAT IRULE INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc IACERule
     * @dev Validates a transfer by calling PolicyEngine.check().
     *
     * ## Implementation Notes
     * - Uses SELECTOR_VALIDATE_TRANSFER for policy lookup
     * - Encodes parameters as (from, to, amount) for the extractor
     * - Empty context is passed (CMTAT limitation)
     * - Returns true only if check() succeeds without reverting
     * - Policies must be registered against the RuleEngine address (msg.sender)
     *
     * ## Policy Check Flow
     * 1. Construct payload with transfer parameters
     * 2. Call policyEngine.check(payload)
     * 3. If check() succeeds → return true
     * 4. If check() reverts → return false
     */
    function validateTransfer(
        address from,
        address to,
        uint256 amount
    ) external view override returns (bool allowed) {
        // Construct the ACE payload
        // Note: We don't need a targetToken because policies are registered
        // against the RuleEngine address, which is msg.sender in this context
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: SELECTOR_VALIDATE_TRANSFER,
            sender: from,
            data: abi.encode(from, to, amount),
            context: "" // Empty context - CMTAT doesn't provide context bytes
        });

        // Call PolicyEngine.check() with try/catch
        // check() is a VIEW function - it won't modify state
        // Note: We can't emit events in a view function
        try policyEngine.check(payload) {
            // Policy check passed - transfer is allowed by ACE
            return true;
        } catch {
            // Policy check failed - transfer is rejected by ACE
            return false;
        }
    }

    /**
     * @inheritdoc IACERule
     * @dev Detects restrictions by calling PolicyEngine.check() and returning a message.
     *
     * ## Return Values
     * - Empty string: Transfer is allowed (no restriction)
     * - Non-empty string: Transfer is rejected (contains reason)
     *
     * ## Error Handling
     * - If check() succeeds: returns empty string
     * - If check() reverts: returns rejection message
     * - Attempts to extract detailed error from revert reason
     */
    function detectTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) external view override returns (string memory message) {
        // Construct the ACE payload
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: SELECTOR_VALIDATE_TRANSFER,
            sender: from,
            data: abi.encode(from, to, amount),
            context: ""
        });

        // Call PolicyEngine.check() with try/catch
        try policyEngine.check(payload) {
            // No restriction - return empty string
            return "";
        } catch (bytes memory reason) {
            // Transfer restricted - attempt to extract detailed message
            return _extractErrorMessage(reason);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extracts a human-readable error message from revert reason.
     * @dev Attempts to decode ACE-specific errors (PolicyRejected, PolicyRunRejected).
     *      Falls back to default message if decoding fails.
     *
     * ## Supported Error Types
     * - PolicyRejected(string): Extracts the rejection reason
     * - PolicyRunRejected(bytes4,address,string): Extracts the reason string
     * - Other errors: Returns default message
     *
     * @param reason The revert reason bytes from PolicyEngine
     * @return message The extracted or default error message
     */
    function _extractErrorMessage(
        bytes memory reason
    ) internal view returns (string memory message) {
        // If empty reason, return default
        if (reason.length < 4) {
            return DEFAULT_REJECTION_MESSAGE;
        }

        // Extract the error selector (first 4 bytes)
        bytes4 errorSelector;
        assembly {
            errorSelector := mload(add(reason, 32))
        }

        // PolicyRejected(string) selector
        bytes4 policyRejectedSelector = bytes4(keccak256("PolicyRejected(string)"));

        // PolicyRunRejected(bytes4,address,string) selector
        bytes4 policyRunRejectedSelector = bytes4(keccak256("PolicyRunRejected(bytes4,address,string)"));

        if (errorSelector == policyRejectedSelector) {
            // Try to decode PolicyRejected(string)
            // Skip the first 4 bytes (selector) and decode the rest
            if (reason.length > 4) {
                // Remove the selector (first 4 bytes)
                bytes memory data = new bytes(reason.length - 4);
                for (uint256 i = 0; i < data.length; i++) {
                    data[i] = reason[i + 4];
                }
                
                // Try to decode as string
                (bool success, string memory decoded) = _tryDecodeString(data);
                if (success && bytes(decoded).length > 0) {
                    return decoded;
                }
            }
        } else if (errorSelector == policyRunRejectedSelector) {
            // PolicyRunRejected has format: (bytes4, address, string)
            // We want to extract the string at the end
            if (reason.length > 4) {
                bytes memory data = new bytes(reason.length - 4);
                for (uint256 i = 0; i < data.length; i++) {
                    data[i] = reason[i + 4];
                }
                
                (bool success, string memory decoded) = _tryDecodePolicyRunRejected(data);
                if (success && bytes(decoded).length > 0) {
                    return decoded;
                }
            }
        }

        // For any other error, return default message
        return DEFAULT_REJECTION_MESSAGE;
    }

    /**
     * @notice Helper to decode a string from bytes (with try/catch protection).
     * @param data The ABI-encoded string data
     * @return success Whether decoding succeeded
     * @return decoded The decoded string (empty if failed)
     */
    function _tryDecodeString(bytes memory data) internal view returns (bool success, string memory decoded) {
        if (data.length < 32) {
            return (false, "");
        }
        
        try this._decodeStringExternal(data) returns (string memory result) {
            return (true, result);
        } catch {
            return (false, "");
        }
    }

    /**
     * @notice External helper to decode a string from bytes.
     * @dev Made external so it can be called with try/catch from internal function.
     * @param data The ABI-encoded string data
     * @return The decoded string
     */
    function _decodeStringExternal(bytes calldata data) external pure returns (string memory) {
        return abi.decode(data, (string));
    }

    /**
     * @notice Helper to decode PolicyRunRejected error (with try/catch protection).
     * @param data The ABI-encoded error data (without selector)
     * @return success Whether decoding succeeded
     * @return decoded The decoded rejection message (empty if failed)
     */
    function _tryDecodePolicyRunRejected(bytes memory data) internal view returns (bool success, string memory decoded) {
        if (data.length < 32) {
            return (false, "");
        }
        
        try this._decodePolicyRunRejectedExternal(data) returns (string memory result) {
            return (true, result);
        } catch {
            return (false, "");
        }
    }

    /**
     * @notice External helper to decode PolicyRunRejected error.
     * @dev Extracts the string message from PolicyRunRejected(bytes4,address,string).
     * @param data The ABI-encoded error data (without selector)
     * @return The decoded rejection message
     */
    function _decodePolicyRunRejectedExternal(bytes calldata data) external pure returns (string memory) {
        (, , string memory message) = abi.decode(data, (bytes4, address, string));
        return message;
    }
}
