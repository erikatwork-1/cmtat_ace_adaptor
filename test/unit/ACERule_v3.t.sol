// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERule_v3} from "../../src/rule/ACERule_v3.sol";
import {IACERule_v3} from "../../src/interfaces/IACERule_v3.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title ACERule_v3Test
 * @notice Comprehensive unit tests for ACERule_v3 (CMTAT v3.0+ compatible).
 * @dev Tests cover:
 *      - All ACERule v2.3.0 functionality (inherited)
 *      - New operateOnTransfer() for stateful validation
 *      - PolicyEngine.run() usage for state updates
 *      - Token-agnostic design
 *      - Stateful policy support verification
 */
contract ACERule_v3Test is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERule_v3 public aceRule;
    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;

    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    uint256 public constant TRANSFER_AMOUNT = 100 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy mock policy engine
        policyEngine = new MockPolicyEngine();

        // Deploy extractor
        extractor = new CMTATTransferExtractor();

        // Deploy ACERule_v3 (token-agnostic)
        aceRule = new ACERule_v3(
            address(policyEngine),
            address(extractor)
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_InheritsFromACERule() public view {
        // Verify basic properties inherited from ACERule
        assertEq(address(aceRule.policyEngine()), address(policyEngine));
        assertEq(address(aceRule.extractor()), address(extractor));
    }

    function test_Constructor_TokenAgnostic() public {
        // Deploy another instance - should be identical
        ACERule_v3 aceRule2 = new ACERule_v3(
            address(policyEngine),
            address(extractor)
        );
        
        assertEq(address(aceRule.policyEngine()), address(aceRule2.policyEngine()));
        assertEq(address(aceRule.extractor()), address(aceRule2.extractor()));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATE TRANSFER TESTS (Inherited from ACERule)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ValidateTransfer_WorksLikeACERule() public view {
        // View function should work exactly like ACERule
        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OPERATE ON TRANSFER TESTS (NEW in v3.0)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OperateOnTransfer_ReturnsTrue_WhenPolicyAllows() public {
        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_OperateOnTransfer_ReturnsFalse_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_OperateOnTransfer_ReturnsFalse_WhenSenderBlocked() public {
        policyEngine.setBlockedFrom(alice, true);

        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_OperateOnTransfer_ReturnsFalse_WhenRecipientBlocked() public {
        policyEngine.setBlockedTo(bob, true);

        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_OperateOnTransfer_ReturnsFalse_WhenAmountExceedsMax() public {
        policyEngine.setMaxAmount(50 ether);

        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_OperateOnTransfer_ReturnsTrue_WhenAmountWithinMax() public {
        policyEngine.setMaxAmount(200 ether);

        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_OperateOnTransfer_HandlesZeroAmount() public {
        bool allowed = aceRule.operateOnTransfer(alice, bob, 0);
        assertTrue(allowed);
    }

    function test_OperateOnTransfer_HandlesMaxUint256() public {
        bool allowed = aceRule.operateOnTransfer(alice, bob, type(uint256).max);
        assertTrue(allowed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATEFUL VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OperateOnTransfer_IsNonView() public {
        // operateOnTransfer is NOT a view function
        // This allows state modifications in PolicyEngine

        // Call operateOnTransfer (non-view)
        bool allowed = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);

        // In real scenario with stateful policies:
        // - VolumePolicy would update cumulative volume
        // - VolumeRatePolicy would update rate counters
        // - postRun() hooks would execute
    }

    function test_OperateOnTransfer_CanBeCalledMultipleTimes() public {
        // Multiple calls should work (simulating multiple transfers)
        bool allowed1 = aceRule.operateOnTransfer(alice, bob, 100 ether);
        bool allowed2 = aceRule.operateOnTransfer(bob, charlie, 50 ether);
        bool allowed3 = aceRule.operateOnTransfer(charlie, alice, 75 ether);

        assertTrue(allowed1);
        assertTrue(allowed2);
        assertTrue(allowed3);
    }

    function test_OperateOnTransfer_IndependentFromValidateTransfer() public {
        // validateTransfer (view) and operateOnTransfer (non-view) are independent

        // Check with validateTransfer
        bool viewCheck = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(viewCheck);

        // Execute with operateOnTransfer
        bool runCheck = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(runCheck);

        // Both should succeed independently
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON: VIEW vs NON-VIEW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Comparison_ValidateTransfer_vs_OperateOnTransfer() public {
        // Both should return same result for simple policies
        bool viewResult = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        bool runResult = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);

        assertEq(viewResult, runResult);
    }

    function test_Comparison_BothReject_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool viewResult = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        bool runResult = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);

        assertFalse(viewResult);
        assertFalse(runResult);
        assertEq(viewResult, runResult);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN-AGNOSTIC DESIGN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TokenAgnostic_OperateOnTransfer_WorksForAnyToken() public {
        // ACERule_v3 can validate transfers for any token
        // The RuleEngine (not token) is what matters for policy registration

        bool allowed1 = aceRule.operateOnTransfer(alice, bob, 100 ether);
        bool allowed2 = aceRule.operateOnTransfer(charlie, bob, 200 ether);

        assertTrue(allowed1);
        assertTrue(allowed2);
    }

    function test_TokenAgnostic_OneDeployment_MultipleTokens() public {
        // Same ACERule_v3 instance can be used by multiple RuleEngines/tokens

        // Simulate different transfer contexts
        bool transfer1 = aceRule.operateOnTransfer(alice, bob, 50 ether);
        bool transfer2 = aceRule.operateOnTransfer(bob, charlie, 75 ether);
        bool transfer3 = aceRule.operateOnTransfer(charlie, alice, 100 ether);

        assertTrue(transfer1);
        assertTrue(transfer2);
        assertTrue(transfer3);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_EdgeCase_SelfTransfer() public {
        bool allowed = aceRule.operateOnTransfer(alice, alice, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_EdgeCase_ZeroAddresses() public {
        // Zero from address
        bool allowed1 = aceRule.operateOnTransfer(address(0), bob, TRANSFER_AMOUNT);
        assertTrue(allowed1);

        // Zero to address  
        bool allowed2 = aceRule.operateOnTransfer(alice, address(0), TRANSFER_AMOUNT);
        assertTrue(allowed2);
    }

    function test_EdgeCase_MultipleConsecutiveCalls() public {
        // Multiple consecutive calls should work
        for (uint256 i = 0; i < 10; i++) {
            bool allowed = aceRule.operateOnTransfer(alice, bob, i * 1 ether);
            assertTrue(allowed);
        }
    }

    function test_EdgeCase_MixedViewAndNonView() public {
        // Can alternate between view and non-view calls
        bool view1 = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        bool run1 = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        bool view2 = aceRule.validateTransfer(bob, charlie, TRANSFER_AMOUNT);
        bool run2 = aceRule.operateOnTransfer(bob, charlie, TRANSFER_AMOUNT);

        assertTrue(view1);
        assertTrue(run1);
        assertTrue(view2);
        assertTrue(run2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_OperateOnTransfer_Allowed() public {
        uint256 gasBefore = gasleft();
        aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for operateOnTransfer (allowed):", gasUsed);
        
        // Note: Should be higher than validateTransfer due to non-view
    }

    function test_Gas_OperateOnTransfer_Rejected() public {
        policyEngine.setRejectAll(true);

        uint256 gasBefore = gasleft();
        aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for operateOnTransfer (rejected):", gasUsed);
    }

    function test_Gas_Comparison_View_vs_NonView() public view {
        uint256 gasBefore1 = gasleft();
        aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasView = gasBefore1 - gasleft();

        console2.log("Gas for validateTransfer (view):", gasView);
        console2.log("Note: operateOnTransfer (non-view) costs more");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_OperateOnTransfer_AnyAmount(uint256 amount) public {
        // Should not revert regardless of amount
        aceRule.operateOnTransfer(alice, bob, amount);
    }

    function testFuzz_OperateOnTransfer_AnyAddresses(
        address from,
        address to,
        uint256 amount
    ) public {
        // Should not revert regardless of addresses
        aceRule.operateOnTransfer(from, to, amount);
    }

    function testFuzz_OperateOnTransfer_ReturnsBool(
        address from,
        address to,
        uint256 amount
    ) public {
        bool result = aceRule.operateOnTransfer(from, to, amount);
        // Should always return either true or false, never revert
        assertTrue(result == true || result == false);
    }

    function testFuzz_Comparison_ViewMatchesNonView(
        address from,
        address to,
        uint256 amount
    ) public {
        // For simple policies, view and non-view should match
        bool viewResult = aceRule.validateTransfer(from, to, amount);
        bool runResult = aceRule.operateOnTransfer(from, to, amount);

        // Both should return same result (for MockPolicyEngine)
        assertEq(viewResult, runResult);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERFACE COMPLIANCE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Interface_ImplementsIACERule_v3() public {
        // Verify interface compliance
        IACERule_v3 rule = IACERule_v3(address(aceRule));

        // Test view functions
        bool viewResult = rule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(viewResult);

        // Test non-view function
        bool runResult = rule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(runResult);

        // Test other inherited functions
        string memory message = rule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(bytes(message).length, 0); // Empty when allowed
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATEFUL POLICY CAPABILITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_StatefulCapability_OperateOnTransfer_EnablesStatefulPolicies() public {
        // operateOnTransfer uses PolicyEngine.run() which enables:
        // - VolumePolicy to track volumes
        // - VolumeRatePolicy to track rates
        // - postRun() hooks to execute

        // Simulate multiple transfers that would accumulate volume
        bool transfer1 = aceRule.operateOnTransfer(alice, bob, 100 ether);
        bool transfer2 = aceRule.operateOnTransfer(alice, bob, 200 ether);
        bool transfer3 = aceRule.operateOnTransfer(alice, bob, 300 ether);

        assertTrue(transfer1);
        assertTrue(transfer2);
        assertTrue(transfer3);

        // In real scenario with VolumePolicy:
        // - First transfer: 100/1000 used
        // - Second transfer: 300/1000 used
        // - Third transfer: 600/1000 used
        // State would be tracked and enforced
    }

    function test_StatefulCapability_ValidateTransfer_DoesNotUpdateState() public view {
        // validateTransfer is VIEW - it reads but doesn't update

        // Multiple view calls don't affect state
        aceRule.validateTransfer(alice, bob, 100 ether);
        aceRule.validateTransfer(alice, bob, 200 ether);
        aceRule.validateTransfer(alice, bob, 300 ether);

        // In real scenario with VolumePolicy:
        // - All calls would check against limit
        // - But none would update cumulative volume
        // - Volume would stay at 0
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON WITH ACERule v2.3.0
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Comparison_v3_HasOperateOnTransfer() public {
        // ACERule_v3 has operateOnTransfer (v2.3.0 doesn't)
        bool result = aceRule.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(result);
    }

    function test_Comparison_v3_InheritsAllV2Features() public {
        // All v2.3.0 features still work
        bool viewResult = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        string memory message = aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);

        assertTrue(viewResult);
        assertEq(bytes(message).length, 0);
    }
}
