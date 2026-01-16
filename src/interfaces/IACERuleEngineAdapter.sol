// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";

/**
 * @title IACERuleEngineAdapter
 * @author CMTAT ACE Adapter
 * @notice Interface for the ACE RuleEngine Adapter that bridges CMTAT tokens to Chainlink ACE PolicyEngine.
 * @dev This interface extends the CMTAT IRuleEngine interface with ACE-specific functionality.
 *
 * The adapter implements the CMTAT IRuleEngine interface, allowing existing CMTAT tokens to
 * use Chainlink ACE PolicyEngine for compliance checks without modifying the token contract.
 *
 * ## Architecture
 * ```
 * CMTAT Token → ACERuleEngineAdapter.validateTransfer() → PolicyEngine.check() → Returns restriction code
 * ```
 *
 * ## Key Features
 * - Drop-in replacement for existing CMTAT RuleEngine
 * - Translates CMTAT's validateTransfer calls to ACE PolicyEngine checks
 * - Maps ACE policy results to CMTAT restriction codes
 * - Supports custom restriction messages
 *
 * ## Known Limitations
 * - Only supports view-based policy checks (check(), not run())
 * - postRun() hooks are NOT called
 * - Stateful policies (VolumePolicy, VolumeRatePolicy) won't update state
 * - Context parameter is not supported (CMTAT doesn't provide context)
 */
interface IACERuleEngineAdapter {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a transfer is validated through the adapter.
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @param restrictionCode The resulting restriction code (0 = no restriction)
     */
    event TransferValidated(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint8 restrictionCode
    );

    /**
     * @notice Emitted when a restriction message is updated.
     * @param restrictionCode The restriction code being updated
     * @param message The new message for the restriction code
     */
    event RestrictionMessageUpdated(uint8 indexed restrictionCode, string message);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Error thrown when a zero address is provided where not allowed.
     * @param paramName The name of the parameter that was zero
     */
    error ZeroAddressNotAllowed(string paramName);

    /**
     * @notice Error thrown when the caller is not authorized to perform an action.
     */
    error Unauthorized();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Restriction code indicating no restriction (transfer allowed).
     * @return The restriction code for allowed transfers (0)
     */
    function RESTRICTION_CODE_OK() external pure returns (uint8);

    /**
     * @notice Restriction code indicating the transfer was rejected by a policy.
     * @return The restriction code for policy rejections (1)
     */
    function RESTRICTION_CODE_POLICY_REJECTED() external pure returns (uint8);

    /**
     * @notice Restriction code indicating an unknown error occurred.
     * @return The restriction code for unknown errors (255)
     */
    function RESTRICTION_CODE_UNKNOWN_ERROR() external pure returns (uint8);

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLE STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the ACE PolicyEngine contract address.
     * @return The PolicyEngine contract address
     */
    function policyEngine() external view returns (IPolicyEngine);

    /**
     * @notice Returns the target CMTAT token contract address.
     * @return The token contract address
     */
    function targetToken() external view returns (address);

    /**
     * @notice Returns the extractor contract used for parameter extraction.
     * @return The extractor contract address
     */
    function extractor() external view returns (IExtractor);

    // ═══════════════════════════════════════════════════════════════════════════
    // CMTAT IRULEENGINE INTERFACE (IEIP1404Wrapper)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validates a transfer using the ACE PolicyEngine.
     * @dev Implements CMTAT's IRuleEngine.validateTransfer interface.
     *      This is a VIEW function - it can only use PolicyEngine.check(), not run().
     *
     * ## Implementation Details
     * 1. Constructs a synthetic calldata payload from the transfer parameters
     * 2. Calls policyEngine.check() with the payload
     * 3. Returns true if allowed, false if rejected
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return isValid True if the transfer is allowed, false otherwise
     */
    function validateTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool isValid);

    /**
     * @notice Detects transfer restrictions using the ACE PolicyEngine.
     * @dev Implements CMTAT's IRuleEngine.detectTransferRestriction interface (EIP-1404).
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return restrictionCode 0 = no restriction, non-zero = restricted
     */
    function detectTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint8 restrictionCode);

    /**
     * @notice Returns a human-readable message for a restriction code.
     * @dev Implements CMTAT's IRuleEngine.messageForTransferRestriction interface (EIP-1404).
     *
     * @param restrictionCode The restriction code to look up
     * @return message The human-readable error message
     */
    function messageForTransferRestriction(
        uint8 restrictionCode
    ) external view returns (string memory message);

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets a custom message for a restriction code.
     * @dev Only callable by authorized administrators.
     *
     * @param restrictionCode The restriction code to configure
     * @param message The human-readable message for the code
     */
    function setRestrictionMessage(uint8 restrictionCode, string calldata message) external;
}
