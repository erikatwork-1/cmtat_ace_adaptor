// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERuleEngineAdapter} from "../../src/adapter/ACERuleEngineAdapter.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title ViewLimitationTest
 * @author CMTAT ACE Adapter
 * @notice Tests demonstrating the VIEW function limitation of the adapter.
 *
 * ## Critical Limitation: VIEW Function Constraint
 *
 * CMTAT's validateTransfer() is a VIEW function, which means:
 * - The adapter can only use PolicyEngine.check() (read-only)
 * - The adapter CANNOT use PolicyEngine.run() (state-changing)
 * - postRun() hooks are NEVER called
 * - Stateful policies will NOT update their state
 *
 * ## Impact on Stateful Policies
 *
 * Policies that rely on state updates during validation will NOT work correctly:
 * - VolumePolicy: Tracks cumulative transfer volume, but won't accumulate
 * - VolumeRatePolicy: Tracks transfer rates over time, but won't track
 * - Any policy using postRun() for bookkeeping
 *
 * ## This Test Suite Demonstrates
 *
 * 1. The difference between check() and run() in ACE
 * 2. Why state updates don't happen through the adapter
 * 3. How this affects VolumePolicy-style tracking
 *
 * These tests are INTENTIONALLY designed to show the limitation, not to pass
 * as working features. They document what DOES NOT work.
 */
contract ViewLimitationTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERuleEngineAdapter public adapter;
    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;
    MockCMTATToken public token;

    address public admin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);

    uint256 public constant USER_BALANCE = 10_000 ether;

    function setUp() public {
        token = new MockCMTATToken("View Test Token", "VTT", admin);
        policyEngine = new MockPolicyEngine();
        extractor = new CMTATTransferExtractor();
        adapter = new ACERuleEngineAdapter(
            address(policyEngine),
            address(token),
            address(extractor),
            admin
        );

        vm.prank(admin);
        token.setRuleEngine(address(adapter));

        vm.startPrank(admin);
        token.mint(alice, USER_BALANCE);
        token.mint(bob, USER_BALANCE);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEMONSTRATION: check() vs run() BEHAVIOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Demonstrates that check() is view-only and doesn't modify state.
     * @dev The adapter uses check(), so any state that run() would modify won't be changed.
     *
     * ## Why This Matters
     * - ACE's run() function calls postRun() hooks after validation
     * - check() does NOT call postRun() hooks
     * - The adapter can only use check() because validateTransfer() is VIEW
     * - Therefore, postRun() hooks are NEVER executed through the adapter
     */
    function test_LIMITATION_CheckDoesNotModifyState() public {
        // Get the initial state value
        uint256 initialState = policyEngine.stateModifiedByRun();
        assertEq(initialState, 0, "Initial state should be 0");

        // Execute multiple transfers through the adapter
        // These all use check() internally, not run()
        vm.prank(alice);
        token.transfer(bob, 100 ether);

        vm.prank(alice);
        token.transfer(bob, 200 ether);

        vm.prank(alice);
        token.transfer(bob, 300 ether);

        // State should STILL be 0 because check() doesn't modify state
        uint256 finalState = policyEngine.stateModifiedByRun();
        assertEq(finalState, 0, "State should still be 0 - check() doesn't modify state");

        // This demonstrates the limitation: even after 3 transfers,
        // no state tracking occurred
        console2.log("=== VIEW FUNCTION LIMITATION DEMONSTRATED ===");
        console2.log("Transfers executed: 3");
        console2.log("State modifications (stateModifiedByRun): 0");
        console2.log("Expected if run() was used: 3");
    }

    /**
     * @notice Shows that run() WOULD modify state (for comparison).
     * @dev This demonstrates what would happen if we could use run().
     */
    function test_COMPARISON_RunDoesModifyState() public {
        // Get the initial state value
        uint256 initialState = policyEngine.stateModifiedByRun();
        assertEq(initialState, 0, "Initial state should be 0");

        // Directly call run() on the policy engine (simulating what run() does)
        // Note: The adapter CANNOT do this because validateTransfer is VIEW
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: bytes4(keccak256("validateTransfer(address,address,uint256)")),
            sender: alice,
            data: abi.encode(alice, bob, 100 ether),
            context: ""
        });

        // First run
        policyEngine.run(payload);
        assertEq(policyEngine.stateModifiedByRun(), 1, "State should be 1 after first run");

        // Second run
        policyEngine.run(payload);
        assertEq(policyEngine.stateModifiedByRun(), 2, "State should be 2 after second run");

        // Third run
        policyEngine.run(payload);
        assertEq(policyEngine.stateModifiedByRun(), 3, "State should be 3 after third run");

        console2.log("=== RUN() BEHAVIOR FOR COMPARISON ===");
        console2.log("Direct run() calls: 3");
        console2.log("State modifications: 3");
        console2.log("This is what WOULD happen if adapter could use run()");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEMONSTRATION: VOLUME POLICY LIMITATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Simulates how VolumePolicy would FAIL to track cumulative volume.
     * @dev VolumePolicy typically tracks: "user can only transfer X tokens total per day"
     *
     * ## How VolumePolicy Should Work (with run())
     * 1. Policy checks if (currentVolume + transferAmount) <= dailyLimit
     * 2. If allowed, postRun() updates: currentVolume += transferAmount
     * 3. Next transfer sees the updated currentVolume
     *
     * ## How It Actually Works (with check())
     * 1. Policy checks if (currentVolume + transferAmount) <= dailyLimit
     * 2. check() doesn't call postRun(), so currentVolume stays at 0
     * 3. Next transfer STILL sees currentVolume = 0
     * 4. User can bypass the daily limit!
     */
    function test_LIMITATION_VolumePolicyCannotTrack() public {
        // Simulate a daily limit of 500 ether
        // In a real VolumePolicy, this would accumulate with each transfer

        // First transfer: 200 ether
        // Expected volume after: 200 ether (but will be 0 due to limitation)
        vm.prank(alice);
        token.transfer(bob, 200 ether);

        // Second transfer: 200 ether
        // Expected cumulative: 400 ether (but will be 0)
        vm.prank(alice);
        token.transfer(bob, 200 ether);

        // Third transfer: 200 ether
        // Expected cumulative: 600 ether (SHOULD FAIL if limit is 500)
        // But since no tracking happens, this succeeds!
        vm.prank(alice);
        token.transfer(bob, 200 ether);

        // Alice has transferred 600 ether total
        // With proper VolumePolicy, the third transfer should have failed
        assertEq(token.balanceOf(alice), USER_BALANCE - 600 ether);

        console2.log("=== VOLUME POLICY LIMITATION ===");
        console2.log("Daily limit (simulated): 500 ether");
        console2.log("Total transferred: 600 ether");
        console2.log("Should have been blocked? YES");
        console2.log("Was blocked? NO (limitation)");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEMONSTRATION: CALL COUNTER LIMITATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Shows that check() call counts cannot be tracked in VIEW context.
     * @dev The MockPolicyEngine has a checkCallCount, but it can't be incremented
     *      from a view function.
     */
    function test_LIMITATION_CannotTrackCallCount() public view {
        uint256 initialCount = policyEngine.checkCallCount();

        // Multiple validation calls
        adapter.validateTransfer(alice, bob, 100 ether);
        adapter.validateTransfer(alice, bob, 100 ether);
        adapter.validateTransfer(alice, bob, 100 ether);

        // Count should still be 0 (can't increment in view function)
        uint256 finalCount = policyEngine.checkCallCount();
        assertEq(finalCount, initialCount, "Check count cannot be incremented in view context");

        console2.log("=== CALL COUNT LIMITATION ===");
        console2.log("validateTransfer calls: 3");
        console2.log("Recorded check calls: 0");
        console2.log("Reason: View functions cannot modify state");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DOCUMENTATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Documents which policies work and which don't.
     */
    function test_DOCUMENTATION_PolicyCompatibility() public pure {
        console2.log("=== POLICY COMPATIBILITY MATRIX ===");
        console2.log("");
        console2.log("FULLY COMPATIBLE (stateless, read-only):");
        console2.log("  [OK] AllowPolicy - Whitelist checks");
        console2.log("  [OK] RejectPolicy - Always reject");
        console2.log("  [OK] MaxPolicy - Static amount limits");
        console2.log("  [OK] IntervalPolicy - Time-based restrictions");
        console2.log("  [OK] PausePolicy - Pause/unpause");
        console2.log("  [OK] OnlyOwnerPolicy - Owner-only access");
        console2.log("  [OK] OnlyAuthorizedSenderPolicy - Authorized senders");
        console2.log("  [OK] BypassPolicy - Bypass logic");
        console2.log("  [OK] RoleBasedAccessControlPolicy - Role checks");
        console2.log("  [OK] CredentialRegistryIdentityValidatorPolicy - Credential checks");
        console2.log("");
        console2.log("PARTIALLY COMPATIBLE (reads work, tracking doesn't):");
        console2.log("  [WARN] VolumePolicy - Volume won't accumulate");
        console2.log("  [WARN] VolumeRatePolicy - Rate won't track");
        console2.log("");
        console2.log("NOT COMPATIBLE:");
        console2.log("  [FAIL] Any policy requiring context bytes");
        console2.log("  [FAIL] Any policy requiring postRun() hooks");
        console2.log("  [FAIL] Any policy modifying state during validation");
    }

    /**
     * @notice Documents workarounds for the VIEW limitation.
     */
    function test_DOCUMENTATION_Workarounds() public pure {
        console2.log("=== POTENTIAL WORKAROUNDS ===");
        console2.log("");
        console2.log("1. Use Read-Only Alternatives");
        console2.log("   - Instead of VolumePolicy, use MaxPolicy with static limits");
        console2.log("   - Accept that per-transfer limits work, but cumulative don't");
        console2.log("");
        console2.log("2. External Volume Tracking");
        console2.log("   - Track volume off-chain via events");
        console2.log("   - Update policy parameters periodically");
        console2.log("   - Less real-time, but functional");
        console2.log("");
        console2.log("3. Custom Token Implementation");
        console2.log("   - Modify CMTAT to use non-view validation");
        console2.log("   - Requires token contract changes");
        console2.log("   - Not suitable for existing deployments");
        console2.log("");
        console2.log("4. Accept the Limitation");
        console2.log("   - Document clearly in compliance documentation");
        console2.log("   - Focus on policies that work correctly");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUMMARY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Summary test that always passes but logs the key takeaway.
     */
    function test_Summary() public pure {
        console2.log("");
        console2.log("====================================");
        console2.log("    VIEW FUNCTION LIMITATION");
        console2.log("====================================");
        console2.log("");
        console2.log("CMTAT's validateTransfer() is VIEW.");
        console2.log("This means the adapter uses check().");
        console2.log("check() does NOT call postRun().");
        console2.log("");
        console2.log("CONSEQUENCE:");
        console2.log("Stateful policies will NOT track correctly.");
        console2.log("VolumePolicy volume won't accumulate.");
        console2.log("VolumeRatePolicy rates won't track.");
        console2.log("");
        console2.log("RECOMMENDATION:");
        console2.log("Use read-only policies with static limits.");
        console2.log("Document this limitation clearly.");
        console2.log("====================================");
    }
}
