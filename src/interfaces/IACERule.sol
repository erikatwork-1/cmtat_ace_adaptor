// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";

/**
 * @title IACERule
 * @author CMTAT ACE Adapter
 * @notice Interface for ACERule that integrates ACE PolicyEngine as a rule within CMTAT RuleEngine.
 * @dev This interface is designed for the "Rule Approach" where ACE validation is one of multiple
 *      rules within a CMTAT RuleEngine, enabling non-destructive integration with existing compliance rules.
 *
 * ## Architecture
 * ```
 * CMTAT Token → RuleEngine → ACERule (this) → ACE PolicyEngine
 *                          → WhitelistRule
 *                          → Other Rules
 * ```
 *
 * ## Key Design Decisions
 * 
 * ### Token-Agnostic Design
 * Unlike ACERuleEngineAdapter, ACERule does NOT have a targetToken parameter. This allows:
 * - One ACERule deployment to serve multiple CMTAT tokens
 * - RuleEngine reusability across different tokens
 * - Lower deployment costs
 * - Simplified policy management
 *
 * ### RuleEngine-Centric Policy Registration
 * ACE policies should be registered against the **RuleEngine address**, not individual CMTAT tokens:
 * ```solidity
 * policyEngine.addPolicy(
 *     ruleEngineAddress,  // ← RuleEngine, NOT CMTAT token
 *     selector,
 *     policyAddress,
 *     parameters
 * );
 * ```
 *
 * ## Version Compatibility
 * - ACERule: For CMTAT v2.3.0 / RuleEngine v1.0.2.1 (view-only)
 * - ACERule_v3: For CMTAT v3.0+ / RuleEngine v3.0+ (stateful with operateOnTransfer)
 *
 * ## Known Limitations (v2.3.0)
 * - Only supports view-based policy checks (check(), not run())
 * - postRun() hooks are NOT called
 * - Stateful policies (VolumePolicy, VolumeRatePolicy) won't update state
 * - Context parameter is not supported (CMTAT doesn't provide context)
 *
 * @custom:security-contact security@example.com
 */
interface IACERule {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a transfer is validated through ACERule.
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @param allowed Whether the transfer was allowed by ACE policies
     */
    event TransferValidated(
        address indexed from,
        address indexed to,
        uint256 amount,
        bool allowed
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Error thrown when a zero address is provided where not allowed.
     * @param paramName The name of the parameter that was zero
     */
    error ZeroAddressNotAllowed(string paramName);

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLE STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the ACE PolicyEngine contract address.
     * @return The PolicyEngine contract address
     */
    function policyEngine() external view returns (IPolicyEngine);

    /**
     * @notice Returns the extractor contract used for parameter extraction.
     * @return The extractor contract address
     */
    function extractor() external view returns (IExtractor);

    // ═══════════════════════════════════════════════════════════════════════════
    // CMTAT IRULE INTERFACE (RuleEngine v1.0.2.1)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validates a transfer using the ACE PolicyEngine.
     * @dev Implements CMTAT RuleEngine's IRule.validateTransfer interface.
     *      This is a VIEW function - it can only use PolicyEngine.check(), not run().
     *
     * ## Implementation Details
     * 1. Constructs a payload from the transfer parameters
     * 2. Calls policyEngine.check() with the payload
     * 3. Returns true if allowed, false if rejected
     *
     * ## Important Notes
     * - Returns BOOL (not uint8 like IRuleEngine adapter)
     * - Policies must be registered against the RuleEngine address
     * - Works alongside other rules in the RuleEngine
     * - ALL rules must return true for transfer to proceed (AND logic)
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return allowed True if the transfer is allowed, false otherwise
     */
    function validateTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool allowed);

    /**
     * @notice Detects transfer restrictions using the ACE PolicyEngine.
     * @dev Implements CMTAT RuleEngine's IRule.detectTransferRestriction interface.
     *      Returns a human-readable string explaining why a transfer was rejected.
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return message Human-readable restriction message (empty if allowed)
     */
    function detectTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) external view returns (string memory message);
}
