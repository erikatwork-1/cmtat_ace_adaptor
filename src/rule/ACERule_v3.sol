// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";
import {ACERule} from "./ACERule.sol";
import {IACERule_v3} from "../interfaces/IACERule_v3.sol";

/**
 * @title ACERule_v3
 * @author CMTAT ACE Adapter
 * @notice ACE PolicyEngine integration as a rule within CMTAT RuleEngine v3.0+ with stateful support.
 * @dev Extends ACERule with operateOnTransfer() for stateful policy validation.
 *
 * ## Key Enhancement: Stateful Operations
 * 
 * CMTAT v3.0+ introduces `operateOnTransfer()` function that enables:
 * - ✅ State-modifying validation using PolicyEngine.run()
 * - ✅ VolumePolicy with cumulative tracking
 * - ✅ VolumeRatePolicy with rate limiting
 * - ✅ postRun() hooks execution
 * - ✅ Full ACE policy suite support
 *
 * ## Architecture
 * ```
 * CMTAT Token v3.0+
 *     │
 *     ▼
 * RuleEngine v3.0+
 *     │
 *     ├──► ACERule_v3 (this) ──► ACE PolicyEngine.run()
 *     │                              │
 *     │                              ├─► Policies validate & update state
 *     │                              └─► postRun() hooks execute
 *     │
 *     ├──► WhitelistRule (existing)
 *     │
 *     └──► Other Rules (existing)
 * ```
 *
 * ## Token-Agnostic Design
 * Like ACERule, this contract is token-agnostic:
 * - ✅ One deployment serves multiple CMTAT v3.0+ tokens
 * - ✅ Policies registered against RuleEngine address
 * - ✅ Lower deployment costs
 * - ✅ Simplified policy management
 *
 * ## Usage Example
 * ```solidity
 * // 1. Deploy ACERule_v3 (token-agnostic)
 * ACERule_v3 aceRule = new ACERule_v3(policyEngineAddress, extractorAddress);
 *
 * // 2. Add to RuleEngine v3.0+ (non-destructive!)
 * ruleEngine.addRule(address(aceRule));
 *
 * // 3. Configure stateful ACE policies for the RuleEngine
 * policyEngine.addPolicy(address(ruleEngine), selector, volumePolicy, params);
 * ```
 *
 * ## Compatible Policies
 * All ACE policies are now fully supported:
 * - ✅ AllowPolicy, RejectPolicy, MaxPolicy, IntervalPolicy
 * - ✅ PausePolicy, OnlyOwnerPolicy, OnlyAuthorizedSenderPolicy
 * - ✅ BypassPolicy, SecureMintPolicy, RoleBasedAccessControlPolicy
 * - ✅ CredentialRegistryIdentityValidatorPolicy
 * - ✅ **VolumePolicy** (now with state tracking!)
 * - ✅ **VolumeRatePolicy** (now with rate accumulation!)
 *
 * ## Version Requirements
 * - CMTAT v3.0+ required
 * - RuleEngine v3.0+ required
 * - ACE PolicyEngine (any version)
 *
 * @custom:security-contact security@example.com
 */
contract ACERule_v3 is ACERule, IACERule_v3 {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes ACERule_v3 with required dependencies.
     * @dev Token-agnostic design: NO targetToken parameter.
     *      Inherits constructor from ACERule.
     *
     * @param _policyEngine The ACE PolicyEngine contract address
     * @param _extractor The extractor contract for parsing transfer parameters
     */
    constructor(
        address _policyEngine,
        address _extractor
    ) ACERule(_policyEngine, _extractor) {}

    // ═══════════════════════════════════════════════════════════════════════════
    // CMTAT v3.0+ IRULE INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc IACERule_v3
     * @dev Performs stateful validation by calling PolicyEngine.run().
     *
     * ## Key Differences from validateTransfer (view)
     * - Uses PolicyEngine.run() instead of check()
     * - CAN modify state (non-view function)
     * - Enables VolumePolicy tracking
     * - Enables VolumeRatePolicy accumulation
     * - postRun() hooks will execute
     *
     * ## Implementation Flow
     * 1. Construct payload with transfer parameters
     * 2. Call policyEngine.run(payload) ← Stateful!
     * 3. If run() succeeds:
     *    - Policies validated successfully
     *    - State may have been updated
     *    - postRun() hooks executed
     *    - Return true
     * 4. If run() reverts:
     *    - Policies rejected the transfer
     *    - No state changes persisted (reverted)
     *    - Return false
     *
     * ## Policy Registration
     * Policies must be registered against the RuleEngine address:
     * ```solidity
     * // Register VolumePolicy against RuleEngine
     * policyEngine.addPolicy(
     *     ruleEngineAddress,  // ← RuleEngine, NOT token
     *     transferSelector,
     *     volumePolicyAddress,
     *     abi.encode(maxVolume, timeWindow)
     * );
     * ```
     *
     * ## Security Considerations
     * - This function is NON-VIEW and can modify state
     * - Reentrancy protection should be handled by RuleEngine
     * - State updates are atomic (revert on failure)
     * - postRun() hooks have access to updated state
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return allowed True if the transfer is allowed, false otherwise
     */
    function operateOnTransfer(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool allowed) {
        // Construct the ACE payload
        // Policies are registered against the RuleEngine address (msg.sender)
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: SELECTOR_VALIDATE_TRANSFER,
            sender: from,
            data: abi.encode(from, to, amount),
            context: "" // Empty context - CMTAT doesn't provide context bytes
        });

        // Call PolicyEngine.run() with try/catch
        // run() is a NON-VIEW function - it CAN modify state
        // This enables stateful policies like VolumePolicy and VolumeRatePolicy
        try policyEngine.run(payload) {
            // Policy run succeeded
            // - All policies validated successfully
            // - State may have been updated (e.g., volume tracking)
            // - postRun() hooks have executed
            emit TransferValidated(from, to, amount, true);
            return true;
        } catch {
            // Policy run failed
            // - At least one policy rejected the transfer
            // - State changes were reverted (atomic)
            // - postRun() hooks did not execute
            emit TransferValidated(from, to, amount, false);
            return false;
        }
    }
}
