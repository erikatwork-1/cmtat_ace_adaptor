# CMTAT-ACE Integration Workflows

This directory contains step-by-step integration workflows for all 4 implementation options.

## Available Options

| Option | Document | Approach | Version | Stateful | Best For |
|--------|----------|----------|---------|----------|----------|
| **1A** | [option-1a-adapter-v2.md](option-1a-adapter-v2.md) | Adapter | CMTAT v2.3.0 | ❌ | New tokens, simple compliance |
| **1B** | [option-1b-adapter-v3.md](option-1b-adapter-v3.md) | Adapter | CMTAT v3.0+ | ✅ | New tokens, stateful policies |
| **2A** | [option-2a-rule-v2.md](option-2a-rule-v2.md) | Rule | CMTAT v2.3.0 | ❌ | Existing tokens, multi-rule |
| **2B** | [option-2b-rule-v3.md](option-2b-rule-v3.md) | Rule | CMTAT v3.0+ | ✅ | Existing tokens, stateful |

## Quick Selection Guide

### Decision Flowchart

```
START: Integrate ACE with CMTAT?
  │
  ▼
[Q1] Need VolumePolicy or VolumeRatePolicy?
  │
  ├─ YES ──► MUST use v3.0+
  │           │
  │           ▼
  │         [Q2] Have existing rules to preserve?
  │           │
  │           ├─ YES ──► Option 2B (ACERule_v3)
  │           └─ NO  ──► Option 1B (ACERuleEngineAdapter_v3)
  │
  └─ NO ───► Can use v2.3.0 or v3.0+
              │
              ▼
            [Q3] Have existing rules to preserve?
              │
              ├─ YES ──► Option 2A (ACERule)
              └─ NO  ──► Option 1A (ACERuleEngineAdapter)
```

### Quick Questions

1. **Do you have existing compliance rules to preserve?**
   - YES → Go to Option 2A or 2B (Rule Approach)
   - NO → Go to Option 1A or 1B (Adapter Approach)

2. **Do you need stateful policies (VolumePolicy, VolumeRatePolicy)?**
   - YES → Must use v3.0+ (Option 1B or 2B)
   - NO → Can use v2.3.0 or v3.0+ (any option)

3. **What CMTAT version are you using?**
   - v2.3.0 → Option 1A or 2A
   - v3.0+ → Option 1B or 2B

## Option Comparison Table

| Option | Approach | Version | Stateful | Token-Agnostic | Best For |
|--------|----------|---------|----------|----------------|----------|
| **1A** | Adapter | v2.3.0 | ❌ | ❌ | New token, simple compliance |
| **1B** | Adapter | v3.0+ | ✅ | ❌ | New token, volume tracking |
| **2A** | Rule | v2.3.0 | ❌ | ✅ | Existing token, multi-rule |
| **2B** | Rule | v3.0+ | ✅ | ✅ | Existing token, stateful |

## Key Differences

### Options 1B & 2B: Stateful Enhancements (v3.0+)

Both 1B and 2B add **`operateOnTransfer()`** function:

```solidity
// NEW in v3.0+
function operateOnTransfer(address from, address to, uint256 amount)
    external returns (uint8);  // Adapter
    external returns (bool);   // Rule
```

**Capabilities Unlocked**:
- ✅ `PolicyEngine.run()` (stateful validation)
- ✅ VolumePolicy with tracking
- ✅ VolumeRatePolicy with rate limits
- ✅ postRun() hooks execute
- ✅ State-modifying operations

**Migration from v2.3.0**:
```
Option 1A → Option 1B: Deploy new adapter_v3
Option 2A → Option 2B: Deploy new ACERule_v3, replace in RuleEngine
```

### Constructor Comparison

#### Adapter Approach (1A & 1B)

```solidity
// Token-specific deployment
new ACERuleEngineAdapter(
    policyEngine,
    cmtatToken,      // ← Specific token
    extractor,
    owner
);

// Policies target TOKEN
policyEngine.addPolicy(tokenAddress, ...);
```

#### Rule Approach (2A & 2B)

```solidity
// Token-agnostic deployment
new ACERule(
    policyEngine,
    extractor
    // NO token parameter!
);

// Policies target RULEENGINE
policyEngine.addPolicy(ruleEngineAddress, ...);
```

## Comparison Matrix

### Adapter vs Rule

| Aspect | Adapter (1A/1B) | Rule (2A/2B) |
|--------|-----------------|--------------|
| **Integration Type** | Replaces RuleEngine | Adds to RuleEngine |
| **Existing Rules** | Cannot preserve | Preserves all |
| **Deployment** | One per token | One for all tokens |
| **Gas Cost** | Lower | Slightly higher |
| **Complexity** | Simpler | More flexible |
| **Rollback** | To old RuleEngine | Remove from rules |

### v2.3.0 vs v3.0+

| Capability | v2.3.0 (1A/2A) | v3.0+ (1B/2B) |
|------------|----------------|---------------|
| **Read-only Policies** | ✅ | ✅ |
| **Stateful Policies** | ❌ | ✅ |
| **VolumePolicy** | ⚠️ Reads only | ✅ Full tracking |
| **VolumeRatePolicy** | ⚠️ Reads only | ✅ Full limiting |
| **postRun() Hooks** | ❌ | ✅ |

## Integration Steps Comparison

### Option 1A/1B (Adapter)

1. Deploy Extractor
2. Deploy Adapter (with token address)
3. Configure PolicyEngine (target token)
4. **Replace RuleEngine** ← Destructive
5. Verify

### Option 2A/2B (Rule)

1. Deploy Extractor  
2. Deploy ACERule (no token address)
3. Configure PolicyEngine (target RuleEngine)
4. **Add to RuleEngine** ← Non-destructive
5. Verify multi-rule logic

## Policy Compatibility

### All Options (1A, 1B, 2A, 2B)

✅ AllowPolicy, RejectPolicy, MaxPolicy, IntervalPolicy, PausePolicy, etc.

### v3.0+ Only (1B, 2B)

✅ **VolumePolicy** - Tracks cumulative volumes
✅ **VolumeRatePolicy** - Enforces time-based rate limits

### v2.3.0 Limitation (1A, 2A)

⚠️ VolumePolicy - Can read, but won't update
⚠️ VolumeRatePolicy - Can read, but won't track

## Gas Cost Estimates

| Operation | 1A | 1B | 2A | 2B |
|-----------|----|----|----|----|
| Deployment | Medium | Medium | Low* | Low* |
| validateTransfer | ~24k | ~24k | ~27k | ~27k |
| operateOnTransfer | N/A | ~35k** | N/A | ~38k** |

*Lower for Rule because one deployment serves multiple tokens  
**Higher due to state updates

## Example Scenarios

### Scenario 1: New Token, Simple Compliance

**Recommended**: Option 1A (Adapter v2.3.0)

**Why**: Simplest integration, lowest gas cost, sufficient for static policies.

[Follow Option 1A Guide →](option-1a-adapter-v2.md)

### Scenario 2: New Token, Need Volume Tracking

**Recommended**: Option 1B (Adapter v3.0+)

**Why**: Stateful support required for VolumePolicy.

[Follow Option 1B Guide →](option-1b-adapter-v3.md)

### Scenario 3: Existing Token with Whitelist

**Recommended**: Option 2A (Rule v2.3.0)

**Why**: Preserves existing WhitelistRule, non-destructive integration.

[Follow Option 2A Guide →](option-2a-rule-v2.md)

### Scenario 4: Existing Token, Complex Compliance

**Recommended**: Option 2B (Rule v3.0+)

**Why**: Multi-rule composition with stateful policies.

[Follow Option 2B Guide →](option-2b-rule-v3.md)

## Migration Paths

### Path 1: No ACE → Adapter

```
Current: CMTAT Token (no ACE)
Target:  CMTAT Token → ACERuleEngineAdapter → ACE

Follow: Option 1A or 1B based on version
```

### Path 2: No ACE → Rule (Non-Destructive)

```
Current: CMTAT Token → RuleEngine → Existing Rules
Target:  CMTAT Token → RuleEngine → Existing Rules + ACERule

Follow: Option 2A or 2B based on version
```

### Path 3: Adapter → Rule (Add Flexibility)

```
Current: CMTAT → ACERuleEngineAdapter → ACE
Target:  CMTAT → RuleEngine → ACERule + Other Rules

Steps:
1. Deploy RuleEngine
2. Deploy ACERule
3. Add other rules
4. Switch token's RuleEngine
```

### Path 4: v2.3.0 → v3.0+ Upgrade

```
Current: CMTAT v2.3.0 → Option 1A or 2A
Target:  CMTAT v3.0+ → Option 1B or 2B

Steps:
1. Upgrade CMTAT token contract
2. Deploy new adapter/rule (v3)
3. Reconfigure policies
4. Test stateful features
```

## Testing Commands

```bash
# Test specific option
forge test --match-contract ACERuleEngineAdapterTest  # 1A/1B
forge test --match-contract ACERuleTest                # 2A/2B

# Test with gas reporting
forge test --gas-report

# Test with verbosity
forge test -vvv

# Run all tests
forge test
```

## Rollback Procedures

### Option 1A/1B Rollback

```solidity
// Revert to old RuleEngine
cmtatToken.setRuleEngine(oldRuleEngineAddress);
```

### Option 2A/2B Rollback

```solidity
// Remove ACERule from RuleEngine
ruleEngine.removeRuleAt(aceRuleIndex);
// Other rules continue working
```

## Common Issues

### All Options

| Issue | Solution |
|-------|----------|
| Transfers always revert | Check extractor configured |
| Transfers ignore ACE | Check policies registered |
| Wrong restriction messages | Update messages via `setRestrictionMessage()` |

### Adapter-Specific (1A/1B)

| Issue | Solution |
|-------|----------|
| Policies not applying | Verify targeting token address |
| Multiple tokens need ACE | Deploy adapter per token |

### Rule-Specific (2A/2B)

| Issue | Solution |
|-------|----------|
| ACERule not called | Verify added to RuleEngine |
| Policies not applying | Verify targeting RuleEngine address |

## Environment Variables

```bash
# Common
export POLICY_ENGINE_ADDRESS=0x...
export EXTRACTOR_ADDRESS=0x...
export RPC_URL=https://...
export PRIVATE_KEY=0x...

# Adapter (1A/1B)
export CMTAT_TOKEN_ADDRESS=0x...
export ADAPTER_OWNER=0x...

# Rule (2A/2B)
export RULE_ENGINE_ADDRESS=0x...
export ACE_RULE_ADDRESS=0x...
```

## Document Structure

Each workflow document includes:

- **Overview**: When to use this option and key benefits
- **Pre-requisites**: Required components and versions
- **Step-by-Step Integration**: Detailed instructions with code
- **Migration Scenarios**: Common use cases
- **Policy Examples**: Configuration examples
- **Testing Checklist**: Verification steps
- **Troubleshooting**: Common issues and solutions

## Getting Started

1. **Read** the [Architecture Documentation](../ARCHITECTURE.md) to understand the design
2. **Choose** your option using the selection guide above
3. **Open** the appropriate workflow document
4. **Follow** the step-by-step instructions
5. **Test** thoroughly before production deployment

## Support Resources

- 📖 [Architecture Documentation](../ARCHITECTURE.md) - Detailed design and capabilities
- 🏗️ [Main README](../../README.md) - Project overview

## Contributing

If you've successfully integrated ACE with CMTAT:
- Share your experience
- Contribute additional examples
- Report any issues or improvements

---

**Need help choosing?** Start with the [Decision Framework](../ARCHITECTURE.md#decision-framework) in the Architecture docs.
