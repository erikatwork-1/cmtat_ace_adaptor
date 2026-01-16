# Option 2B: ACE Rule for CMTAT v3.0+ Integration Guide

## Overview

**Option 2B** uses `ACERule_v3` as **one rule among many** within an existing CMTAT v3.0+ RuleEngine, with **full stateful operation support**.

### Quick Facts

| Property | Value |
|----------|-------|
| **Contract** | `ACERule_v3` |
| **CMTAT Version** | v3.0+ |
| **Architecture** | Composable rule |
| **Deployment** | One per RuleEngine (token-agnostic) |
| **Returns** | `bool` (true/false) |
| **Stateful Support** | ✅ Full support (VolumePolicy, VolumeRatePolicy) |
| **Best For** | Brownfield upgrades + stateful policies |

### Key Enhancement Over 2A

```
┌─────────────────────────────────────────────────────────┐
│ Option 2A (v2.3.0)     │ Option 2B (v3.0+)            │
├────────────────────────┼──────────────────────────────┤
│ validateTransfer()     │ validateTransfer()            │
│   └─ check() only      │   └─ check() (view)          │
│                        │                               │
│ ❌ No stateful ops     │ ✅ operateOnTransfer()        │
│                        │   └─ run() (stateful)        │
│                        │                               │
│ ⚠️ View-only policies  │ ✅ Full ACE policy suite     │
└────────────────────────┴──────────────────────────────┘
```

## Architecture

### System Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     CMTAT Token v3.0+                         │
│                                                                │
│  _transfer(from, to, amount)                                  │
│      │                                                         │
│      ├─► validateTransfer() ──────┐                           │
│      │    (view check)            │                           │
│      │                            │                           │
│      └─► operateOnTransfer() ─────┤ (NEW in v3.0+)           │
│           (stateful run)          │                           │
└────────────────────────────────────┼─────────────────────────┘
                                     │
                                     ▼
┌──────────────────────────────────────────────────────────────┐
│                  CMTAT RuleEngine v3.0+                       │
│              (Orchestrates multiple rules)                    │
│                                                                │
│  validateTransfer(from, to, amount) → bool                    │
│      ├─► Rule 1: ACERule_v3.validateTransfer()               │
│      ├─► Rule 2: WhitelistRule.validateTransfer()            │
│      └─► Rule 3: Other rules...                              │
│           ALL must return true (AND logic)                    │
│                                                                │
│  operateOnTransfer(from, to, amount) → bool                   │
│      ├─► Rule 1: ACERule_v3.operateOnTransfer() ─────────┐   │
│      ├─► Rule 2: Other stateful rules...                  │   │
│      └─► ALL must return true (AND logic)                 │   │
└────────────────────────────────────────────────────────────┼──┘
                                                              │
                                                              ▼
┌──────────────────────────────────────────────────────────────┐
│                      ACERule_v3                               │
│              (Token-agnostic ACE integration)                 │
│                                                                │
│  validateTransfer(from, to, amount) → bool                    │
│      └─► policyEngine.check() ──────────────┐                │
│           (view-only)                        │                │
│                                              │                │
│  operateOnTransfer(from, to, amount) → bool  │                │
│      └─► policyEngine.run() ─────────────────┤ (STATEFUL!)   │
│           (state-modifying)                   │                │
└──────────────────────────────────────────────┼────────────────┘
                                               │
                                               ▼
┌──────────────────────────────────────────────────────────────┐
│                   ACE PolicyEngine                            │
│                                                                │
│  check(payload) → void (view)                                 │
│      └─► Validate without state updates                       │
│                                                                │
│  run(payload) → void (non-view)                               │
│      ├─► Validate transfer                                    │
│      ├─► Update policy state (volumes, rates)                 │
│      └─► Execute postRun() hooks                              │
└──────────────────────────────────────────────────────────────┘
```

### Token-Agnostic Design

**Critical Difference from Option 1B**: ACERule_v3 has NO targetToken parameter!

```solidity
// ❌ Option 1B (token-specific)
ACERuleEngineAdapter_v3 adapter = new ACERuleEngineAdapter_v3(
    policyEngine,
    tokenAddress,    // ← Token-specific
    extractor,
    owner
);

// ✅ Option 2B (token-agnostic)
ACERule_v3 aceRule = new ACERule_v3(
    policyEngine,
    extractor
);
// One ACERule_v3 → Many tokens!
```

## Prerequisites

### Dependencies

```bash
# Foundry project
forge install

# Required submodules
git submodule update --init --recursive
```

### CMTAT Version Requirements

- **CMTAT**: v3.0 or higher
- **RuleEngine**: v3.0 or higher (with `operateOnTransfer` support)
- **OpenZeppelin**: v5.0+

### ACE Components

- **PolicyEngine**: Deployed ACE PolicyEngine
- **Extractor**: `CMTATTransferExtractor`
- **Policies**: VolumePolicy, VolumeRatePolicy, or other stateful policies

---

## Step-by-Step Integration

### Step 1: Deploy ACERule_v3 (Token-Agnostic)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ACERule_v3} from "src/rule/ACERule_v3.sol";
import {CMTATTransferExtractor} from "src/extractors/CMTATTransferExtractor.sol";

contract DeployACERule_v3 {
    function run() external returns (ACERule_v3) {
        address policyEngine = 0x...; // Your PolicyEngine
        
        // Deploy extractor (can be shared)
        CMTATTransferExtractor extractor = new CMTATTransferExtractor();
        
        // Deploy ACERule_v3 (NO token parameter!)
        ACERule_v3 aceRule = new ACERule_v3(
            policyEngine,
            address(extractor)
        );
        
        return aceRule;
    }
}
```

### Step 2: Add to RuleEngine

```solidity
// Add ACERule_v3 to existing RuleEngine
// This is NON-DESTRUCTIVE - existing rules remain!

ruleEngine.addRule(address(aceRule));

// Verify
require(ruleEngine.ruleCount() > 0, "Rule not added");
```

### Step 3: Register ACE Policies

**Critical**: Policies registered against **RuleEngine address**, NOT token!

```solidity
// Example: Register VolumePolicy for RuleEngine
bytes4 transferSelector = bytes4(keccak256("transfer(address,uint256)"));

policyEngine.addPolicy(
    address(ruleEngine),     // ← RuleEngine, NOT token!
    transferSelector,
    volumePolicyAddress,
    abi.encode(
        1000000 ether,       // Daily volume limit
        86400                // 24 hour window
    )
);

// This RuleEngine can now be used by MULTIPLE tokens
```

### Step 4: Test Integration

```solidity
function testIntegration() public {
    // Mint tokens
    token.mint(alice, 1000 ether);
    
    // Test view validation
    bool isValid = aceRule.validateTransfer(alice, bob, 100 ether);
    require(isValid, "Validation failed");
    
    // Test stateful operation
    bool allowed = aceRule.operateOnTransfer(alice, bob, 100 ether);
    require(allowed, "Operation failed");
    
    // Perform actual transfer (goes through RuleEngine → ACERule_v3)
    vm.prank(alice);
    token.transfer(bob, 100 ether);
    
    // Verify balances
    assertEq(token.balanceOf(bob), 100 ether);
}
```

---

## Configuration Examples

### Example 1: Single Token with ACERule_v3

```solidity
// Deploy components
ACERule_v3 aceRule = new ACERule_v3(policyEngine, extractor);
RuleEngine ruleEngine = new RuleEngine();
CMTATv3 token = new CMTATv3("Token A", "TKA");

// Add ACERule_v3 to RuleEngine
ruleEngine.addRule(address(aceRule));

// Set RuleEngine for token
token.setRuleEngine(address(ruleEngine));

// Register policies against RuleEngine
policyEngine.addPolicy(
    address(ruleEngine),
    bytes4(keccak256("transfer(address,uint256)")),
    volumePolicyAddress,
    abi.encode(1000000 ether, 86400, false)
);

// Now token uses ACERule_v3 for stateful validation
token.transfer(bob, 100 ether);
```

### Example 2: Multiple Tokens, One ACERule_v3

**This is the power of token-agnostic design!**

```solidity
// Deploy ONE ACERule_v3
ACERule_v3 sharedRule = new ACERule_v3(policyEngine, extractor);

// Deploy THREE RuleEngines (one per token)
RuleEngine ruleEngineA = new RuleEngine();
RuleEngine ruleEngineB = new RuleEngine();
RuleEngine ruleEngineC = new RuleEngine();

// Add SAME ACERule_v3 to all RuleEngines
ruleEngineA.addRule(address(sharedRule));
ruleEngineB.addRule(address(sharedRule));
ruleEngineC.addRule(address(sharedRule));

// Deploy three tokens
CMTATv3 tokenA = new CMTATv3("Token A", "TKA");
CMTATv3 tokenB = new CMTATv3("Token B", "TKB");
CMTATv3 tokenC = new CMTATv3("Token C", "TKC");

// Set RuleEngines
tokenA.setRuleEngine(address(ruleEngineA));
tokenB.setRuleEngine(address(ruleEngineB));
tokenC.setRuleEngine(address(ruleEngineC));

// Register policies for each RuleEngine
policyEngine.addPolicy(address(ruleEngineA), selector, policy, params);
policyEngine.addPolicy(address(ruleEngineB), selector, policy, params);
policyEngine.addPolicy(address(ruleEngineC), selector, policy, params);

// All tokens now use ACERule_v3 for stateful validation!
```

### Example 3: Multi-Rule Composition with Stateful ACE

```solidity
// Deploy multiple rules
ACERule_v3 aceRule = new ACERule_v3(policyEngine, extractor);
WhitelistRule whitelist = new WhitelistRule();
MaxHoldingRule maxHolding = new MaxHoldingRule();

// Add all rules to RuleEngine (order matters!)
ruleEngine.addRule(address(aceRule));      // ACE compliance
ruleEngine.addRule(address(whitelist));    // Whitelist check
ruleEngine.addRule(address(maxHolding));   // Position limits

// ALL rules must pass (AND logic)
// ACERule_v3 provides stateful tracking
// Other rules provide additional validation
```

---

## Migration Scenarios

### Scenario 1: Upgrade from Option 2A (v2.3.0 → v3.0+)

**Objective**: Add stateful validation to existing ACERule deployment.

#### Step 1: Deploy ACERule_v3

```solidity
// Deploy new ACERule_v3
ACERule_v3 newRule = new ACERule_v3(policyEngine, extractor);
```

#### Step 2: Update RuleEngine

```solidity
// Remove old ACERule (v2.3.0)
ruleEngine.removeRule(address(oldACERule));

// Add new ACERule_v3
ruleEngine.addRule(address(newRule));
```

#### Step 3: Update Policy Registration

```solidity
// Policies remain registered to RuleEngine
// No changes needed if RuleEngine address unchanged

// But NOW stateful policies will work!
policyEngine.addPolicy(
    address(ruleEngine),
    selector,
    volumePolicyAddress,        // NOW tracks state!
    abi.encode(1000000 ether, 86400, false)
);
```

#### Step 4: Test

```solidity
// Test stateful validation
vm.prank(alice);
token.transfer(bob, 100 ether);

// VolumePolicy now tracks cumulative volume
vm.prank(alice);
token.transfer(bob, 200 ether);

// State accumulates!
```

### Scenario 2: Add ACERule_v3 to Existing Multi-Rule Setup

**Objective**: Add ACE compliance to token already using multiple rules.

```solidity
// Existing setup
ruleEngine.rules();
// → [WhitelistRule, MaxHoldingRule, CountryRestrictionRule]

// Add ACERule_v3 (non-destructive!)
ruleEngine.addRule(address(aceRule_v3));

// New setup
ruleEngine.rules();
// → [WhitelistRule, MaxHoldingRule, CountryRestrictionRule, ACERule_v3]

// ALL rules still validate, ACERule_v3 adds ACE compliance
```

---

## Policy Examples

### VolumePolicy with ACERule_v3

```solidity
// Register VolumePolicy against RuleEngine
policyEngine.addPolicy(
    address(ruleEngine),     // RuleEngine, NOT token
    bytes4(keccak256("transfer(address,uint256)")),
    volumePolicyAddress,
    abi.encode(
        10_000_000 ether,    // Max volume: 10M tokens
        86400,               // Window: 24 hours
        true                 // Per address: true
    )
);

// Behavior: Tracks volume per address over 24h window
// operateOnTransfer() updates state via run()
```

### VolumeRatePolicy with ACERule_v3

```solidity
// Register VolumeRatePolicy
policyEngine.addPolicy(
    address(ruleEngine),
    bytes4(keccak256("transfer(address,uint256)")),
    volumeRatePolicyAddress,
    abi.encode(
        1000 ether,          // Max rate: 1000 tokens
        60                   // Per minute
    )
);

// Behavior: Limits transfer rate to 1000 tokens/minute
// Prevents rapid trading
```

### Combined Stateful Policies

```solidity
bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));

// Policy 1: Daily volume limit
policyEngine.addPolicy(
    address(ruleEngine),
    selector,
    volumePolicyAddress,
    abi.encode(1000000 ether, 86400, true)
);

// Policy 2: Per-minute rate limit
policyEngine.addPolicy(
    address(ruleEngine),
    selector,
    volumeRatePolicyAddress,
    abi.encode(100 ether, 60)
);

// Policy 3: KYC check (stateless)
policyEngine.addPolicy(
    address(ruleEngine),
    selector,
    kycPolicyAddress,
    abi.encode()
);

// All policies enforce via ACERule_v3.operateOnTransfer()
```

---

## Testing

### Unit Test: Stateful Validation

```solidity
// test/unit/ACERule_v3.t.sol

function test_OperateOnTransfer_UpdatesState() public {
    // Setup VolumePolicy
    policyEngine.addPolicy(
        address(ruleEngine),
        bytes4(keccak256("transfer(address,uint256)")),
        volumePolicyAddress,
        abi.encode(1000 ether, 86400, false)
    );
    
    // First transfer: 100 used
    bool allowed1 = aceRule.operateOnTransfer(alice, bob, 100 ether);
    assertTrue(allowed1);
    
    // Second transfer: 300 used
    bool allowed2 = aceRule.operateOnTransfer(alice, bob, 200 ether);
    assertTrue(allowed2);
    
    // Third transfer: Would exceed 1000
    bool allowed3 = aceRule.operateOnTransfer(alice, bob, 800 ether);
    assertFalse(allowed3); // Rejected!
}
```

### Integration Test: Multi-Token

```solidity
// test/integration/ACERule_v3_Integration.t.sol

function test_OneACERule_MultipleTokens_StatefulTracking() public {
    // Deploy ONE ACERule_v3
    ACERule_v3 sharedRule = new ACERule_v3(policyEngine, extractor);
    
    // Setup two tokens with separate RuleEngines
    RuleEngine engineA = new RuleEngine();
    RuleEngine engineB = new RuleEngine();
    
    engineA.addRule(address(sharedRule));
    engineB.addRule(address(sharedRule));
    
    CMTATv3 tokenA = new CMTATv3("Token A", "TKA");
    CMTATv3 tokenB = new CMTATv3("Token B", "TKB");
    
    tokenA.setRuleEngine(address(engineA));
    tokenB.setRuleEngine(address(engineB));
    
    // Register separate VolumePolicy for each RuleEngine
    policyEngine.addPolicy(
        address(engineA),
        selector,
        volumePolicyAddress,
        abi.encode(500 ether, 86400, false) // 500 limit for engineA
    );
    
    policyEngine.addPolicy(
        address(engineB),
        selector,
        volumePolicyAddress,
        abi.encode(1000 ether, 86400, false) // 1000 limit for engineB
    );
    
    // Transfers on tokenA tracked separately from tokenB
    tokenA.transfer(bob, 400 ether); // OK: 400/500 for engineA
    tokenB.transfer(bob, 800 ether); // OK: 800/1000 for engineB
    
    // Each RuleEngine has independent state!
}
```

---

## Comparison: 2A vs 2B

| Feature | 2A (v2.3.0) | 2B (v3.0+) |
|---------|-------------|------------|
| **CMTAT Version** | v2.3.0 | v3.0+ |
| **validateTransfer()** | ✅ check() | ✅ check() |
| **operateOnTransfer()** | ❌ Not available | ✅ run() |
| **VolumePolicy** | ⚠️ Reads only | ✅ Tracks state |
| **VolumeRatePolicy** | ⚠️ Reads only | ✅ Tracks state |
| **postRun() hooks** | ❌ Never execute | ✅ Always execute |
| **Token-agnostic** | ✅ Yes | ✅ Yes |
| **Composable** | ✅ Yes | ✅ Yes |
| **Returns** | `bool` | `bool` |
| **Use case** | Simple compliance | Advanced compliance |

---

## Comparison: 1B vs 2B

| Feature | 1B (Adapter_v3) | 2B (Rule_v3) |
|---------|-----------------|--------------|
| **Architecture** | Replacement | Composition |
| **Token binding** | Token-specific | Token-agnostic |
| **Returns** | `uint8` codes | `bool` |
| **Other rules** | ❌ Exclusive | ✅ Composable |
| **Deployment cost** | One per token | One per RuleEngine |
| **Migration** | Requires replacement | Non-destructive |
| **Flexibility** | Less flexible | More flexible |
| **Best for** | Greenfield | Brownfield |

---

## Troubleshooting

### Issue: "operateOnTransfer not found on RuleEngine"

**Cause**: RuleEngine is v1.0.2.1 (v2.3.0), not v3.0+.

**Solution**: Upgrade to RuleEngine v3.0+ or use Option 2A (ACERule).

### Issue: VolumePolicy not tracking state

**Cause**: RuleEngine not calling operateOnTransfer().

**Solution**: Verify RuleEngine v3.0+ implementation calls operateOnTransfer().

### Issue: Policies registered to wrong address

**Cause**: Policies registered to token instead of RuleEngine.

**Solution**: Re-register policies to RuleEngine address:
```solidity
policyEngine.addPolicy(
    address(ruleEngine),  // ← Correct
    // NOT address(token)  ← Wrong
    selector,
    policyAddress,
    params
);
```

---

## Best Practices

1. **Deploy once** - ACERule_v3 is reusable across RuleEngines
2. **Register to RuleEngine** - Policies go to RuleEngine, not token
3. **Compose carefully** - Rule order matters in AND logic
4. **Test state updates** - Verify VolumePolicy tracking works
5. **Monitor gas** - Stateful operations cost more
6. **Version control policies** - Document policy parameters
7. **Use for brownfield** - Ideal for non-destructive upgrades

---

## Next Steps

- Review [Option 1B (ACE Adapter v3.0+)](./option-1b-adapter-v3.md) for comparison
- See [ARCHITECTURE.md](../ARCHITECTURE.md) for design philosophy
- Check [TEST_SUMMARY.md](../../TEST_SUMMARY.md) for test coverage
- Refer to [README.md](./README.md) for commands and quick reference

---

## Summary

**Option 2B (ACERule_v3)** provides:

✅ Token-agnostic deployment (one rule, many tokens)  
✅ Non-destructive integration (compose with existing rules)  
✅ Full stateful policy support (VolumePolicy, VolumeRatePolicy)  
✅ postRun() hook execution  
✅ Returns `bool` for easy composition  
✅ Ideal for brownfield upgrades  

**Best for**: Upgrading existing CMTAT deployments to add ACE compliance without disrupting existing rules, with full stateful policy support.

For questions or assistance, please consult the main [README.md](../../README.md) or open an issue.
