// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {IACERule} from "./IACERule.sol";

/**
 * @title IACERule_v3
 * @author CMTAT ACE Adapter
 * @notice Extended interface for ACERule compatible with CMTAT v3.0+ and RuleEngine v3.0+.
 * @dev Extends IACERule with stateful operation support via operateOnTransfer().
 *
 * ## Key Enhancement: Stateful Operations
 * CMTAT v3.0+ introduces `operateOnTransfer()` which allows state-modifying operations
 * during transfer validation. This unlocks full ACE PolicyEngine capabilities:
 *
 * - ✅ PolicyEngine.run() instead of check()
 * - ✅ Stateful policy validation
 * - ✅ VolumePolicy with tracking
 * - ✅ VolumeRatePolicy with accumulation
 * - ✅ postRun() hooks execute
 *
 * ## Version Compatibility
 * - CMTAT v3.0+ required
 * - RuleEngine v3.0+ required
 * - ACE PolicyEngine (any version)
 *
 * ## Token-Agnostic Design
 * Like ACERule, ACERule_v3 is token-agnostic:
 * - No targetToken parameter in constructor
 * - Works with any CMTAT v3.0+ token
 * - Policies registered against RuleEngine address
 *
 * @custom:security-contact security@example.com
 */
interface IACERule_v3 is IACERule {
    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL INTERFACE FOR v3.0+
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Performs stateful validation and operations on a transfer.
     * @dev NEW in CMTAT v3.0+ / RuleEngine v3.0+.
     *      This is a NON-VIEW function that can modify state.
     *
     * ## Key Differences from validateTransfer
     * - Can use PolicyEngine.run() (stateful)
     * - postRun() hooks will execute
     * - State updates are allowed
     * - VolumePolicy and VolumeRatePolicy work correctly
     *
     * ## Implementation Notes
     * 1. Constructs a payload from the transfer parameters
     * 2. Calls policyEngine.run() (not check()!)
     * 3. Returns true if allowed, false if rejected
     * 4. State may be updated during execution
     *
     * ## Policy Registration
     * Policies must still be registered against the RuleEngine address:
     * ```solidity
     * policyEngine.addPolicy(
     *     ruleEngineAddress,  // ← RuleEngine, NOT token
     *     selector,
     *     policyAddress,
     *     parameters
     * );
     * ```
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
    ) external returns (bool allowed);
}
