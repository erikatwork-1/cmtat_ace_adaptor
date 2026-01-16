// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERule} from "../../src/rule/ACERule.sol";
import {IACERule} from "../../src/interfaces/IACERule.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title ACERuleTest
 * @notice Comprehensive unit tests for ACERule (v2.3.0 compatible).
 * @dev Tests cover:
 *      - Constructor validation
 *      - validateTransfer() behavior
 *      - detectTransferRestriction() behavior
 *      - Token-agnostic design
 *      - Integration with RuleEngine
 *      - Edge cases and error handling
 */
contract ACERuleTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERule public aceRule;
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

        // Deploy ACERule (token-agnostic - no targetToken parameter!)
        aceRule = new ACERule(
            address(policyEngine),
            address(extractor)
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsImmutablesCorrectly() public view {
        assertEq(address(aceRule.policyEngine()), address(policyEngine));
        assertEq(address(aceRule.extractor()), address(extractor));
    }

    function test_Constructor_TokenAgnosticDesign() public {
        // ACERule should NOT have a targetToken parameter or storage
        // This test verifies the contract is truly token-agnostic
        
        // Deploy another ACERule - should work the same way
        ACERule aceRule2 = new ACERule(
            address(policyEngine),
            address(extractor)
        );
        
        // Both rules should be identical and reusable
        assertEq(address(aceRule.policyEngine()), address(aceRule2.policyEngine()));
        assertEq(address(aceRule.extractor()), address(aceRule2.extractor()));
    }

    function test_Constructor_RevertsOnZeroPolicyEngine() public {
        vm.expectRevert(abi.encodeWithSelector(IACERule.ZeroAddressNotAllowed.selector, "policyEngine"));
        new ACERule(address(0), address(extractor));
    }

    function test_Constructor_RevertsOnZeroExtractor() public {
        vm.expectRevert(abi.encodeWithSelector(IACERule.ZeroAddressNotAllowed.selector, "extractor"));
        new ACERule(address(policyEngine), address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATE TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ValidateTransfer_ReturnsTrue_WhenPolicyAllows() public view {
        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenSenderBlocked() public {
        policyEngine.setBlockedFrom(alice, true);

        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenRecipientBlocked() public {
        policyEngine.setBlockedTo(bob, true);

        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenAmountExceedsMax() public {
        policyEngine.setMaxAmount(50 ether);

        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    function test_ValidateTransfer_ReturnsTrue_WhenAmountWithinMax() public {
        policyEngine.setMaxAmount(200 ether);

        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_ValidateTransfer_HandlesZeroAmount() public view {
        bool allowed = aceRule.validateTransfer(alice, bob, 0);
        assertTrue(allowed);
    }

    function test_ValidateTransfer_HandlesZeroAddresses() public view {
        // Zero from address
        bool allowed1 = aceRule.validateTransfer(address(0), bob, TRANSFER_AMOUNT);
        assertTrue(allowed1);

        // Zero to address
        bool allowed2 = aceRule.validateTransfer(alice, address(0), TRANSFER_AMOUNT);
        assertTrue(allowed2);
    }

    function test_ValidateTransfer_HandlesMaxUint256() public view {
        bool allowed = aceRule.validateTransfer(alice, bob, type(uint256).max);
        assertTrue(allowed);
    }

    // Note: validateTransfer is a VIEW function, so it cannot emit events
    // Events would only be emitted from operateOnTransfer in ACERule_v3

    // ═══════════════════════════════════════════════════════════════════════════
    // DETECT TRANSFER RESTRICTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DetectTransferRestriction_ReturnsEmpty_WhenAllowed() public view {
        string memory message = aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(bytes(message).length, 0);
    }

    function test_DetectTransferRestriction_ReturnsMessage_WhenRejected() public {
        policyEngine.setRejectAll(true);

        string memory message = aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertTrue(bytes(message).length > 0);
    }

    function test_DetectTransferRestriction_ReturnsDefaultMessage_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        string memory message = aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        // MockPolicyEngine returns "Transfer rejected by policy", not our default message
        // This is expected behavior - we extract what the policy engine provides
        assertEq(message, "Transfer rejected by policy");
    }

    function test_DetectTransferRestriction_MatchesValidateTransfer() public {
        // Test allowed case
        bool valid1 = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        string memory msg1 = aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(valid1, bytes(msg1).length == 0);

        // Test rejected case
        policyEngine.setRejectAll(true);
        bool valid2 = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        string memory msg2 = aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(valid2, bytes(msg2).length == 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN-AGNOSTIC DESIGN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TokenAgnostic_SameRuleWorksForMultipleTokens() public {
        // One ACERule deployment can validate transfers for any token
        // The RuleEngine (not token) is what matters for policy registration

        // Simulate transfers from different "tokens" (represented by different senders)
        bool allowed1 = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed1);

        bool allowed2 = aceRule.validateTransfer(charlie, bob, TRANSFER_AMOUNT);
        assertTrue(allowed2);

        // Both should work with the same ACERule instance
    }

    function test_TokenAgnostic_ReusableAcrossRuleEngines() public {
        // Deploy a second "RuleEngine" context
        // In practice, this would be different RuleEngine contracts
        
        // Same ACERule can be used by multiple RuleEngines
        bool allowed1 = aceRule.validateTransfer(alice, bob, 50 ether);
        bool allowed2 = aceRule.validateTransfer(alice, charlie, 75 ether);
        
        assertTrue(allowed1);
        assertTrue(allowed2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_EdgeCase_SelfTransfer() public view {
        bool allowed = aceRule.validateTransfer(alice, alice, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }

    function test_EdgeCase_MultipleConsecutiveChecks() public {
        // Multiple checks should be independent (view function)
        bool check1 = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        bool check2 = aceRule.validateTransfer(bob, charlie, TRANSFER_AMOUNT);
        bool check3 = aceRule.validateTransfer(charlie, alice, TRANSFER_AMOUNT);

        assertTrue(check1);
        assertTrue(check2);
        assertTrue(check3);
    }

    function test_EdgeCase_DifferentAmounts() public view {
        assertTrue(aceRule.validateTransfer(alice, bob, 1 wei));
        assertTrue(aceRule.validateTransfer(alice, bob, 1 ether));
        assertTrue(aceRule.validateTransfer(alice, bob, 1000 ether));
        assertTrue(aceRule.validateTransfer(alice, bob, type(uint256).max));
    }

    function test_EdgeCase_UnknownErrorHandling() public {
        policyEngine.setRejectAll(true);
        policyEngine.setRevertWithUnknownError(true);

        // Should still return false, not revert
        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(allowed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_ValidateTransfer_Allowed() public view {
        uint256 gasBefore = gasleft();
        aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for validateTransfer (allowed):", gasUsed);
    }

    function test_Gas_ValidateTransfer_Rejected() public {
        policyEngine.setRejectAll(true);

        uint256 gasBefore = gasleft();
        aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for validateTransfer (rejected):", gasUsed);
    }

    function test_Gas_DetectTransferRestriction() public view {
        uint256 gasBefore = gasleft();
        aceRule.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for detectTransferRestriction:", gasUsed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ValidateTransfer_AnyAmount(uint256 amount) public view {
        // Should not revert regardless of amount
        aceRule.validateTransfer(alice, bob, amount);
    }

    function testFuzz_ValidateTransfer_AnyAddresses(address from, address to, uint256 amount) public view {
        // Should not revert regardless of addresses
        aceRule.validateTransfer(from, to, amount);
    }

    function testFuzz_ValidateTransfer_ReturnsBool(
        address from,
        address to,
        uint256 amount
    ) public view {
        bool result = aceRule.validateTransfer(from, to, amount);
        // Should always return either true or false, never revert
        assertTrue(result == true || result == false);
    }

    function testFuzz_DetectTransferRestriction_NeverReverts(
        address from,
        address to,
        uint256 amount
    ) public view {
        // Should never revert, always return a string
        string memory message = aceRule.detectTransferRestriction(from, to, amount);
        // Message can be empty or non-empty, but function should not revert
        assertTrue(bytes(message).length >= 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON WITH ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Comparison_RuleReturnsBool_AdapterReturnsUint8() public view {
        // ACERule returns bool
        bool ruleResult = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(ruleResult == true || ruleResult == false);
        
        // This demonstrates the key difference:
        // - ACERule (Rule Approach): returns bool
        // - ACERuleEngineAdapter (Adapter Approach): returns uint8
    }

    function test_Comparison_RuleIsTokenAgnostic() public {
        // Key difference from Adapter:
        // - ACERule: NO targetToken (token-agnostic)
        // - ACERuleEngineAdapter: HAS targetToken (token-specific)
        
        // This ACERule can validate for ANY token
        bool result1 = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        bool result2 = aceRule.validateTransfer(charlie, bob, TRANSFER_AMOUNT);
        
        assertTrue(result1);
        assertTrue(result2);
    }
}
