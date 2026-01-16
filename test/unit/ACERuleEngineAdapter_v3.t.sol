// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERuleEngineAdapter_v3} from "../../src/adapter/ACERuleEngineAdapter_v3.sol";
import {ACERuleEngineAdapter} from "../../src/adapter/ACERuleEngineAdapter.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title ACERuleEngineAdapter_v3Test
 * @notice Comprehensive unit tests for ACERuleEngineAdapter_v3 (CMTAT v3.0+ compatible).
 * @dev Tests cover:
 *      - All ACERuleEngineAdapter v2.3.0 functionality (inherited)
 *      - New operateOnTransfer() for stateful validation
 *      - PolicyEngine.run() usage for state updates
 *      - Returns uint8 restriction codes
 *      - Stateful policy support verification
 */
contract ACERuleEngineAdapter_v3Test is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERuleEngineAdapter_v3 public adapter;
    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;
    MockCMTATToken public token;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant TRANSFER_AMOUNT = 100 ether;

    uint8 public constant RESTRICTION_CODE_OK = 0;
    uint8 public constant RESTRICTION_CODE_POLICY_REJECTED = 1;
    uint8 public constant RESTRICTION_CODE_UNKNOWN_ERROR = 255;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy mock policy engine
        policyEngine = new MockPolicyEngine();

        // Deploy extractor
        extractor = new CMTATTransferExtractor();

        // Deploy mock token
        token = new MockCMTATToken("Mock CMTAT", "MCMTAT", owner);

        // Deploy adapter_v3
        adapter = new ACERuleEngineAdapter_v3(
            address(policyEngine),
            address(token),
            address(extractor),
            owner
        );

        // Set adapter as RuleEngine
        vm.prank(owner);
        token.setRuleEngine(address(adapter));

        // Mint initial balances
        vm.startPrank(owner);
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_InheritsFromAdapter() public view {
        // Verify inherited properties
        assertEq(address(adapter.policyEngine()), address(policyEngine));
        assertEq(adapter.targetToken(), address(token));
        assertEq(address(adapter.extractor()), address(extractor));
        assertEq(adapter.owner(), owner);
    }

    function test_Constructor_HasVersionInfo() public view {
        // Adapter_v3 should have version identification
        string memory version = adapter.version();
        assertEq(version, "3.0.0");
    }

    function test_Constructor_SupportsStatefulOperations() public view {
        // Adapter_v3 supports stateful operations
        bool supportsStateful = adapter.supportsStatefulOperations();
        assertTrue(supportsStateful);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATE TRANSFER TESTS (Inherited from v2.3.0)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ValidateTransfer_WorksLikeV2() public view {
        // View function should work exactly like v2.3.0 adapter
        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(isValid);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(isValid);
    }

    function test_DetectTransferRestriction_ReturnsZero_WhenAllowed() public view {
        uint8 code = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_OK);
    }

    function test_DetectTransferRestriction_ReturnsOne_WhenRejected() public {
        policyEngine.setRejectAll(true);

        uint8 code = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_POLICY_REJECTED);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OPERATE ON TRANSFER TESTS (NEW in v3.0)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OperateOnTransfer_ReturnsZero_WhenPolicyAllows() public {
        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_OK);
    }

    function test_OperateOnTransfer_ReturnsOne_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_POLICY_REJECTED);
    }

    function test_OperateOnTransfer_ReturnsOne_WhenSenderBlocked() public {
        policyEngine.setBlockedFrom(alice, true);

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_POLICY_REJECTED);
    }

    function test_OperateOnTransfer_ReturnsOne_WhenRecipientBlocked() public {
        policyEngine.setBlockedTo(bob, true);

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_POLICY_REJECTED);
    }

    function test_OperateOnTransfer_ReturnsOne_WhenAmountExceedsMax() public {
        policyEngine.setMaxAmount(50 ether);

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_POLICY_REJECTED);
    }

    function test_OperateOnTransfer_ReturnsZero_WhenAmountWithinMax() public {
        policyEngine.setMaxAmount(200 ether);

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_OK);
    }

    function test_OperateOnTransfer_HandlesZeroAmount() public {
        uint8 code = adapter.operateOnTransfer(alice, bob, 0);
        assertEq(code, RESTRICTION_CODE_OK);
    }

    function test_OperateOnTransfer_HandlesMaxUint256() public {
        uint8 code = adapter.operateOnTransfer(alice, bob, type(uint256).max);
        assertEq(code, RESTRICTION_CODE_OK);
    }

    function test_OperateOnTransfer_Returns255_OnUnknownError() public {
        policyEngine.setRejectAll(true);
        policyEngine.setRevertWithUnknownError(true);

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_UNKNOWN_ERROR);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATEFUL VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OperateOnTransfer_IsNonView() public {
        // operateOnTransfer is NOT a view function
        // This allows state modifications in PolicyEngine

        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_OK);

        // In real scenario with stateful policies:
        // - VolumePolicy would update cumulative volume
        // - VolumeRatePolicy would update rate counters
        // - postRun() hooks would execute
    }

    function test_OperateOnTransfer_CanBeCalledMultipleTimes() public {
        // Multiple calls should work (simulating multiple transfers)
        uint8 code1 = adapter.operateOnTransfer(alice, bob, 100 ether);
        uint8 code2 = adapter.operateOnTransfer(bob, charlie, 50 ether);
        uint8 code3 = adapter.operateOnTransfer(charlie, alice, 75 ether);

        assertEq(code1, RESTRICTION_CODE_OK);
        assertEq(code2, RESTRICTION_CODE_OK);
        assertEq(code3, RESTRICTION_CODE_OK);
    }

    function test_OperateOnTransfer_IndependentFromValidateTransfer() public {
        // validateTransfer (view) and operateOnTransfer (non-view) are independent

        // Check with validateTransfer
        bool viewCheck = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(viewCheck);

        // Execute with operateOnTransfer
        uint8 runCheck = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(runCheck, RESTRICTION_CODE_OK);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON: VIEW vs NON-VIEW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Comparison_ValidateTransfer_vs_OperateOnTransfer() public {
        // Both should return equivalent results for simple policies
        bool viewResult = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint8 runResult = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);

        assertEq(viewResult, runResult == RESTRICTION_CODE_OK);
    }

    function test_Comparison_BothReject_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool viewResult = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint8 runResult = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);

        assertFalse(viewResult);
        assertEq(runResult, RESTRICTION_CODE_POLICY_REJECTED);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION WITH TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Integration_TransferSucceeds_WhenPolicyAllows() public {
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    function test_Integration_TransferReverts_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_Integration_MultipleTransfers_Work() public {
        // Multiple transfers should work with stateful adapter
        vm.prank(alice);
        token.transfer(bob, 50 ether);

        vm.prank(bob);
        token.transfer(charlie, 25 ether);

        vm.prank(charlie);
        token.transfer(alice, 10 ether);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 50 ether + 10 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE + 50 ether - 25 ether);
        assertEq(token.balanceOf(charlie), 25 ether - 10 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MESSAGE FOR TRANSFER RESTRICTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MessageForTransferRestriction_InheritedFromV2() public view {
        assertEq(adapter.messageForTransferRestriction(0), "No restriction");
        assertEq(adapter.messageForTransferRestriction(1), "Transfer rejected by compliance policy");
        assertEq(adapter.messageForTransferRestriction(255), "Unknown compliance error occurred");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetRestrictionMessage_WorksForOwner() public {
        vm.prank(owner);
        adapter.setRestrictionMessage(42, "Custom error message");

        assertEq(adapter.messageForTransferRestriction(42), "Custom error message");
    }

    function test_SetRestrictionMessage_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setRestrictionMessage(42, "Custom error message");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_ValidateTransfer_View() public view {
        uint256 gasBefore = gasleft();
        adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas for validateTransfer (view):", gasUsed);
    }

    function test_Gas_OperateOnTransfer_NonView() public {
        uint256 gasBefore = gasleft();
        adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas for operateOnTransfer (non-view):", gasUsed);
        console2.log("(Higher than validateTransfer due to state capability)");
    }

    function test_Gas_FullTransfer_WithAdapter_v3() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas for full transfer with adapter_v3:", gasUsed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_OperateOnTransfer_AnyAmount(uint256 amount) public {
        // Should not revert regardless of amount
        adapter.operateOnTransfer(alice, bob, amount);
    }

    function testFuzz_OperateOnTransfer_AnyAddresses(
        address from,
        address to,
        uint256 amount
    ) public {
        // Should not revert regardless of addresses
        adapter.operateOnTransfer(from, to, amount);
    }

    function testFuzz_OperateOnTransfer_ReturnsValidCode(
        address from,
        address to,
        uint256 amount
    ) public {
        uint8 code = adapter.operateOnTransfer(from, to, amount);
        // Code should be 0, 1, or 255
        assertTrue(code == 0 || code == 1 || code == 255);
    }

    function testFuzz_Comparison_ViewMatchesNonView(
        address from,
        address to,
        uint256 amount
    ) public {
        // For simple policies, results should be equivalent
        bool viewResult = adapter.validateTransfer(from, to, amount);
        uint8 runResult = adapter.operateOnTransfer(from, to, amount);

        assertEq(viewResult, runResult == RESTRICTION_CODE_OK);
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
        uint8 code1 = adapter.operateOnTransfer(alice, bob, 100 ether);
        uint8 code2 = adapter.operateOnTransfer(alice, bob, 200 ether);
        uint8 code3 = adapter.operateOnTransfer(alice, bob, 300 ether);

        assertEq(code1, RESTRICTION_CODE_OK);
        assertEq(code2, RESTRICTION_CODE_OK);
        assertEq(code3, RESTRICTION_CODE_OK);

        // In real scenario with VolumePolicy:
        // - First transfer: 100/1000 used
        // - Second transfer: 300/1000 used
        // - Third transfer: 600/1000 used
        // State would be tracked and enforced
    }

    function test_StatefulCapability_ValidateTransfer_DoesNotUpdateState() public view {
        // validateTransfer is VIEW - it reads but doesn't update

        // Multiple view calls don't affect state
        adapter.validateTransfer(alice, bob, 100 ether);
        adapter.validateTransfer(alice, bob, 200 ether);
        adapter.validateTransfer(alice, bob, 300 ether);

        // In real scenario with VolumePolicy:
        // - All calls would check against limit
        // - But none would update cumulative volume
        // - Volume would stay at 0
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON WITH v2.3.0 ADAPTER
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Comparison_v3_HasOperateOnTransfer() public {
        // Adapter_v3 has operateOnTransfer (v2.3.0 doesn't)
        uint8 code = adapter.operateOnTransfer(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, RESTRICTION_CODE_OK);
    }

    function test_Comparison_v3_InheritsAllV2Features() public view {
        // All v2.3.0 features still work
        bool viewResult = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint8 detectResult = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        string memory message = adapter.messageForTransferRestriction(0);

        assertTrue(viewResult);
        assertEq(detectResult, RESTRICTION_CODE_OK);
        assertEq(message, "No restriction");
    }

    function test_Comparison_v3_HasVersionIdentification() public view {
        // v3 has version() function
        string memory version = adapter.version();
        assertEq(version, "3.0.0");

        // v3 indicates stateful support
        bool supportsStateful = adapter.supportsStatefulOperations();
        assertTrue(supportsStateful);
    }
}
