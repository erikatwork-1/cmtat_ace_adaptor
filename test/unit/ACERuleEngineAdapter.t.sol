// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERuleEngineAdapter} from "../../src/adapter/ACERuleEngineAdapter.sol";
import {IACERuleEngineAdapter} from "../../src/interfaces/IACERuleEngineAdapter.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ACERuleEngineAdapterTest
 * @notice Comprehensive unit tests for the ACERuleEngineAdapter.
 * @dev Tests cover:
 *      - Constructor validation
 *      - validateTransfer() behavior
 *      - detectTransferRestriction() behavior
 *      - messageForTransferRestriction() behavior
 *      - Error mapping logic
 *      - Admin functions
 *      - Integration with MockCMTATToken
 */
contract ACERuleEngineAdapterTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERuleEngineAdapter public adapter;
    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;
    MockCMTATToken public token;

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

        // Deploy mock token
        token = new MockCMTATToken("Mock CMTAT", "MCMTAT", owner);

        // Deploy adapter
        adapter = new ACERuleEngineAdapter(
            address(policyEngine),
            address(token),
            address(extractor),
            owner
        );

        // Set up token with adapter as RuleEngine
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

    function test_Constructor_SetsImmutablesCorrectly() public view {
        assertEq(address(adapter.policyEngine()), address(policyEngine));
        assertEq(adapter.targetToken(), address(token));
        assertEq(address(adapter.extractor()), address(extractor));
        assertEq(adapter.owner(), owner);
    }

    function test_Constructor_SetsDefaultMessages() public view {
        assertEq(adapter.messageForTransferRestriction(0), "No restriction");
        assertEq(adapter.messageForTransferRestriction(1), "Transfer rejected by compliance policy");
        assertEq(adapter.messageForTransferRestriction(255), "Unknown compliance error occurred");
    }

    function test_Constructor_RevertsOnZeroPolicyEngine() public {
        vm.expectRevert(abi.encodeWithSelector(IACERuleEngineAdapter.ZeroAddressNotAllowed.selector, "policyEngine"));
        new ACERuleEngineAdapter(address(0), address(token), address(extractor), owner);
    }

    function test_Constructor_RevertsOnZeroTargetToken() public {
        vm.expectRevert(abi.encodeWithSelector(IACERuleEngineAdapter.ZeroAddressNotAllowed.selector, "targetToken"));
        new ACERuleEngineAdapter(address(policyEngine), address(0), address(extractor), owner);
    }

    function test_Constructor_RevertsOnZeroExtractor() public {
        vm.expectRevert(abi.encodeWithSelector(IACERuleEngineAdapter.ZeroAddressNotAllowed.selector, "extractor"));
        new ACERuleEngineAdapter(address(policyEngine), address(token), address(0), owner);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        // Note: OpenZeppelin's Ownable reverts with OwnableInvalidOwner before our check
        // This is expected behavior - the OZ check happens first in the constructor
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ACERuleEngineAdapter(address(policyEngine), address(token), address(extractor), address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATE TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ValidateTransfer_ReturnsTrue_WhenPolicyAllows() public view {
        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(isValid);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(isValid);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenSenderBlocked() public {
        policyEngine.setBlockedFrom(alice, true);

        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(isValid);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenRecipientBlocked() public {
        policyEngine.setBlockedTo(bob, true);

        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(isValid);
    }

    function test_ValidateTransfer_ReturnsFalse_WhenAmountExceedsMax() public {
        policyEngine.setMaxAmount(50 ether);

        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertFalse(isValid);
    }

    function test_ValidateTransfer_ReturnsTrue_WhenAmountWithinMax() public {
        policyEngine.setMaxAmount(200 ether);

        bool isValid = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        assertTrue(isValid);
    }

    function test_ValidateTransfer_HandlesZeroAmount() public view {
        bool isValid = adapter.validateTransfer(alice, bob, 0);
        assertTrue(isValid);
    }

    function test_ValidateTransfer_HandlesZeroAddresses() public view {
        // Zero from address
        bool isValid1 = adapter.validateTransfer(address(0), bob, TRANSFER_AMOUNT);
        assertTrue(isValid1);

        // Zero to address
        bool isValid2 = adapter.validateTransfer(alice, address(0), TRANSFER_AMOUNT);
        assertTrue(isValid2);
    }

    function test_ValidateTransfer_HandlesMaxUint256() public view {
        bool isValid = adapter.validateTransfer(alice, bob, type(uint256).max);
        assertTrue(isValid);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DETECT TRANSFER RESTRICTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DetectTransferRestriction_ReturnsZero_WhenAllowed() public view {
        uint8 code = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, 0);
    }

    function test_DetectTransferRestriction_ReturnsOne_WhenPolicyRejects() public {
        policyEngine.setRejectAll(true);

        uint8 code = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, 1);
    }

    function test_DetectTransferRestriction_Returns255_WhenUnknownError() public {
        policyEngine.setRejectAll(true);
        policyEngine.setRevertWithUnknownError(true);

        uint8 code = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(code, 255);
    }

    function test_DetectTransferRestriction_MatchesValidateTransfer() public {
        // Test allowed case
        bool valid1 = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint8 code1 = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(valid1, code1 == 0);

        // Test rejected case
        policyEngine.setRejectAll(true);
        bool valid2 = adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint8 code2 = adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        assertEq(valid2, code2 == 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MESSAGE FOR TRANSFER RESTRICTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MessageForTransferRestriction_ReturnsCorrectMessages() public view {
        assertEq(adapter.messageForTransferRestriction(0), "No restriction");
        assertEq(adapter.messageForTransferRestriction(1), "Transfer rejected by compliance policy");
        assertEq(adapter.messageForTransferRestriction(255), "Unknown compliance error occurred");
    }

    function test_MessageForTransferRestriction_ReturnsUnknown_ForUnconfiguredCode() public view {
        assertEq(adapter.messageForTransferRestriction(42), "Unknown restriction code");
        assertEq(adapter.messageForTransferRestriction(100), "Unknown restriction code");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetRestrictionMessage_UpdatesMessage() public {
        vm.prank(owner);
        adapter.setRestrictionMessage(42, "Custom error message");

        assertEq(adapter.messageForTransferRestriction(42), "Custom error message");
    }

    function test_SetRestrictionMessage_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IACERuleEngineAdapter.RestrictionMessageUpdated(42, "Custom error message");

        vm.prank(owner);
        adapter.setRestrictionMessage(42, "Custom error message");
    }

    function test_SetRestrictionMessage_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setRestrictionMessage(42, "Custom error message");
    }

    function test_SetRestrictionMessage_CanOverrideDefaults() public {
        vm.prank(owner);
        adapter.setRestrictionMessage(1, "New rejection message");

        assertEq(adapter.messageForTransferRestriction(1), "New rejection message");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNERSHIP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Ownership_TransferRequiresTwoSteps() public {
        // Initiate transfer
        vm.prank(owner);
        adapter.transferOwnership(alice);

        // Owner should still be original owner
        assertEq(adapter.owner(), owner);

        // Alice accepts ownership
        vm.prank(alice);
        adapter.acceptOwnership();

        // Now Alice is the owner
        assertEq(adapter.owner(), alice);
    }

    function test_Ownership_PendingOwnerCanAccept() public {
        vm.prank(owner);
        adapter.transferOwnership(alice);

        assertEq(adapter.pendingOwner(), alice);

        vm.prank(alice);
        adapter.acceptOwnership();

        assertEq(adapter.owner(), alice);
        assertEq(adapter.pendingOwner(), address(0));
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

    function test_Integration_TransferFromSucceeds_WhenPolicyAllows() public {
        // Alice approves Charlie to transfer
        vm.prank(alice);
        token.approve(charlie, TRANSFER_AMOUNT);

        // Charlie transfers from Alice to Bob
        vm.prank(charlie);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    function test_Integration_TransferFromReverts_WhenSenderBlocked() public {
        policyEngine.setBlockedFrom(alice, true);

        vm.prank(alice);
        token.approve(charlie, TRANSFER_AMOUNT);

        vm.prank(charlie);
        vm.expectRevert();
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    function test_Integration_CanSwitchRuleEngine() public {
        // Deploy a new adapter with different policy engine
        MockPolicyEngine newPolicyEngine = new MockPolicyEngine();
        newPolicyEngine.setRejectAll(true); // New engine rejects all

        ACERuleEngineAdapter newAdapter = new ACERuleEngineAdapter(
            address(newPolicyEngine),
            address(token),
            address(extractor),
            owner
        );

        // Switch to new adapter
        vm.prank(owner);
        token.setRuleEngine(address(newAdapter));

        // Transfer should now fail
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);

        // Switch back to original adapter
        vm.prank(owner);
        token.setRuleEngine(address(adapter));

        // Transfer should succeed again
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_Integration_CanTransfer_WithNoRuleEngine() public {
        // Remove rule engine
        vm.prank(owner);
        token.setRuleEngine(address(0));

        // Even with policy engine rejecting, transfer should work (no rule engine)
        policyEngine.setRejectAll(true);

        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_ValidateTransfer_Allowed() public view {
        uint256 gasBefore = gasleft();
        adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for validateTransfer (allowed):", gasUsed);
    }

    function test_Gas_ValidateTransfer_Rejected() public {
        policyEngine.setRejectAll(true);

        uint256 gasBefore = gasleft();
        adapter.validateTransfer(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for validateTransfer (rejected):", gasUsed);
    }

    function test_Gas_DetectTransferRestriction() public view {
        uint256 gasBefore = gasleft();
        adapter.detectTransferRestriction(alice, bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for detectTransferRestriction:", gasUsed);
    }

    function test_Gas_FullTransfer_WithAdapter() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for full transfer with adapter:", gasUsed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ValidateTransfer_AnyAmount(uint256 amount) public view {
        // Should not revert regardless of amount
        adapter.validateTransfer(alice, bob, amount);
    }

    function testFuzz_ValidateTransfer_AnyAddresses(address from, address to, uint256 amount) public view {
        // Should not revert regardless of addresses
        adapter.validateTransfer(from, to, amount);
    }

    function testFuzz_DetectTransferRestriction_ReturnsValidCode(
        address from,
        address to,
        uint256 amount
    ) public view {
        uint8 code = adapter.detectTransferRestriction(from, to, amount);
        // Code should be 0, 1, or 255
        assertTrue(code == 0 || code == 1 || code == 255);
    }

    function testFuzz_MessageForTransferRestriction_NeverReverts(uint8 code) public view {
        // Should never revert, always return a string
        string memory message = adapter.messageForTransferRestriction(code);
        assertTrue(bytes(message).length > 0);
    }
}
