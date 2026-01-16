// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ACERule} from "../../src/rule/ACERule.sol";
import {CMTATTransferExtractor} from "../../src/extractors/CMTATTransferExtractor.sol";
import {MockPolicyEngine} from "../mocks/MockPolicyEngine.sol";
import {MockCMTATToken} from "../mocks/MockCMTATToken.sol";

/**
 * @title MultiRule_CompositionTest
 * @notice Integration tests for composing ACERule with other rules in CMTAT RuleEngine.
 * @dev Tests demonstrate:
 *      - ACERule as ONE rule among many in a RuleEngine
 *      - Rule composition patterns (ALL, ANY, PRIORITY)
 *      - Complex compliance scenarios with multiple rules
 *      - Real-world multi-layered validation
 * 
 * @dev Note: This demonstrates the pattern with mock rules.
 *      In production, you would use actual CMTAT RuleEngine v1.0.2.1
 *      which supports rule composition.
 */

// ═══════════════════════════════════════════════════════════════════════════
// MOCK RULES FOR COMPOSITION TESTING
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @notice Mock rule that checks minimum holding period
 */
contract HoldingPeriodRule {
        mapping(address => mapping(address => uint256)) public lastReceived;
        uint256 public minimumHoldingPeriod = 1 days;

        function validateTransfer(
            address from,
            address /*to*/,
            uint256 /*amount*/
        ) external view returns (bool) {
            if (lastReceived[address(this)][from] == 0) return true;
            return block.timestamp >= lastReceived[address(this)][from] + minimumHoldingPeriod;
        }

        function recordTransfer(address to) external {
            lastReceived[address(this)][to] = block.timestamp;
        }

        function setMinimumHoldingPeriod(uint256 _period) external {
            minimumHoldingPeriod = _period;
        }
}

/**
 * @notice Mock rule that enforces maximum holding per address
 */
contract MaxHoldingRule {
        mapping(address => uint256) public maxHolding;
        uint256 public defaultMaxHolding = 10000 ether;

        function validateTransfer(
            address /*from*/,
            address to,
            uint256 amount
        ) external view returns (bool) {
            uint256 limit = maxHolding[to] > 0 ? maxHolding[to] : defaultMaxHolding;
            // In real scenario, would check token.balanceOf(to) + amount <= limit
            return amount <= limit;
        }

        function setMaxHolding(address account, uint256 max) external {
            maxHolding[account] = max;
        }

        function setDefaultMaxHolding(uint256 max) external {
            defaultMaxHolding = max;
        }
}

/**
 * @notice Mock rule that enforces investor count limits
 */
contract InvestorCountRule {
        mapping(address => bool) public isInvestor;
        uint256 public investorCount;
        uint256 public maxInvestors = 100;

        function validateTransfer(
            address /*from*/,
            address to,
            uint256 /*amount*/
        ) external view returns (bool) {
            // If recipient is already an investor, allow
            if (isInvestor[to]) return true;
            // If not, check if we have room for new investor
            return investorCount < maxInvestors;
        }

        function addInvestor(address investor) external {
            if (!isInvestor[investor]) {
                isInvestor[investor] = true;
                investorCount++;
            }
        }

        function setMaxInvestors(uint256 max) external {
            maxInvestors = max;
        }
}

/**
 * @notice Composite RuleEngine that validates against multiple rules
 */
contract CompositeRuleEngine {
        address[] public rules;
        bool public requireAllRules; // true = ALL must pass, false = ANY can pass

        function addRule(address rule) external {
            rules.push(rule);
        }

        function setRequireAllRules(bool _requireAll) external {
            requireAllRules = _requireAll;
        }

        function validateTransfer(
            address from,
            address to,
            uint256 amount
        ) external view returns (bool) {
            if (rules.length == 0) return true;

            if (requireAllRules) {
                // ALL rules must pass
                for (uint256 i = 0; i < rules.length; i++) {
                    (bool success, bytes memory result) = rules[i].staticcall(
                        abi.encodeWithSignature("validateTransfer(address,address,uint256)", from, to, amount)
                    );
                    if (!success || !abi.decode(result, (bool))) {
                        return false;
                    }
                }
                return true;
            } else {
                // ANY rule can pass
                for (uint256 i = 0; i < rules.length; i++) {
                    (bool success, bytes memory result) = rules[i].staticcall(
                        abi.encodeWithSignature("validateTransfer(address,address,uint256)", from, to, amount)
                    );
                    if (success && abi.decode(result, (bool))) {
                        return true;
                    }
                }
                return false;
            }
        }
}

contract MultiRule_CompositionTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // TEST FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════

    ACERule public aceRule;
    HoldingPeriodRule public holdingRule;
    MaxHoldingRule public maxHoldingRule;
    InvestorCountRule public investorCountRule;
    CompositeRuleEngine public compositeEngine;

    CMTATTransferExtractor public extractor;
    MockPolicyEngine public policyEngine;
    MockCMTATToken public token;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public dave = address(0x5);

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant TRANSFER_AMOUNT = 100 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy policy engine and extractor
        policyEngine = new MockPolicyEngine();
        extractor = new CMTATTransferExtractor();

        // Deploy ACERule
        aceRule = new ACERule(
            address(policyEngine),
            address(extractor)
        );

        // Deploy other rules
        holdingRule = new HoldingPeriodRule();
        maxHoldingRule = new MaxHoldingRule();
        investorCountRule = new InvestorCountRule();

        // Deploy composite rule engine
        compositeEngine = new CompositeRuleEngine();

        // Deploy token
        token = new MockCMTATToken("Composite Token", "COMP", owner);

        // Set composite engine as token's RuleEngine
        vm.prank(owner);
        token.setRuleEngine(address(compositeEngine));

        // Mint initial balances
        vm.startPrank(owner);
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
        vm.stopPrank();

        // Register initial investors
        investorCountRule.addInvestor(alice);
        investorCountRule.addInvestor(bob);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC COMPOSITION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Composition_ACERule_Only() public {
        // Add only ACERule to composite
        compositeEngine.addRule(address(aceRule));
        compositeEngine.setRequireAllRules(true);

        // Transfer should work
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    function test_Composition_ACERule_Plus_HoldingPeriod() public {
        // Add ACERule and HoldingPeriodRule
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.setRequireAllRules(true); // ALL must pass

        // Set very short holding period for testing
        holdingRule.setMinimumHoldingPeriod(0);

        // First transfer should work
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    function test_Composition_ACERule_Plus_MaxHolding() public {
        // Add ACERule and MaxHoldingRule
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        // Set high max holding
        maxHoldingRule.setDefaultMaxHolding(1000000 ether);

        // Transfer should work
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    function test_Composition_All_Rules() public {
        // Add ALL rules
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.addRule(address(investorCountRule));
        compositeEngine.setRequireAllRules(true);

        // Configure for success
        holdingRule.setMinimumHoldingPeriod(0);
        maxHoldingRule.setDefaultMaxHolding(1000000 ether);

        // Transfer to existing investor should work
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertEq(token.balanceOf(bob), INITIAL_BALANCE + TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RULE REJECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Composition_ACERule_Rejects() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.setRequireAllRules(true);

        // ACERule rejects
        policyEngine.setRejectAll(true);

        // Transfer should fail
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_Composition_MaxHoldingRule_Rejects() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        // MaxHolding rejects large transfers
        maxHoldingRule.setDefaultMaxHolding(50 ether);

        // Small transfer works
        vm.prank(alice);
        token.transfer(bob, 50 ether);

        // Large transfer fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100 ether);
    }

    function test_Composition_InvestorCount_Rejects() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(investorCountRule));
        compositeEngine.setRequireAllRules(true);

        // Set max investors to 2 (alice and bob already registered)
        investorCountRule.setMaxInvestors(2);

        // Transfer to existing investor works
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        // Transfer to new investor fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(charlie, TRANSFER_AMOUNT);
    }

    function test_Composition_AnyRule_OneFails_OtherPasses() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(false); // ANY can pass

        // MaxHolding rejects
        maxHoldingRule.setDefaultMaxHolding(50 ether);

        // But ACERule allows, so transfer works (ANY mode)
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REAL-WORLD COMPLIANCE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RealWorld_RegD_Compliance() public {
        // Scenario: Regulation D private placement
        // - ACERule: Accredited investor check via ACE policies
        // - InvestorCountRule: Max 35 non-accredited or 100 accredited
        // - MaxHoldingRule: Concentration limits

        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(investorCountRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        // Configure rules
        investorCountRule.setMaxInvestors(100);
        maxHoldingRule.setDefaultMaxHolding(100000 ether);

        // Transfers work within limits (within INITIAL_BALANCE of 1000 ether)
        vm.prank(alice);
        token.transfer(bob, 500 ether);

        assertEq(token.balanceOf(bob), INITIAL_BALANCE + 500 ether);
    }

    function test_RealWorld_RegS_Compliance() public {
        // Scenario: Regulation S offshore offering
        // - ACERule: Geographic restrictions via ACE policies
        // - HoldingPeriodRule: Required offshore holding period
        // - MaxHoldingRule: Position limits

        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        // Configure offshore holding period (e.g., 1 year)
        holdingRule.setMinimumHoldingPeriod(0); // Shortened for test

        // Initial offshore purchase allowed
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        // Record the transfer
        holdingRule.recordTransfer(bob);

        // Further transfers work
        vm.prank(alice);
        token.transfer(charlie, TRANSFER_AMOUNT);
    }

    function test_RealWorld_MiFID_II_Compliance() public {
        // Scenario: MiFID II European compliance
        // - ACERule: Suitability assessments via ACE
        // - MaxHoldingRule: Product intervention limits (per transfer)
        // - InvestorCountRule: Professional vs retail limits

        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.addRule(address(investorCountRule));
        compositeEngine.setRequireAllRules(true);

        // Configure for retail investors (per-transfer limit)
        maxHoldingRule.setMaxHolding(bob, 600 ether); // Per-transfer limit

        // Transfer within retail limit works
        vm.prank(alice);
        token.transfer(bob, 500 ether);

        // Transfer exceeding per-transfer limit fails
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 700 ether); // Exceeds 600 per-transfer limit
    }

    function test_RealWorld_AML_MultiLayer() public {
        // Scenario: Multi-layer AML compliance
        // - ACERule: OFAC/sanctions screening
        // - HoldingPeriodRule: Rapid trading detection
        // - MaxHoldingRule: Structuring detection
        // - InvestorCountRule: Smurfing detection

        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.addRule(address(investorCountRule));
        compositeEngine.setRequireAllRules(true);

        // Configure AML rules
        holdingRule.setMinimumHoldingPeriod(0); // Detect rapid trading
        maxHoldingRule.setDefaultMaxHolding(50000 ether); // Detect large positions
        investorCountRule.setMaxInvestors(100); // Detect smurfing

        // Legitimate transfer works (within INITIAL_BALANCE)
        vm.prank(alice);
        token.transfer(bob, 500 ether);

        // Suspicious patterns would be blocked by respective rules
    }

    function test_RealWorld_KYC_Tiered() public {
        // Scenario: Tiered KYC levels
        // - ACERule: Base KYC check via ACE
        // - MaxHoldingRule: Higher limits for enhanced KYC
        // - InvestorCountRule: Institutional vs retail quotas

        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        // Basic KYC: 1000 limit
        maxHoldingRule.setMaxHolding(charlie, 1000 ether);

        // Enhanced KYC: 50000 limit
        maxHoldingRule.setMaxHolding(bob, 50000 ether);

        vm.prank(owner);
        token.mint(alice, 100000 ether);

        // Basic KYC user limited
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(charlie, 2000 ether);

        // Enhanced KYC user can receive more
        vm.prank(alice);
        token.transfer(bob, 20000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RULE PRIORITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Priority_ACERule_First() public {
        // When ACERule is first, it gets checked first
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        // ACERule rejects early, other rules not even checked
        policyEngine.setRejectAll(true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_Priority_ACERule_Last() public {
        // When ACERule is last, other rules checked first
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.addRule(address(aceRule));
        compositeEngine.setRequireAllRules(true);

        // Even if others pass, ACERule can still reject
        policyEngine.setRejectAll(true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DYNAMIC RULE MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Dynamic_AddRules_Runtime() public {
        // Start with no rules
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        // Add ACERule
        compositeEngine.addRule(address(aceRule));
        compositeEngine.setRequireAllRules(true);

        // Still works
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        // Add restrictive rule
        policyEngine.setRejectAll(true);

        // Now blocked
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_OneRule() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.setRequireAllRules(true);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas with 1 rule (ACERule):", gasUsed);
    }

    function test_Gas_TwoRules() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.setRequireAllRules(true);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas with 2 rules:", gasUsed);
    }

    function test_Gas_FourRules() public {
        compositeEngine.addRule(address(aceRule));
        compositeEngine.addRule(address(holdingRule));
        compositeEngine.addRule(address(maxHoldingRule));
        compositeEngine.addRule(address(investorCountRule));
        compositeEngine.setRequireAllRules(true);

        holdingRule.setMinimumHoldingPeriod(0);
        maxHoldingRule.setDefaultMaxHolding(1000000 ether);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas with 4 rules:", gasUsed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DOCUMENTATION EXAMPLES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Documentation_MultiRuleExample() public {
        // Example from documentation: Multi-rule composition

        // 1. Create composite engine
        CompositeRuleEngine engine = new CompositeRuleEngine();

        // 2. Add multiple rules
        engine.addRule(address(aceRule));        // ACE compliance
        engine.addRule(address(maxHoldingRule)); // Position limits
        engine.setRequireAllRules(true);         // ALL must pass

        // 3. Set as token's rule engine
        MockCMTATToken exampleToken = new MockCMTATToken("Example", "EX", owner);
        vm.prank(owner);
        exampleToken.setRuleEngine(address(engine));

        // 4. Configure rules
        maxHoldingRule.setDefaultMaxHolding(50000 ether);

        // 5. Mint and transfer
        vm.prank(owner);
        exampleToken.mint(alice, 100000 ether);

        vm.prank(alice);
        exampleToken.transfer(bob, 10000 ether);

        // Success! Both rules validated
        assertEq(exampleToken.balanceOf(bob), 10000 ether);
    }
}
