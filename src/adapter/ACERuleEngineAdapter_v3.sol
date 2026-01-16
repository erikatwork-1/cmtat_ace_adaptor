// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {ACERuleEngineAdapter} from "./ACERuleEngineAdapter.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title ACERuleEngineAdapter_v3
 * @author CMTAT ACE Adapter
 * @notice Enhanced RuleEngine adapter for CMTAT v3.0+ with stateful operation support.
 * @dev Extends ACERuleEngineAdapter with operateOnTransfer() for stateful policy validation.
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
 *     ├─ _transfer() calls validateTransfer() → VIEW check
 *     │      │
 *     │      ▼
 *     │  ACERuleEngineAdapter_v3.validateTransfer() → PolicyEngine.check()
 *     │
 *     └─ _transfer() calls operateOnTransfer() → STATEFUL run
 *            │
 *            ▼
 *        ACERuleEngineAdapter_v3.operateOnTransfer() → PolicyEngine.run()
 *            │
 *            ├─► Policies validate & update state
 *            └─► postRun() hooks execute
 * ```
 *
 * ## Comparison: v2.3.0 vs v3.0
 *
 * | Feature | v2.3.0 Adapter | v3.0 Adapter |
 * |---------|---------------|--------------|
 * | validateTransfer() | ✅ VIEW check() | ✅ VIEW check() |
 * | operateOnTransfer() | ❌ Not available | ✅ NON-VIEW run() |
 * | Stateful policies | ❌ Won't update | ✅ Fully functional |
 * | VolumePolicy | ⚠️ Reads only | ✅ Tracks volumes |
 * | VolumeRatePolicy | ⚠️ Reads only | ✅ Accumulates rates |
 * | postRun() hooks | ❌ Never execute | ✅ Execute on run() |
 *
 * ## Usage Example
 * ```solidity
 * // 1. Deploy adapter for specific token
 * ACERuleEngineAdapter_v3 adapter = new ACERuleEngineAdapter_v3(
 *     policyEngineAddress,
 *     cmtatTokenAddress,
 *     extractorAddress,
 *     ownerAddress
 * );
 *
 * // 2. Replace token's RuleEngine
 * cmtatToken.setRuleEngine(address(adapter));
 *
 * // 3. Configure stateful ACE policies
 * policyEngine.addPolicy(cmtatTokenAddress, selector, volumePolicy, params);
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
 * - ACE PolicyEngine (any version)
 *
 * ## Migration from v2.3.0
 * To upgrade from ACERuleEngineAdapter to ACERuleEngineAdapter_v3:
 * 1. Deploy ACERuleEngineAdapter_v3
 * 2. Configure stateful policies (e.g., VolumePolicy)
 * 3. Call cmtatToken.setRuleEngine(newAdapterAddress)
 * 4. Test operateOnTransfer() functionality
 *
 * @custom:security-contact security@example.com
 */
contract ACERuleEngineAdapter_v3 is ACERuleEngineAdapter {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the v3.0 adapter with required dependencies.
     * @dev Inherits constructor from ACERuleEngineAdapter.
     *      Same parameters as v2.3.0 adapter - seamless upgrade path.
     *
     * @param _policyEngine The ACE PolicyEngine contract address
     * @param _targetToken The CMTAT v3.0+ token contract address
     * @param _extractor The extractor contract for parsing transfer parameters
     * @param _owner The initial owner of the adapter (for admin functions)
     */
    constructor(
        address _policyEngine,
        address _targetToken,
        address _extractor,
        address _owner
    ) ACERuleEngineAdapter(_policyEngine, _targetToken, _extractor, _owner) {}

    // ═══════════════════════════════════════════════════════════════════════════
    // CMTAT v3.0+ IRULEENGINE INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Performs stateful validation and operations on a transfer.
     * @dev NEW in CMTAT v3.0+ IRuleEngine interface.
     *      This is a NON-VIEW function that uses PolicyEngine.run() for stateful validation.
     *
     * ## Key Differences from validateTransfer
     * - Uses PolicyEngine.run() instead of check()
     * - CAN modify state (non-view function)
     * - Enables VolumePolicy tracking
     * - Enables VolumeRatePolicy accumulation
     * - postRun() hooks will execute
     * - Returns uint8 restriction code (0 = allowed)
     *
     * ## Implementation Flow
     * 1. Construct payload with transfer parameters
     * 2. Call policyEngine.run(payload) ← Stateful!
     * 3. If run() succeeds:
     *    - Policies validated successfully
     *    - State may have been updated
     *    - postRun() hooks executed
     *    - Return RESTRICTION_CODE_OK (0)
     * 4. If run() reverts:
     *    - Policies rejected the transfer
     *    - No state changes persisted (reverted)
     *    - Map error to restriction code
     *
     * ## Policy Configuration
     * Policies must be registered against the targetToken address:
     * ```solidity
     * // Register VolumePolicy against token
     * policyEngine.addPolicy(
     *     targetToken,        // ← CMTAT token address
     *     transferSelector,
     *     volumePolicyAddress,
     *     abi.encode(maxVolume, timeWindow)
     * );
     * ```
     *
     * ## Security Considerations
     * - This function is NON-VIEW and can modify state
     * - Reentrancy protection should be handled by CMTAT token
     * - State updates are atomic (revert on failure)
     * - postRun() hooks have access to updated state
     *
     * ## Gas Considerations
     * - operateOnTransfer() typically costs more gas than validateTransfer()
     * - State writes increase gas consumption
     * - postRun() hooks add additional overhead
     * - Consider gas optimization for high-frequency transfers
     *
     * @param from The sender address
     * @param to The recipient address
     * @param amount The transfer amount
     * @return restrictionCode 0 = allowed, non-zero = restricted
     */
    function operateOnTransfer(
        address from,
        address to,
        uint256 amount
    ) external returns (uint8 restrictionCode) {
        // Construct the ACE payload
        // Using SELECTOR_VALIDATE_TRANSFER for consistent policy lookup
        // The extractor will parse (from, to, amount) from the data
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
            return RESTRICTION_CODE_OK;
        } catch (bytes memory reason) {
            // Policy run failed
            // - At least one policy rejected the transfer
            // - State changes were reverted (atomic)
            // - Map error to appropriate restriction code
            return _mapErrorToRestrictionCode(reason);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS (Informational)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the version of this adapter.
     * @return version The semantic version string
     */
    function version() external pure returns (string memory) {
        return "3.0.0";
    }

    /**
     * @notice Checks if this adapter supports stateful operations.
     * @return supported True (v3.0 always supports stateful ops)
     */
    function supportsStatefulOperations() external pure returns (bool) {
        return true;
    }
}
