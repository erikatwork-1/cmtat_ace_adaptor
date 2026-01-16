// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERuleEngineAdapter} from "../../src/adapter/ACERuleEngineAdapter.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";

/**
 * @title PolicyIntegrationTest
 * @notice Tests demonstrating various ACE policy scenarios with the adapter.
 * @dev Simulates the behavior of different ACE policies:
 *      - AllowPolicy (whitelist)
 *      - RejectPolicy
 *      - MaxPolicy (amount limits)
 *      - PausePolicy
 *      - Policy composition (multiple policies)
 */
contract PolicyIntegrationTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERuleEngineAdapter public adapter;
    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;
    MockCMTATToken public token;

    address public admin = address(0x1);
    address public whitelisted1 = address(0x2);
    address public whitelisted2 = address(0x3);
    address public nonWhitelisted = address(0x4);

    uint256 public constant USER_BALANCE = 10_000 ether;

    function setUp() public {
        token = new MockCMTATToken("Policy Test Token", "PTT", admin);
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
        token.mint(whitelisted1, USER_BALANCE);
        token.mint(whitelisted2, USER_BALANCE);
        token.mint(nonWhitelisted, USER_BALANCE);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ALLOW POLICY TESTS (Whitelist)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Simulates AllowPolicy behavior by blocking non-whitelisted addresses.
     */
    function test_AllowPolicy_WhitelistedCanTransfer() public {
        // Only whitelisted1 and whitelisted2 can send
        // (In real ACE, this would be an AllowPolicy with a credential check)
        policyEngine.setBlockedFrom(nonWhitelisted, true);

        // Whitelisted users can transfer
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);

        vm.prank(whitelisted2);
        token.transfer(whitelisted1, 50 ether);
    }

    function test_AllowPolicy_NonWhitelistedCannotTransfer() public {
        policyEngine.setBlockedFrom(nonWhitelisted, true);

        vm.prank(nonWhitelisted);
        vm.expectRevert();
        token.transfer(whitelisted1, 100 ether);
    }

    function test_AllowPolicy_RecipientWhitelist() public {
        // Only allow transfers to whitelisted recipients
        policyEngine.setBlockedTo(nonWhitelisted, true);

        // Transfer to whitelisted succeeds
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);

        // Transfer to non-whitelisted fails
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(nonWhitelisted, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REJECT POLICY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RejectPolicy_BlocksAllTransfers() public {
        policyEngine.setRejectAll(true);

        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 100 ether);
    }

    function test_RejectPolicy_CanBeDisabled() public {
        policyEngine.setRejectAll(true);

        // Transfers blocked
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 100 ether);

        // Disable rejection
        policyEngine.setRejectAll(false);

        // Transfers work
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MAX POLICY TESTS (Amount Limits)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MaxPolicy_EnforcesLimit() public {
        policyEngine.setMaxAmount(1000 ether);

        // Under limit succeeds
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 500 ether);

        // At limit succeeds
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 500 ether);

        // Over limit fails
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 1001 ether);
    }

    function test_MaxPolicy_ZeroLimitDisablesRestriction() public {
        // setMaxAmount(0) means no limit
        policyEngine.setMaxAmount(0);

        vm.prank(whitelisted1);
        token.transfer(whitelisted2, USER_BALANCE);
    }

    function test_MaxPolicy_CanUpdateLimit() public {
        policyEngine.setMaxAmount(100 ether);

        // 150 ether transfer fails
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 150 ether);

        // Increase limit
        policyEngine.setMaxAmount(200 ether);

        // Now 150 ether transfer succeeds
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 150 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PAUSE POLICY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PausePolicy_BlocksTransfers() public {
        // Simulate pause by rejecting all
        policyEngine.setRejectAll(true);

        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 100 ether);
    }

    function test_PausePolicy_UnpauseAllowsTransfers() public {
        // Pause
        policyEngine.setRejectAll(true);

        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 100 ether);

        // Unpause
        policyEngine.setRejectAll(false);

        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POLICY COMPOSITION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Tests combining multiple policy conditions (AND logic).
     * @dev In real ACE, multiple policies return Continue for AND behavior.
     */
    function test_PolicyComposition_ANDLogic() public {
        // Both conditions must be met:
        // 1. Sender must be whitelisted (not blocked)
        // 2. Amount must be under limit
        policyEngine.setBlockedFrom(nonWhitelisted, true);
        policyEngine.setMaxAmount(1000 ether);

        // Whitelisted + under limit = success
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 500 ether);

        // Non-whitelisted + under limit = fail (violates condition 1)
        vm.prank(nonWhitelisted);
        vm.expectRevert();
        token.transfer(whitelisted2, 500 ether);

        // Whitelisted + over limit = fail (violates condition 2)
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 1500 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POLICY UPDATE WITHOUT ADAPTER CHANGE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Demonstrates policy updates without changing the adapter.
     * @dev This is a key benefit of using ACE - policies can be updated
     *      via PolicyEngine without touching the token contract.
     */
    function test_PolicyUpdate_WithoutAdapterChange() public {
        // Initial state: no restrictions
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);

        // Add max limit policy
        policyEngine.setMaxAmount(50 ether);

        // Now large transfers fail
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 100 ether);

        // Small transfers still work
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 40 ether);

        // Remove limit
        policyEngine.setMaxAmount(0);

        // Large transfers work again
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);

        // Token's rule engine address never changed!
        assertEq(address(token.ruleEngine()), address(adapter));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CUSTOM REJECTION MESSAGE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CustomRejectionMessage_InPolicy() public {
        policyEngine.setRejectAll(true);
        policyEngine.setRejectionMessage("Investor not accredited");

        // Check that transfer would be rejected
        uint8 code = adapter.detectTransferRestriction(whitelisted1, whitelisted2, 100 ether);
        assertEq(code, 1); // Policy rejected

        // The adapter's message is used (not the policy's internal message)
        string memory message = adapter.messageForTransferRestriction(code);
        assertEq(message, "Transfer rejected by compliance policy");

        // Admin can set custom message to match policy
        vm.prank(admin);
        adapter.setRestrictionMessage(1, "Investor not accredited");

        message = adapter.messageForTransferRestriction(code);
        assertEq(message, "Investor not accredited");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REAL-WORLD SCENARIO TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Simulates a security token issuance scenario.
     */
    function test_Scenario_SecurityTokenIssuance() public {
        // Set up compliance rules:
        // 1. Only accredited investors (whitelisted) can receive
        // 2. Maximum transfer of 10,000 tokens per transaction
        policyEngine.setBlockedTo(nonWhitelisted, true);
        policyEngine.setMaxAmount(10_000 ether);

        // Issuer (admin) distributes to investors
        vm.startPrank(admin);
        token.mint(admin, 100_000 ether);
        vm.stopPrank();

        // Admin can transfer to whitelisted investors
        vm.prank(admin);
        token.transfer(whitelisted1, 5_000 ether);

        vm.prank(admin);
        token.transfer(whitelisted2, 5_000 ether);

        // Admin cannot transfer more than max per transaction
        vm.prank(admin);
        vm.expectRevert();
        token.transfer(whitelisted1, 15_000 ether);

        // Admin cannot transfer to non-accredited
        vm.prank(admin);
        vm.expectRevert();
        token.transfer(nonWhitelisted, 1_000 ether);
    }

    /**
     * @notice Simulates adding a new investor to whitelist.
     */
    function test_Scenario_AddNewInvestor() public {
        address newInvestor = address(0x999);

        // Initially, new investor is blocked
        policyEngine.setBlockedTo(newInvestor, true);

        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(newInvestor, 100 ether);

        // KYC/AML completed, add to whitelist
        policyEngine.setBlockedTo(newInvestor, false);

        // Now transfer succeeds
        vm.prank(whitelisted1);
        token.transfer(newInvestor, 100 ether);

        assertEq(token.balanceOf(newInvestor), 100 ether);
    }

    /**
     * @notice Simulates an emergency pause scenario.
     */
    function test_Scenario_EmergencyPause() public {
        // Normal operations
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);

        // Security incident detected - pause all transfers
        policyEngine.setRejectAll(true);

        // No one can transfer
        vm.prank(whitelisted1);
        vm.expectRevert();
        token.transfer(whitelisted2, 100 ether);

        vm.prank(whitelisted2);
        vm.expectRevert();
        token.transfer(whitelisted1, 100 ether);

        // Issue resolved - unpause
        policyEngine.setRejectAll(false);

        // Normal operations resume
        vm.prank(whitelisted1);
        token.transfer(whitelisted2, 100 ether);
    }
}
