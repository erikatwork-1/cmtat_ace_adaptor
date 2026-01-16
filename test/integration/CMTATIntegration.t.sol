// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERuleEngineAdapter} from "../../src/adapter/ACERuleEngineAdapter.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";

/**
 * @title CMTATIntegrationTest
 * @notice Integration tests demonstrating full CMTAT + ACE adapter workflow.
 * @dev Tests the complete flow:
 *      1. Deploy CMTAT token
 *      2. Deploy ACE PolicyEngine with policies
 *      3. Deploy and configure adapter
 *      4. Switch token's RuleEngine to adapter
 *      5. Test actual token transfers with various policies
 */
contract CMTATIntegrationTest is Test {
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
    address public charlie = address(0x4);
    address public treasury = address(0x5);

    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant USER_BALANCE = 10_000 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Step 1: Deploy CMTAT token (simulated)
        token = new MockCMTATToken("CMTAT Security Token", "CMTAT", admin);

        // Step 2: Deploy ACE PolicyEngine
        policyEngine = new MockPolicyEngine();

        // Step 3: Deploy extractor
        extractor = new CMTATTransferExtractor();

        // Step 4: Deploy adapter
        adapter = new ACERuleEngineAdapter(
            address(policyEngine),
            address(token),
            address(extractor),
            admin
        );

        // Step 5: Configure token to use adapter
        vm.prank(admin);
        token.setRuleEngine(address(adapter));

        // Mint initial supply and distribute to users
        vm.startPrank(admin);
        token.mint(treasury, INITIAL_SUPPLY);
        vm.stopPrank();

        // Transfer from treasury to users
        vm.startPrank(treasury);
        token.transfer(alice, USER_BALANCE);
        token.transfer(bob, USER_BALANCE);
        token.transfer(charlie, USER_BALANCE);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_BasicTransfer_Succeeds() public {
        uint256 amount = 1000 ether;

        vm.prank(alice);
        token.transfer(bob, amount);

        assertEq(token.balanceOf(alice), USER_BALANCE - amount);
        assertEq(token.balanceOf(bob), USER_BALANCE + amount);
    }

    function test_BasicTransferFrom_Succeeds() public {
        uint256 amount = 1000 ether;

        // Alice approves Charlie
        vm.prank(alice);
        token.approve(charlie, amount);

        // Charlie transfers from Alice to Bob
        vm.prank(charlie);
        token.transferFrom(alice, bob, amount);

        assertEq(token.balanceOf(alice), USER_BALANCE - amount);
        assertEq(token.balanceOf(bob), USER_BALANCE + amount);
    }

    function test_MultipleTransfers_InSequence() public {
        uint256 amount = 100 ether;

        // Alice -> Bob
        vm.prank(alice);
        token.transfer(bob, amount);

        // Bob -> Charlie
        vm.prank(bob);
        token.transfer(charlie, amount);

        // Charlie -> Alice (circular)
        vm.prank(charlie);
        token.transfer(alice, amount);

        // Net effect: Alice and Charlie unchanged, Bob loses 1 transfer worth
        assertEq(token.balanceOf(alice), USER_BALANCE);
        assertEq(token.balanceOf(bob), USER_BALANCE);
        assertEq(token.balanceOf(charlie), USER_BALANCE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POLICY REJECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Transfer_RejectedByPolicy() public {
        policyEngine.setRejectAll(true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1000 ether);
    }

    function test_Transfer_RejectedWhenSenderBlocked() public {
        policyEngine.setBlockedFrom(alice, true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1000 ether);

        // Bob can still transfer
        vm.prank(bob);
        token.transfer(charlie, 1000 ether);
    }

    function test_Transfer_RejectedWhenRecipientBlocked() public {
        policyEngine.setBlockedTo(bob, true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1000 ether);

        // But Alice can transfer to Charlie
        vm.prank(alice);
        token.transfer(charlie, 1000 ether);
    }

    function test_Transfer_RejectedWhenAmountExceedsMax() public {
        policyEngine.setMaxAmount(500 ether);

        // Small transfer succeeds
        vm.prank(alice);
        token.transfer(bob, 400 ether);

        // Large transfer fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 600 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RULE ENGINE SWITCHING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SwitchRuleEngine_ToNewAdapter() public {
        // Create a new policy engine that rejects all
        MockPolicyEngine newPolicyEngine = new MockPolicyEngine();
        newPolicyEngine.setRejectAll(true);

        // Create new adapter
        ACERuleEngineAdapter newAdapter = new ACERuleEngineAdapter(
            address(newPolicyEngine),
            address(token),
            address(extractor),
            admin
        );

        // Transfer works with original adapter
        vm.prank(alice);
        token.transfer(bob, 100 ether);

        // Switch to new adapter
        vm.prank(admin);
        token.setRuleEngine(address(newAdapter));

        // Transfer now fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100 ether);
    }

    function test_SwitchRuleEngine_BackToOriginal() public {
        // Create rejecting adapter
        MockPolicyEngine newPolicyEngine = new MockPolicyEngine();
        newPolicyEngine.setRejectAll(true);
        ACERuleEngineAdapter newAdapter = new ACERuleEngineAdapter(
            address(newPolicyEngine),
            address(token),
            address(extractor),
            admin
        );

        // Switch to rejecting adapter
        vm.prank(admin);
        token.setRuleEngine(address(newAdapter));

        // Transfer fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100 ether);

        // Switch back to original adapter
        vm.prank(admin);
        token.setRuleEngine(address(adapter));

        // Transfer works again
        vm.prank(alice);
        token.transfer(bob, 100 ether);
    }

    function test_DisableRuleEngine() public {
        // With rule engine
        policyEngine.setRejectAll(true);
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100 ether);

        // Disable rule engine
        vm.prank(admin);
        token.setRuleEngine(address(0));

        // Transfer works even though policy engine rejects
        vm.prank(alice);
        token.transfer(bob, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RESTRICTION CODE AND MESSAGE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CanTransfer_PreValidation() public view {
        // Check if transfer would be allowed
        bool canTransfer = token.canTransfer(alice, bob, 1000 ether);
        assertTrue(canTransfer);
    }

    function test_CanTransfer_ReturnsFalse_WhenRejected() public {
        policyEngine.setRejectAll(true);

        bool canTransfer = token.canTransfer(alice, bob, 1000 ether);
        assertFalse(canTransfer);
    }

    function test_GetTransferRestriction_ReturnsCode() public {
        // No restriction
        uint8 code1 = token.getTransferRestriction(alice, bob, 1000 ether);
        assertEq(code1, 0);

        // Policy rejection
        policyEngine.setRejectAll(true);
        uint8 code2 = token.getTransferRestriction(alice, bob, 1000 ether);
        assertEq(code2, 1);
    }

    function test_GetRestrictionMessage() public view {
        string memory msg0 = token.getRestrictionMessage(0);
        assertEq(msg0, "No restriction");

        string memory msg1 = token.getRestrictionMessage(1);
        assertEq(msg1, "Transfer rejected by compliance policy");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH OPERATIONS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_BatchTransfers_AllSucceed() public {
        address[] memory recipients = new address[](3);
        recipients[0] = bob;
        recipients[1] = charlie;
        recipients[2] = treasury;

        uint256 amount = 100 ether;

        vm.startPrank(alice);
        for (uint256 i = 0; i < recipients.length; i++) {
            token.transfer(recipients[i], amount);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(alice), USER_BALANCE - (amount * 3));
    }

    function test_BatchTransfers_PartialFailure() public {
        // Block transfers to Charlie
        policyEngine.setBlockedTo(charlie, true);

        uint256 amount = 100 ether;

        // Transfer to Bob succeeds
        vm.prank(alice);
        token.transfer(bob, amount);

        // Transfer to Charlie fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(charlie, amount);

        // Balance reflects only the successful transfer
        assertEq(token.balanceOf(alice), USER_BALANCE - amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SelfTransfer_Succeeds() public {
        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        token.transfer(alice, 100 ether);

        assertEq(token.balanceOf(alice), balanceBefore);
    }

    function test_ZeroAmountTransfer_Succeeds() public {
        vm.prank(alice);
        token.transfer(bob, 0);

        // Balances unchanged
        assertEq(token.balanceOf(alice), USER_BALANCE);
        assertEq(token.balanceOf(bob), USER_BALANCE);
    }

    function test_MaxAmountTransfer_Succeeds() public {
        // Give Alice a large balance for this test
        uint256 largeAmount = 1_000_000_000 ether;

        vm.prank(admin);
        token.mint(alice, largeAmount);

        vm.prank(alice);
        token.transfer(bob, largeAmount);

        assertEq(token.balanceOf(bob), USER_BALANCE + largeAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CUSTOM RESTRICTION MESSAGE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CustomRestrictionMessage() public {
        // Set custom message for code 1
        vm.prank(admin);
        adapter.setRestrictionMessage(1, "AML/KYC check failed");

        string memory message = adapter.messageForTransferRestriction(1);
        assertEq(message, "AML/KYC check failed");

        // Also accessible via token
        string memory tokenMessage = token.getRestrictionMessage(1);
        assertEq(tokenMessage, "AML/KYC check failed");
    }

    function test_CustomRestrictionMessage_ForNewCode() public {
        // Set message for a new code
        vm.prank(admin);
        adapter.setRestrictionMessage(10, "Accredited investor required");

        string memory message = adapter.messageForTransferRestriction(10);
        assertEq(message, "Accredited investor required");
    }
}
