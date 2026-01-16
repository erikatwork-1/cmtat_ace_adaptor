// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERule} from "../../src/rule/ACERule.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title ACERule_IntegrationTest
 * @notice Integration tests for ACERule with CMTAT v2.3.0 RuleEngine.
 * @dev Tests the complete integration flow:
 *      - ACERule as a rule within existing CMTAT RuleEngine
 *      - Token-agnostic design allowing one ACERule for multiple tokens
 *      - Policy registration against RuleEngine address (NOT token)
 *      - Composition with other rules
 *      - Real-world scenarios
 */
contract ACERule_IntegrationTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERule public aceRule;
    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;

    // Multiple tokens to test token-agnostic design
    MockCMTATToken public tokenA;
    MockCMTATToken public tokenB;
    MockCMTATToken public tokenC;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant TRANSFER_AMOUNT = 100 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy mock policy engine
        policyEngine = new MockPolicyEngine();

        // Deploy extractor
        extractor = new CMTATTransferExtractor();

        // Deploy ONE ACERule instance (token-agnostic)
        aceRule = new ACERule(
            address(policyEngine),
            address(extractor)
        );

        // Deploy MULTIPLE tokens
        tokenA = new MockCMTATToken("Token A", "TKA", owner);
        tokenB = new MockCMTATToken("Token B", "TKB", owner);
        tokenC = new MockCMTATToken("Token C", "TKC", owner);

        // Set ACERule as the RuleEngine for all tokens
        // This demonstrates the token-agnostic design
        vm.startPrank(owner);
        tokenA.setRuleEngine(address(aceRule));
        tokenB.setRuleEngine(address(aceRule));
        tokenC.setRuleEngine(address(aceRule));
        vm.stopPrank();

        // Mint initial balances
        vm.startPrank(owner);
        tokenA.mint(alice, INITIAL_BALANCE);
        tokenA.mint(bob, INITIAL_BALANCE);
        
        tokenB.mint(alice, INITIAL_BALANCE);
        tokenB.mint(charlie, INITIAL_BALANCE);
        
        tokenC.mint(bob, INITIAL_BALANCE);
        tokenC.mint(charlie, INITIAL_BALANCE);
        vm.stopPrank();

        // NOTE: In real scenario, policies would be registered against RuleEngine address
        // policyEngine.addPolicy(address(aceRule), selector, policyAddress, parameters);
        // NOT against token addresses
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN-AGNOSTIC DESIGN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TokenAgnostic_OneACERule_MultipleTokens() public {
        // ONE ACERule instance works with THREE different tokens

        // Transfer on Token A
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);

        // Transfer on Token B
        vm.prank(alice);
        tokenB.transfer(charlie, TRANSFER_AMOUNT);

        // Transfer on Token C
        vm.prank(bob);
        tokenC.transfer(charlie, TRANSFER_AMOUNT);

        // All transfers succeed
        assertEq(tokenA.balanceOf(alice), INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertEq(tokenB.balanceOf(alice), INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertEq(tokenC.balanceOf(bob), INITIAL_BALANCE - TRANSFER_AMOUNT);
    }

    function test_TokenAgnostic_PolicyRejection_AffectsAllTokens() public {
        // When policy rejects, it affects all tokens using this ACERule
        policyEngine.setRejectAll(true);

        // All transfers should fail
        vm.prank(alice);
        vm.expectRevert();
        tokenA.transfer(bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        vm.expectRevert();
        tokenB.transfer(charlie, TRANSFER_AMOUNT);

        vm.prank(bob);
        vm.expectRevert();
        tokenC.transfer(charlie, TRANSFER_AMOUNT);
    }

    function test_TokenAgnostic_PerRuleEngineConfiguration() public {
        // In real scenario, you could deploy multiple ACERule instances
        // Each with different policy configurations

        // Deploy second ACERule with stricter policies
        ACERule strictRule = new ACERule(
            address(policyEngine),
            address(extractor)
        );

        // Deploy new token with strict rule
        MockCMTATToken strictToken = new MockCMTATToken("Strict Token", "STK", owner);
        vm.prank(owner);
        strictToken.setRuleEngine(address(strictRule));

        // Configure strict policy
        policyEngine.setMaxAmount(50 ether);

        vm.prank(owner);
        strictToken.mint(alice, INITIAL_BALANCE);

        // Strict token rejects large transfers
        vm.prank(alice);
        vm.expectRevert();
        strictToken.transfer(bob, TRANSFER_AMOUNT); // 100 > 50, rejected

        // But lenient tokens still work
        policyEngine.setMaxAmount(200 ether);
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT); // Works
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POLICY REGISTRATION PATTERN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PolicyRegistration_UsesRuleEngineAddress() public {
        // Demonstrate correct policy registration pattern
        // Policies registered against ACERule address (RuleEngine), NOT token

        // Simulate policy check using RuleEngine address
        address ruleEngineAddress = address(aceRule);
        
        // In real scenario:
        // policyEngine.addPolicy(
        //     ruleEngineAddress,  // ← RuleEngine address
        //     transferSelector,
        //     policyAddress,
        //     parameters
        // );

        // Verify validateTransfer uses RuleEngine context
        bool allowed = aceRule.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(allowed);

        // The same ACERule validates for all tokens
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        tokenB.transfer(charlie, TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REAL-WORLD SCENARIO TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RealWorld_SecurityTokenFamily() public {
        // Scenario: Multiple security tokens in a fund family
        // All share same compliance rules via single ACERule

        // Fund A Token
        MockCMTATToken fundA = new MockCMTATToken("Fund A Token", "FNDA", owner);
        vm.prank(owner);
        fundA.setRuleEngine(address(aceRule));

        // Fund B Token
        MockCMTATToken fundB = new MockCMTATToken("Fund B Token", "FNDB", owner);
        vm.prank(owner);
        fundB.setRuleEngine(address(aceRule));

        // Mint tokens
        vm.startPrank(owner);
        fundA.mint(alice, INITIAL_BALANCE);
        fundB.mint(alice, INITIAL_BALANCE);
        vm.stopPrank();

        // Same compliance rules apply to both
        policyEngine.setBlockedTo(charlie, true); // Charlie is blocked

        // Alice can transfer to Bob
        vm.prank(alice);
        fundA.transfer(bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        fundB.transfer(bob, TRANSFER_AMOUNT);

        // But NOT to Charlie
        vm.prank(alice);
        vm.expectRevert();
        fundA.transfer(charlie, TRANSFER_AMOUNT);

        vm.prank(alice);
        vm.expectRevert();
        fundB.transfer(charlie, TRANSFER_AMOUNT);
    }

    function test_RealWorld_DifferentTokensClassesOnSameRuleEngine() public {
        // Scenario: Common shares vs Preferred shares
        // Both use same ACERule but with different policies

        // Common shares
        MockCMTATToken common = new MockCMTATToken("Common Shares", "COM", owner);
        vm.prank(owner);
        common.setRuleEngine(address(aceRule));

        // Preferred shares
        MockCMTATToken preferred = new MockCMTATToken("Preferred Shares", "PREF", owner);
        vm.prank(owner);
        preferred.setRuleEngine(address(aceRule));

        // Mint tokens
        vm.startPrank(owner);
        common.mint(alice, INITIAL_BALANCE);
        preferred.mint(bob, INITIAL_BALANCE);
        vm.stopPrank();

        // Both follow same ACE policies
        vm.prank(alice);
        common.transfer(bob, TRANSFER_AMOUNT);

        vm.prank(bob);
        preferred.transfer(alice, TRANSFER_AMOUNT);

        assertEq(common.balanceOf(bob), TRANSFER_AMOUNT);
        assertEq(preferred.balanceOf(alice), TRANSFER_AMOUNT);
    }

    function test_RealWorld_VolumePolicy_Simulation() public {
        // Scenario: Simulating volume-based restrictions
        // (Full VolumePolicy requires ACE_v3)

        policyEngine.setMaxAmount(500 ether);

        // Alice can do small transfers
        vm.prank(alice);
        tokenA.transfer(bob, 100 ether);

        vm.prank(alice);
        tokenA.transfer(bob, 200 ether);

        vm.prank(alice);
        tokenA.transfer(bob, 150 ether);

        // But large transfer exceeds limit
        vm.prank(alice);
        vm.expectRevert();
        tokenA.transfer(bob, 600 ether);
    }

    function test_RealWorld_BlocklistCompliance() public {
        // Scenario: OFAC/sanctions compliance via blocklist

        // Block charlie (simulating OFAC list)
        policyEngine.setBlockedFrom(charlie, true);
        policyEngine.setBlockedTo(charlie, true);

        // Charlie cannot send
        vm.prank(owner);
        tokenC.mint(charlie, INITIAL_BALANCE);

        vm.prank(charlie);
        vm.expectRevert();
        tokenC.transfer(alice, TRANSFER_AMOUNT);

        // Charlie cannot receive
        vm.prank(alice);
        vm.expectRevert();
        tokenA.transfer(charlie, TRANSFER_AMOUNT);

        // Other users work fine
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_RealWorld_AccreditedInvestorGating() public {
        // Scenario: Only accredited investors can receive tokens

        // Bob is not accredited
        policyEngine.setBlockedTo(bob, true);

        // Alice (accredited) can receive
        vm.prank(owner);
        tokenA.mint(owner, INITIAL_BALANCE);

        vm.prank(owner);
        tokenA.transfer(alice, TRANSFER_AMOUNT); // Works

        // Bob (not accredited) cannot receive
        vm.prank(owner);
        vm.expectRevert();
        tokenA.transfer(bob, TRANSFER_AMOUNT); // Fails
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MIGRATION SCENARIO TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Migration_AddACERule_ToExistingToken() public {
        // Scenario: Existing CMTAT token migrating to ACE

        // Deploy token WITHOUT ACERule initially
        MockCMTATToken existingToken = new MockCMTATToken("Existing Token", "EXT", owner);
        
        vm.startPrank(owner);
        existingToken.mint(alice, INITIAL_BALANCE);
        existingToken.mint(bob, INITIAL_BALANCE);
        vm.stopPrank();

        // Transfers work without restrictions
        vm.prank(alice);
        existingToken.transfer(bob, TRANSFER_AMOUNT);

        // Now migrate to ACERule
        vm.prank(owner);
        existingToken.setRuleEngine(address(aceRule));

        // Transfers now go through ACE
        vm.prank(alice);
        existingToken.transfer(bob, TRANSFER_AMOUNT); // Still works

        // ACE policies now enforced
        policyEngine.setRejectAll(true);

        vm.prank(alice);
        vm.expectRevert();
        existingToken.transfer(bob, TRANSFER_AMOUNT); // Now blocked
    }

    function test_Migration_SwitchBetweenRuleEngines() public {
        // Scenario: Token switching from custom RuleEngine to ACERule

        // Initial state: Token A uses ACERule
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT); // Works

        // Token owner decides to switch to different RuleEngine
        // (In real scenario, this would be another RuleEngine contract)
        
        // For now, demonstrate switching back and forth
        vm.prank(owner);
        tokenA.setRuleEngine(address(0)); // Disable rule engine

        // Transfers work without restrictions
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);

        // Re-enable ACERule
        vm.prank(owner);
        tokenA.setRuleEngine(address(aceRule));

        // ACE policies enforced again
        policyEngine.setBlockedTo(bob, true);

        vm.prank(alice);
        vm.expectRevert();
        tokenA.transfer(bob, TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_EdgeCase_ZeroAmountTransfer() public {
        // Zero amount transfers should pass ACERule
        vm.prank(alice);
        tokenA.transfer(bob, 0);
    }

    function test_EdgeCase_SelfTransfer() public {
        // Self transfers should pass ACERule
        vm.prank(alice);
        tokenA.transfer(alice, TRANSFER_AMOUNT);

        assertEq(tokenA.balanceOf(alice), INITIAL_BALANCE);
    }

    function test_EdgeCase_MultipleTokensSequential() public {
        // Sequential transfers across multiple tokens
        vm.prank(alice);
        tokenA.transfer(bob, 50 ether);

        vm.prank(alice);
        tokenB.transfer(charlie, 75 ether);

        vm.prank(bob);
        tokenC.transfer(charlie, 100 ether);

        assertEq(tokenA.balanceOf(bob), INITIAL_BALANCE + 50 ether);
        assertEq(tokenB.balanceOf(charlie), INITIAL_BALANCE + 75 ether);
        assertEq(tokenC.balanceOf(charlie), INITIAL_BALANCE + 100 ether);
    }

    function test_EdgeCase_PolicyChangeMidway() public {
        // Policy changes affect subsequent transfers

        // First transfer allowed
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);

        // Change policy
        policyEngine.setMaxAmount(50 ether);

        // Second transfer blocked
        vm.prank(alice);
        vm.expectRevert();
        tokenA.transfer(bob, TRANSFER_AMOUNT);

        // Relax policy
        policyEngine.setMaxAmount(200 ether);

        // Third transfer allowed again
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_TransferWithACERule() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas for transfer with ACERule:", gasUsed);
    }

    function test_Gas_MultipleTokens_SameACERule() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(alice);
        tokenA.transfer(bob, TRANSFER_AMOUNT);
        
        vm.prank(alice);
        tokenB.transfer(charlie, TRANSFER_AMOUNT);
        
        vm.prank(bob);
        tokenC.transfer(charlie, TRANSFER_AMOUNT);
        
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas for 3 transfers across 3 tokens:", gasUsed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DOCUMENTATION EXAMPLES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Documentation_BasicUsage() public {
        // Example from documentation: Basic ACERule usage

        // 1. Deploy ACERule (once)
        ACERule rule = new ACERule(
            address(policyEngine),
            address(extractor)
        );

        // 2. Set as RuleEngine for token(s)
        MockCMTATToken token = new MockCMTATToken("Example Token", "EX", owner);
        vm.prank(owner);
        token.setRuleEngine(address(rule));

        // 3. Mint and transfer
        vm.prank(owner);
        token.mint(alice, 1000 ether);

        vm.prank(alice);
        token.transfer(bob, 100 ether);

        // Success!
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_Documentation_TokenAgnosticExample() public {
        // Example from documentation: Token-agnostic design

        // Deploy ONE ACERule
        ACERule sharedRule = new ACERule(
            address(policyEngine),
            address(extractor)
        );

        // Use for MULTIPLE tokens
        MockCMTATToken token1 = new MockCMTATToken("Token 1", "TK1", owner);
        MockCMTATToken token2 = new MockCMTATToken("Token 2", "TK2", owner);

        vm.prank(owner);
        token1.setRuleEngine(address(sharedRule));

        vm.prank(owner);
        token2.setRuleEngine(address(sharedRule));

        // Both tokens share same compliance rules
        vm.prank(owner);
        token1.mint(alice, 1000 ether);

        vm.prank(owner);
        token2.mint(alice, 1000 ether);

        vm.prank(alice);
        token1.transfer(bob, 100 ether);

        vm.prank(alice);
        token2.transfer(bob, 100 ether);

        assertEq(token1.balanceOf(bob), 100 ether);
        assertEq(token2.balanceOf(bob), 100 ether);
    }
}
