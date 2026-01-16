# Option 2A: ACERule (CMTAT v2.3.0) - Token-Agnostic Rule Approach

## Overview

**Option 2A** uses `ACERule` as **one rule within RuleEngine**, enabling non-destructive integration with existing compliance rules.

### When to Use

✅ **Best for**:
- Existing CMTAT v2.3.0 tokens with compliance rules
- Gradual migration to ACE
- Multi-rule compliance frameworks (ACE + Whitelist + Custom)
- Risk-averse production deployments

✅ **Key Innovation**: **Token-Agnostic Design**
- ONE ACERule deployment works with MULTIPLE tokens
- Policies registered against **RuleEngine address**, NOT token
- Lower deployment costs
- Simplified policy management

### Architecture

```
CMTAT Token v2.3.0
    ↓
RuleEngine v1.0.2.1
    ├── ACERule → ACE PolicyEngine [NEW!]
    ├── WhitelistRule [PRESERVED]
    └── Other Rules [PRESERVED]
```

---

## Key Differences from Option 1A (Adapter)

| Aspect | Option 1A (Adapter) | Option 2A (Rule) |
|--------|---------------------|------------------|
| **Integration** | Replaces RuleEngine | Adds to RuleEngine |
| **Existing Rules** | Cannot preserve | ✅ Preserves all |
| **Deployment** | Token-specific | ✅ Token-agnostic |
| **Constructor** | Needs `targetToken` | ✅ NO `targetToken` |
| **Policy Target** | Token address | ✅ RuleEngine address |
| **Return Type** | `uint8` codes | `bool` true/false |
| **Reusability** | One per token | ✅ One for all tokens |

---

## Step-by-Step Integration

### Step 1: Deploy CMTATTransferExtractor

Same as Option 1A - see [Option 1A Step 1](option-1a-adapter-v2.md#step-1-deploy-cmtattransferextractor)

### Step 2: Deploy ACERule (Token-Agnostic!)

**Key Difference**: NO `targetToken` parameter!

```solidity
// script/deploy/rule/DeployACERule_v2.s.sol
// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {ACERule} from "src/rule/ACERule.sol";

contract DeployACERule_v2 is Script {
    function run() external returns (address) {
        address policyEngine = vm.envAddress("POLICY_ENGINE_ADDRESS");
        address extractor = vm.envAddress("EXTRACTOR_ADDRESS");
        
        vm.startBroadcast();
        
        ACERule aceRule = new ACERule(
            policyEngine,
            extractor
            // NO targetToken! ← Key difference from Adapter
        );
        
        console.log("ACERule deployed:", address(aceRule));
        console.log("  PolicyEngine:", policyEngine);
        console.log("  Extractor:", extractor);
        console.log("  ✓ Token-agnostic design - works with ANY token!");
        
        vm.stopBroadcast();
        
        return address(aceRule);
    }
}
```

**Deploy**:
```bash
forge script script/deploy/rule/DeployACERule_v2.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

export ACE_RULE_ADDRESS=0x...
```

### Step 3: Configure ACE PolicyEngine

**CRITICAL DIFFERENCE**: Policies target **RuleEngine address**, NOT token!

```solidity
// script/integration/rule/ConfigurePolicyEngine.s.sol
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

contract ConfigurePolicyEngine is Script {
    bytes4 constant VALIDATE_TRANSFER_SELECTOR = 
        bytes4(keccak256("validateTransfer(address,address,uint256)"));
    
    function run() external {
        address policyEngine = vm.envAddress("POLICY_ENGINE_ADDRESS");
        address extractor = vm.envAddress("EXTRACTOR_ADDRESS");
        address ruleEngine = vm.envAddress("RULE_ENGINE_ADDRESS"); // ← Not token!
        address allowPolicy = vm.envAddress("ALLOW_POLICY_ADDRESS");
        
        vm.startBroadcast();
        
        IPolicyEngine pe = IPolicyEngine(policyEngine);
        
        // Set extractor
        pe.setExtractor(VALIDATE_TRANSFER_SELECTOR, extractor);
        
        // Add policies targeting RULEENGINE (not token!)
        pe.addPolicy(
            ruleEngine,            // ← Target is RULEENGINE
            VALIDATE_TRANSFER_SELECTOR,
            allowPolicy,
            new bytes32[](0)
        );
        
        console.log("✓ Policies registered for RuleEngine:", ruleEngine);
        console.log("  (NOT for individual tokens)");
        
        vm.stopBroadcast();
    }
}
```

**Run**:
```bash
export RULE_ENGINE_ADDRESS=0x...  # Your existing RuleEngine!

forge script script/integration/rule/ConfigurePolicyEngine.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 4: Add ACERule to RuleEngine (Non-Destructive!)

**Key Feature**: Preserves existing rules!

```solidity
// script/integration/rule/AddRuleToEngine.s.sol
pragma solidity 0.8.26;

import "forge-std/Script.sol";

interface IRuleEngine {
    function addRule(address rule) external;
    function rulesCount() external view returns (uint256);
    function ruleAtIndex(uint256 index) external view returns (address);
}

contract AddRuleToEngine is Script {
    function run() external {
        address ruleEngine = vm.envAddress("RULE_ENGINE_ADDRESS");
        address aceRule = vm.envAddress("ACE_RULE_ADDRESS");
        
        IRuleEngine re = IRuleEngine(ruleEngine);
        
        console.log("Current rules in RuleEngine:");
        uint256 count = re.rulesCount();
        for (uint256 i = 0; i < count; i++) {
            console.log("  Rule", i, ":", re.ruleAtIndex(i));
        }
        
        vm.startBroadcast();
        
        // Add ACERule (non-destructive!)
        re.addRule(aceRule);
        
        vm.stopBroadcast();
        
        console.log("\n✓ ACERule added!");
        console.log("New rule count:", re.rulesCount());
        console.log("✓ Existing rules preserved!");
    }
}
```

**Run**:
```bash
forge script script/integration/rule/AddRuleToEngine.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 5: Verify Multi-Rule Validation

Test that ALL rules work together.

```solidity
// script/integration/rule/VerifyMultiRule.s.sol
pragma solidity 0.8.26;

import "forge-std/Script.sol";

interface ICMTAT {
    function validateTransfer(address from, address to, uint256 amount) 
        external view returns (bool);
}

interface IRuleEngine {
    function rulesCount() external view returns (uint256);
    function ruleAtIndex(uint256 index) external view returns (address);
}

contract VerifyMultiRule is Script {
    function run() external view {
        address cmtatToken = vm.envAddress("CMTAT_TOKEN_ADDRESS");
        address ruleEngine = vm.envAddress("RULE_ENGINE_ADDRESS");
        address testRecipient = vm.envAddress("TEST_RECIPIENT");
        
        IRuleEngine re = IRuleEngine(ruleEngine);
        ICMTAT token = ICMTAT(cmtatToken);
        
        console.log("Verifying multi-rule validation...");
        console.log("\nActive rules:");
        uint256 count = re.rulesCount();
        for (uint256 i = 0; i < count; i++) {
            console.log("  -", re.ruleAtIndex(i));
        }
        
        console.log("\nTesting transfer validation...");
        bool allowed = token.validateTransfer(
            msg.sender,
            testRecipient,
            1 ether
        );
        
        if (allowed) {
            console.log("✓ Transfer ALLOWED");
            console.log("  (All rules passed - AND logic)");
        } else {
            console.log("✗ Transfer REJECTED");
            console.log("  (At least one rule rejected)");
        }
    }
}
```

---

## Token-Agnostic Advantage

### One ACERule, Multiple Tokens

```solidity
// Deploy ACERule once
ACERule aceRule = new ACERule(policyEngine, extractor);

// Use with Token 1
RuleEngine ruleEngine1 = RuleEngine(token1.ruleEngine());
ruleEngine1.addRule(address(aceRule));

// Use with Token 2 (same ACERule!)
RuleEngine ruleEngine2 = RuleEngine(token2.ruleEngine());
ruleEngine2.addRule(address(aceRule));

// Use with Token 3 (same ACERule!)
RuleEngine ruleEngine3 = RuleEngine(token3.ruleEngine());
ruleEngine3.addRule(address(aceRule));

// Configure policies ONCE for the shared RuleEngine(s)
policyEngine.addPolicy(ruleEngineAddress, selector, policy, params);
```

---

## Migration Scenarios

### Scenario 1: Add ACE to Existing Token (Non-Destructive)

**Current State**:
```
CMTAT Token → RuleEngine → WhitelistRule
                         → ConditionalTransferRule
```

**Target State**:
```
CMTAT Token → RuleEngine → WhitelistRule [PRESERVED]
                         → ConditionalTransferRule [PRESERVED]
                         → ACERule [NEW!]
```

**Steps**:
1. Deploy ACERule
2. Configure PolicyEngine (target RuleEngine)
3. Call `ruleEngine.addRule(aceRule)`
4. Test: ALL rules must pass (AND logic)

### Scenario 2: Multiple Tokens, Shared ACERule

**Efficiency**: Deploy ACERule once, use with all tokens.

```bash
# Deploy ACERule (once)
forge script script/deploy/rule/DeployACERule_v2.s.sol --broadcast

# Add to Token 1's RuleEngine
export RULE_ENGINE_ADDRESS=$TOKEN1_RULE_ENGINE
forge script script/integration/rule/AddRuleToEngine.s.sol --broadcast

# Add to Token 2's RuleEngine (same ACERule!)
export RULE_ENGINE_ADDRESS=$TOKEN2_RULE_ENGINE
forge script script/integration/rule/AddRuleToEngine.s.sol --broadcast

# Add to Token 3's RuleEngine (same ACERule!)
export RULE_ENGINE_ADDRESS=$TOKEN3_RULE_ENGINE
forge script script/integration/rule/AddRuleToEngine.s.sol --broadcast
```

---

## Multi-Rule Logic

### AND Logic (All Rules Must Pass)

```
Transfer Request
    ↓
RuleEngine validates
    ├─ Rule 1: WhitelistRule.validateTransfer()
    │  Returns: true (sender/recipient whitelisted)
    │
    ├─ Rule 2: ACERule.validateTransfer()
    │  → Calls ACE PolicyEngine
    │  Returns: true (ACE policies allow)
    │
    └─ Rule 3: ConditionalTransferRule.validateTransfer()
       Returns: true (conditions met)

Result: ALL returned true → Transfer ALLOWED

If ANY rule returns false → Transfer REJECTED
```

---

## Policy Examples

Same policies as Option 1A, but targeting **RuleEngine address**:

```solidity
// AllowPolicy targeting RuleEngine
policyEngine.addPolicy(
    ruleEngineAddress,     // ← RuleEngine, not token!
    transferSelector,
    allowPolicyAddress,
    abi.encode(allowedAddresses)
);

// MaxPolicy targeting RuleEngine
policyEngine.addPolicy(
    ruleEngineAddress,     // ← RuleEngine, not token!
    transferSelector,
    maxPolicyAddress,
    abi.encode(maxAmount)
);
```

---

## Testing Checklist

Additional checks for multi-rule setup:

- [ ] Verify all existing rules still work
- [ ] Test ACERule independently
- [ ] Test combined validation (all rules)
- [ ] Verify AND logic (any rejection = transfer rejected)
- [ ] Test rule order doesn't affect outcome
- [ ] Verify gas costs with multiple rules
- [ ] Test rollback (remove ACERule from RuleEngine)

---

## Troubleshooting

### Issue: ACERule Not Being Called

**Check**:
```bash
# Verify ACERule is in RuleEngine
cast call $RULE_ENGINE "rulesCount()(uint256)"
cast call $RULE_ENGINE "ruleAtIndex(uint256)(address)" 0
```

### Issue: Policies Targeting Wrong Address

**Common Mistake**: Registering policies against token instead of RuleEngine

**Fix**:
```solidity
// WRONG
policyEngine.addPolicy(cmtatTokenAddress, ...);

// CORRECT
policyEngine.addPolicy(ruleEngineAddress, ...);
```

---

## Advantages Over Option 1A

| Benefit | How It Helps |
|---------|-------------|
| **Non-Destructive** | Keep all existing rules |
| **Token-Agnostic** | One deployment for all tokens |
| **Lower Cost** | Shared ACERule reduces gas |
| **Lower Risk** | Gradual adoption |
| **Flexible** | Add/remove rules anytime |
| **Composable** | Mix ACE with traditional rules |

---

## Next Steps

1. **Explore** other rules that can work with ACE
2. **Optimize** rule ordering if gas is concern
3. **Document** your multi-rule compliance framework
4. **Consider** upgrade to v3.0+ for stateful policies (Option 2B)

## Support

- 📖 [Full Option 1A Guide](option-1a-adapter-v2.md) - Detailed adapter example
- 📖 [Architecture Documentation](../ARCHITECTURE.md)
- 🐛 Report issues on GitHub
