# CMTAT-ACE Integration Architecture

## Table of Contents

- [Overview](#overview)
- [Design Philosophy](#design-philosophy)
- [The 4-Option Architecture](#the-4-option-architecture)
- [Approach 1: Adapter Architecture](#approach-1-adapter-architecture)
- [Approach 2: Rule Architecture](#approach-2-rule-architecture)
- [Version Comparison: v2.3.0 vs v3.0+](#version-comparison-v230-vs-v30)
- [Policy Registration Patterns](#policy-registration-patterns)
- [Data Flow Diagrams](#data-flow-diagrams)
- [Capabilities Matrix](#capabilities-matrix)
- [Decision Framework](#decision-framework)
- [Migration Paths](#migration-paths)

---

## Overview

This project provides a comprehensive integration solution between **CMTAT (Capital Markets and Technology Association)** tokens and **Chainlink ACE (Access Control Engine)** PolicyEngine. The solution offers **4 distinct implementation options** organized in a 2×2 matrix:

- **2 Architectural Approaches**: Adapter (Replacement) vs Rule (Composition)
- **2 CMTAT Versions**: v2.3.0 vs v3.0+

This flexibility enables seamless integration for both **greenfield deployments** (new tokens) and **brownfield upgrades** (existing tokens with compliance rules).

---

## Design Philosophy

### Core Principles

1. **Flexibility First**: Provide multiple integration paths to suit different deployment contexts
2. **Non-Destructive Options**: Enable gradual migration without breaking existing systems
3. **Version Support**: Maintain backward compatibility while supporting future enhancements
4. **Separation of Concerns**: Clear boundaries between adapter and rule approaches
5. **Gas Efficiency**: Optimize for common use cases while maintaining flexibility

### Key Innovations

#### Token-Agnostic Rule Design

The **ACERule** contracts (Options 2A and 2B) introduce a novel token-agnostic design:

- **No targetToken parameter**: One deployment serves multiple CMTAT tokens
- **RuleEngine-centric**: Policies registered against RuleEngine, not individual tokens
- **Cost-efficient**: Lower deployment costs and simplified policy management
- **Composable**: Works seamlessly alongside other compliance rules

This contrasts with the traditional **ACERuleEngineAdapter** approach (Options 1A and 1B) which uses token-specific deployments.

---

## The 4-Option Architecture

### Option Matrix

| Option | Architecture | CMTAT Version | RuleEngine Version | Contract | Stateful |
|--------|-------------|---------------|-------------------|----------|----------|
| **1A** | Adapter (Replacement) | v2.3.0 | v1.0.2.1 | ACERuleEngineAdapter | ❌ View-only |
| **1B** | Adapter (Replacement) | v3.0+ | v3.0+ | ACERuleEngineAdapter_v3 | ✅ Full support |
| **2A** | Rule (Composition) | v2.3.0 | v1.0.2.1 | ACERule | ❌ View-only |
| **2B** | Rule (Composition) | v3.0+ | v3.0+ | ACERule_v3 | ✅ Full support |

### When to Use Each Option

#### Option 1A: ACERuleEngineAdapter (v2.3.0)
**Best for**:
- New CMTAT v2.3.0 deployments
- Full migration to ACE (no existing rules to preserve)
- Maximum gas efficiency
- Simple compliance requirements

**Trade-offs**:
- Destructive integration (replaces existing RuleEngine)
- Token-specific deployment
- View-only validation (stateful policies won't work)

#### Option 1B: ACERuleEngineAdapter_v3 (v3.0+)
**Best for**:
- New CMTAT v3.0+ deployments
- Need for stateful policies (VolumePolicy, VolumeRatePolicy)
- Full migration to ACE
- Maximum feature set

**Trade-offs**:
- Requires CMTAT v3.0+
- Destructive integration
- Token-specific deployment

#### Option 2A: ACERule (v2.3.0)
**Best for**:
- Existing CMTAT v2.3.0 tokens with compliance rules
- Gradual migration to ACE
- Multi-rule compliance frameworks
- Risk-averse deployments

**Trade-offs**:
- Slightly higher gas cost (one extra hop)
- View-only validation (stateful policies won't work)
- Requires existing RuleEngine

#### Option 2B: ACERule_v3 (v3.0+)
**Best for**:
- Existing CMTAT v3.0+ tokens with compliance rules
- Need for stateful policies
- Complex multi-rule compliance
- Future-proof architecture

**Trade-offs**:
- Requires CMTAT v3.0+ and RuleEngine v3.0+
- Slightly higher gas cost
- More complex architecture

---

## Approach 1: Adapter Architecture

### Overview

The **Adapter Approach** provides a **drop-in replacement** for CMTAT's RuleEngine, allowing direct integration with ACE PolicyEngine.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    CMTAT Token                          │
│                                                         │
│  _transfer(from, to, amount)                           │
│         │                                               │
│         ▼                                               │
│  ruleEngine.validateTransfer()  ← Interface call       │
│         │                                               │
│         └─────────────────────────┐                     │
└───────────────────────────────────┼─────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────┐
│          ACERuleEngineAdapter / _v3                     │
│                                                         │
│  Implements: IRuleEngine                                │
│    - validateTransfer() → uint8        [VIEW]           │
│    - detectTransferRestriction() → uint8 [VIEW]         │
│    - operateOnTransfer() → uint8       [v3.0+ only]     │
│                                                         │
│  Internal:                                              │
│    - policyEngine.check()  [v2.3.0]                     │
│    - policyEngine.run()    [v3.0+ in operateOnTransfer] │
│         │                                               │
└─────────┼───────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│              ACE PolicyEngine                           │
│                                                         │
│  - Executes policies                                    │
│  - Returns success/failure                              │
│  - Updates state (if run() called)                      │
└─────────────────────────────────────────────────────────┘
```

### Key Components

#### ACERuleEngineAdapter (v2.3.0)

**Location**: `src/ACERuleEngineAdapter.sol`

**Constructor**:
```solidity
constructor(
    address _policyEngine,   // ACE PolicyEngine
    address _targetToken,    // ← Token-specific!
    address _extractor,      // Parameter extractor
    address _owner           // Admin
)
```

**Interface Implementation**:
```solidity
function validateTransfer(address from, address to, uint256 amount)
    external view returns (bool);

function detectTransferRestriction(address from, address to, uint256 amount)
    external view returns (uint8);

function messageForTransferRestriction(uint8 code)
    external view returns (string memory);
```

**Policy Registration**:
```solidity
// Policies registered against TOKEN address
policyEngine.addPolicy(
    cmtatTokenAddress,  // ← Token address
    transferSelector,
    policyAddress,
    parameters
);
```

#### ACERuleEngineAdapter_v3 (v3.0+)

**Location**: `src/adapter/ACERuleEngineAdapter_v3.sol`

**Additional Interface**:
```solidity
function operateOnTransfer(address from, address to, uint256 amount)
    external returns (uint8);  // ← Non-view, enables stateful ops
```

**Capabilities**:
- ✅ All v2.3.0 features
- ✅ Stateful validation via `operateOnTransfer()`
- ✅ Uses `PolicyEngine.run()` for state updates
- ✅ VolumePolicy with tracking
- ✅ VolumeRatePolicy with accumulation
- ✅ postRun() hooks execute

### Advantages

1. **Simpler Architecture**: Direct CMTAT → Adapter → ACE flow
2. **Lower Gas Costs**: No intermediate RuleEngine hop
3. **Full Control**: Complete ownership of validation logic
4. **Easier to Understand**: Straightforward integration path
5. **Best for Greenfield**: Ideal for new token deployments

### Limitations

1. **Destructive**: Replaces existing RuleEngine (cannot preserve other rules)
2. **Token-Specific**: One adapter deployment per token
3. **No Rule Composition**: Cannot combine with other compliance rules
4. **Migration Complexity**: Harder to migrate existing multi-rule systems

---

## Approach 2: Rule Architecture

### Overview

The **Rule Approach** integrates ACE as **one rule among many** within CMTAT's RuleEngine framework, enabling non-destructive integration.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    CMTAT Token                          │
│                                                         │
│  _transfer(from, to, amount)                           │
│         │                                               │
│         ▼                                               │
│  ruleEngine.validateTransfer()  ← Interface call       │
└─────────┼───────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│                  RuleEngine                             │
│                                                         │
│  Orchestrates multiple rules (AND logic):               │
│    │                                                    │
│    ├──► ACERule / ACERule_v3  ────┐                    │
│    │                               │                    │
│    ├──► WhitelistRule             │ All must pass      │
│    │                               │                    │
│    ├──► ConditionalTransferRule   │                    │
│    │                               │                    │
│    └──► Other compliance rules    │                    │
│                                    │                    │
└────────────────────────────────────┼────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────┐
│            ACERule / ACERule_v3                         │
│                                                         │
│  Implements: IRule                                      │
│    - validateTransfer() → bool     [VIEW]               │
│    - detectTransferRestriction() → string [VIEW]        │
│    - operateOnTransfer() → bool    [v3.0+ only]         │
│                                                         │
│  Token-Agnostic Design:                                 │
│    - NO targetToken parameter                           │
│    - Reusable across multiple tokens                    │
│    - Policies registered against RuleEngine             │
│         │                                               │
└─────────┼───────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│              ACE PolicyEngine                           │
│                                                         │
│  - Executes policies                                    │
│  - Returns success/failure                              │
│  - Updates state (if run() called)                      │
└─────────────────────────────────────────────────────────┘
```

### Key Components

#### ACERule (v2.3.0)

**Location**: `src/rule/ACERule.sol`

**Constructor** (Token-Agnostic!):
```solidity
constructor(
    address _policyEngine,   // ACE PolicyEngine
    address _extractor       // Parameter extractor
    // NO targetToken! ← Key difference
)
```

**Interface Implementation**:
```solidity
function validateTransfer(address from, address to, uint256 amount)
    external view returns (bool);  // ← Returns bool, not uint8

function detectTransferRestriction(address from, address to, uint256 amount)
    external view returns (string memory);  // ← Returns string
```

**Policy Registration**:
```solidity
// Policies registered against RULEENGINE address
policyEngine.addPolicy(
    ruleEngineAddress,  // ← RuleEngine, NOT token!
    transferSelector,
    policyAddress,
    parameters
);
```

#### ACERule_v3 (v3.0+)

**Location**: `src/rule/ACERule_v3.sol`

**Additional Interface**:
```solidity
function operateOnTransfer(address from, address to, uint256 amount)
    external returns (bool);  // ← Non-view, enables stateful ops
```

**Capabilities**:
- ✅ All v2.3.0 features
- ✅ Stateful validation via `operateOnTransfer()`
- ✅ Uses `PolicyEngine.run()` for state updates
- ✅ Token-agnostic design
- ✅ VolumePolicy with tracking
- ✅ VolumeRatePolicy with accumulation

### Advantages

1. **Non-Destructive**: Preserves existing compliance rules
2. **Token-Agnostic**: One deployment serves multiple tokens
3. **Composable**: Works alongside WhitelistRule, ConditionalTransferRule, etc.
4. **Lower Risk**: Gradual migration path for production systems
5. **Cost-Efficient**: Shared deployment reduces overall costs
6. **Flexible**: Can add/remove rules without redeploying

### Limitations

1. **Slightly Higher Gas**: One additional hop through RuleEngine
2. **More Complex**: Requires understanding RuleEngine orchestration
3. **AND Logic**: ALL rules must pass (cannot do OR logic)
4. **Requires RuleEngine**: Must have existing RuleEngine infrastructure

---

## Version Comparison: v2.3.0 vs v3.0+

### CMTAT v2.3.0 Capabilities

#### Interface

```solidity
interface IRuleEngine {
    function validateTransfer(address from, address to, uint256 amount)
        external view returns (bool);  // ← VIEW only!
    
    function detectTransferRestriction(address from, address to, uint256 amount)
        external view returns (uint8);
    
    function messageForTransferRestriction(uint8 code)
        external view returns (string memory);
}
```

#### Limitations

| Feature | Status | Impact |
|---------|--------|--------|
| PolicyEngine.check() | ✅ Supported | Read-only validation works |
| PolicyEngine.run() | ❌ Cannot use | VIEW function constraint |
| State updates | ❌ Not possible | Policies cannot modify state |
| VolumePolicy | ⚠️ Reads only | Volume tracking won't accumulate |
| VolumeRatePolicy | ⚠️ Reads only | Rate limiting won't work |
| postRun() hooks | ❌ Never execute | VIEW function limitation |
| Context parameter | ❌ Not supported | CMTAT doesn't provide context |

#### Compatible Policies (v2.3.0)

**Fully Functional**:
- AllowPolicy (whitelist/blacklist)
- RejectPolicy
- MaxPolicy (static limits)
- IntervalPolicy (time windows)
- PausePolicy
- OnlyOwnerPolicy
- OnlyAuthorizedSenderPolicy
- BypassPolicy
- SecureMintPolicy
- RoleBasedAccessControlPolicy
- CredentialRegistryIdentityValidatorPolicy

**Partially Functional** (reads only):
- VolumePolicy (can read limits, but won't track usage)
- VolumeRatePolicy (can read rates, but won't accumulate)

### CMTAT v3.0+ Enhancements

#### Extended Interface

```solidity
interface IRuleEngine {
    // Existing from v2.3.0
    function validateTransfer(address from, address to, uint256 amount)
        external view returns (bool);
    
    // NEW in v3.0+
    function operateOnTransfer(address from, address to, uint256 amount)
        external returns (bool);  // ← Non-view!
}
```

#### Capabilities Unlocked

| Feature | v2.3.0 | v3.0+ | Impact |
|---------|--------|-------|--------|
| PolicyEngine.check() | ✅ | ✅ | Read-only validation |
| PolicyEngine.run() | ❌ | ✅ | Stateful validation enabled |
| State updates | ❌ | ✅ | Policies can modify state |
| VolumePolicy | ⚠️ | ✅ | Full volume tracking |
| VolumeRatePolicy | ⚠️ | ✅ | Full rate limiting |
| postRun() hooks | ❌ | ✅ | Hooks execute after validation |
| Context parameter | ❌ | ✅* | *If CMTAT provides it |

#### All Policies Fully Functional (v3.0+)

With v3.0+, **ALL ACE policies** work correctly:
- ✅ All v2.3.0 compatible policies
- ✅ VolumePolicy (with tracking)
- ✅ VolumeRatePolicy (with accumulation)
- ✅ Any custom stateful policies
- ✅ postRun() hooks execute

### Upgrade Path: v2.3.0 → v3.0+

```
CMTAT v2.3.0 Token
    ↓ (upgrade token contract)
CMTAT v3.0+ Token
    ↓ (update integration)
Choose:
    Option 1B: ACERuleEngineAdapter_v3
    Option 2B: ACERule_v3
```

---

## Policy Registration Patterns

### Pattern 1: Adapter Approach (Token-Centric)

```solidity
// Step 1: Deploy adapter for specific token
ACERuleEngineAdapter adapter = new ACERuleEngineAdapter(
    policyEngineAddress,
    cmtatTokenAddress,  // ← Token-specific
    extractorAddress,
    ownerAddress
);

// Step 2: Configure extractor
policyEngine.setExtractor(transferSelector, extractorAddress);

// Step 3: Register policies against TOKEN address
policyEngine.addPolicy(
    cmtatTokenAddress,     // ← Target is the token
    transferSelector,
    allowPolicyAddress,
    parameters
);

// Step 4: Set adapter as RuleEngine
cmtatToken.setRuleEngine(address(adapter));
```

**Key Point**: Policies target the **CMTAT token address**.

### Pattern 2: Rule Approach (RuleEngine-Centric)

```solidity
// Step 1: Deploy ACERule (token-agnostic!)
ACERule aceRule = new ACERule(
    policyEngineAddress,
    extractorAddress
    // NO token address!
);

// Step 2: Add ACERule to RuleEngine
ruleEngine.addRule(address(aceRule));

// Step 3: Configure extractor
policyEngine.setExtractor(transferSelector, extractorAddress);

// Step 4: Register policies against RULEENGINE address
policyEngine.addPolicy(
    ruleEngineAddress,     // ← Target is the RuleEngine
    transferSelector,
    allowPolicyAddress,
    parameters
);
```

**Key Point**: Policies target the **RuleEngine address**, not individual tokens.

### Policy Registration Comparison

| Aspect | Adapter (Token-Centric) | Rule (RuleEngine-Centric) |
|--------|------------------------|---------------------------|
| Target Address | CMTAT Token | RuleEngine |
| Reusability | One token per adapter | Multiple tokens per rule |
| Policy Scope | Token-specific | RuleEngine-wide |
| Deployment Cost | Higher (per token) | Lower (shared) |
| Management | Separate policies per token | Unified policy management |

---

## Data Flow Diagrams

### Flow 1: Adapter Approach - View Validation (v2.3.0)

```
User calls token.transfer()
    │
    ▼
CMTAT Token._transfer()
    │
    ▼
RuleEngine.validateTransfer()  ← VIEW function
    │
    ▼
ACERuleEngineAdapter.validateTransfer()
    │
    ├─ Construct payload: {selector, sender, data, context}
    │
    ▼
PolicyEngine.check(payload)  ← VIEW, no state changes
    │
    ├─ Load policies for (token, selector)
    ├─ Execute each policy in sequence
    ├─ Check conditions (read-only)
    │
    ├──► If ANY policy rejects ──► Revert
    │
    └──► If ALL policies pass ──► Return success
         │
         ▼
ACERuleEngineAdapter returns true/false
    │
    ▼
CMTAT Token completes transfer or reverts
```

### Flow 2: Adapter Approach - Stateful Validation (v3.0+)

```
User calls token.transfer()
    │
    ▼
CMTAT Token._transfer()
    │
    ├─ Step 1: Call validateTransfer() [VIEW check]
    │  (Quick validation, no state changes)
    │
    ├─ Step 2: Call operateOnTransfer() [NON-VIEW]
    │     │
    │     ▼
    │  ACERuleEngineAdapter_v3.operateOnTransfer()
    │     │
    │     ├─ Construct payload
    │     │
    │     ▼
    │  PolicyEngine.run(payload)  ← NON-VIEW, can modify state!
    │     │
    │     ├─ Load policies
    │     ├─ Execute preRun() hooks
    │     ├─ Execute each policy (can update state)
    │     ├─ Execute postRun() hooks
    │     │
    │     ├──► If ANY policy rejects ──► Revert
    │     │
    │     └──► If ALL pass ──► Update state, return success
    │            │
    │            ▼
    │         VolumePolicy updates cumulative volume ✅
    │         VolumeRatePolicy updates rate counter ✅
    │
    └─ Complete transfer
```

### Flow 3: Rule Approach - Multi-Rule Validation

```
User calls token.transfer()
    │
    ▼
CMTAT Token._transfer()
    │
    ▼
RuleEngine.validateTransfer()
    │
    ├─ Iterate through all rules (AND logic)
    │
    ├──► Rule 1: WhitelistRule.validateTransfer()
    │    ├─ Check if sender/recipient whitelisted
    │    └─ Return true/false
    │
    ├──► Rule 2: ACERule.validateTransfer()
    │    │
    │    ├─ Construct payload
    │    │
    │    ▼
    │    PolicyEngine.check(payload)
    │    │
    │    ├─ Execute ACE policies
    │    │
    │    └─ Return true/false
    │
    ├──► Rule 3: ConditionalTransferRule.validateTransfer()
    │    ├─ Check custom conditions
    │    └─ Return true/false
    │
    └─ If ALL rules return true ──► Allow transfer
       If ANY rule returns false ──► Reject transfer
```

---

## Capabilities Matrix

### Feature Comparison

| Feature | Adapter v2.3.0 | Adapter v3.0+ | Rule v2.3.0 | Rule v3.0+ |
|---------|----------------|---------------|-------------|------------|
| **Architecture** |
| Drop-in replacement | ✅ | ✅ | ❌ | ❌ |
| Works with RuleEngine | ❌ | ❌ | ✅ | ✅ |
| Token-specific | ✅ | ✅ | ❌ | ❌ |
| Token-agnostic | ❌ | ❌ | ✅ | ✅ |
| **Validation** |
| validateTransfer() | ✅ VIEW | ✅ VIEW | ✅ VIEW | ✅ VIEW |
| operateOnTransfer() | ❌ | ✅ | ❌ | ✅ |
| PolicyEngine.check() | ✅ | ✅ | ✅ | ✅ |
| PolicyEngine.run() | ❌ | ✅ | ❌ | ✅ |
| **Policies** |
| Read-only policies | ✅ | ✅ | ✅ | ✅ |
| VolumePolicy | ⚠️ Read | ✅ Track | ⚠️ Read | ✅ Track |
| VolumeRatePolicy | ⚠️ Read | ✅ Track | ⚠️ Read | ✅ Track |
| postRun() hooks | ❌ | ✅ | ❌ | ✅ |
| **Integration** |
| Preserves existing rules | ❌ | ❌ | ✅ | ✅ |
| Multi-rule composition | ❌ | ❌ | ✅ | ✅ |
| Non-destructive | ❌ | ❌ | ✅ | ✅ |
| **Gas & Cost** |
| Gas efficiency | High | High | Medium | Medium |
| Deployment cost | Per token | Per token | Shared | Shared |
| **Use Cases** |
| Greenfield | ✅✅ | ✅✅ | ⚠️ | ⚠️ |
| Brownfield | ⚠️ | ⚠️ | ✅✅ | ✅✅ |
| Simple compliance | ✅✅ | ✅✅ | ✅ | ✅ |
| Complex compliance | ⚠️ | ⚠️ | ✅✅ | ✅✅ |

Legend:
- ✅ Fully supported
- ✅✅ Highly recommended
- ⚠️ Limited/partial support
- ❌ Not supported

---

## Decision Framework

### Decision Tree

```
Start: Need to integrate ACE with CMTAT?
    │
    ▼
Do you have EXISTING compliance rules to preserve?
    │
    ├─ YES ──► Use RULE APPROACH (2A or 2B)
    │           │
    │           ▼
    │        CMTAT version?
    │           │
    │           ├─ v2.3.0 ──► ACERule (2A)
    │           └─ v3.0+  ──► ACERule_v3 (2B)
    │
    └─ NO ───► Use ADAPTER APPROACH (1A or 1B)
                │
                ▼
             Need stateful policies?
                │
                ├─ YES ──► MUST use v3.0+ ──► ACERuleEngineAdapter_v3 (1B)
                │
                └─ NO  ──► CMTAT version?
                            │
                            ├─ v2.3.0 ──► ACERuleEngineAdapter (1A)
                            └─ v3.0+  ──► ACERuleEngineAdapter_v3 (1B)
```

### Recommendation Matrix

| Your Situation | Recommended Option | Reason |
|----------------|-------------------|---------|
| New token, simple compliance | 1A or 1B | Simplest, lowest gas |
| New token, need VolumePolicy | 1B | Stateful support required |
| Existing token, want to keep rules | 2A or 2B | Non-destructive |
| Existing token, need stateful | 2B | Stateful + composition |
| Multiple tokens, shared compliance | 2A or 2B | Token-agnostic deployment |
| High-frequency trading | 1A or 1B | Lower gas costs |
| Complex multi-rule framework | 2A or 2B | Flexible composition |
| Risk-averse production | 2A or 2B | Gradual migration |

---

## Migration Paths

### Path 1: v2.3.0 Adapter → v3.0+ Adapter

**Scenario**: Upgrade existing ACERuleEngineAdapter deployment to v3.0+

```
Current:
  CMTAT v2.3.0 → ACERuleEngineAdapter

Target:
  CMTAT v3.0+ → ACERuleEngineAdapter_v3

Steps:
  1. Upgrade CMTAT token to v3.0+
  2. Deploy ACERuleEngineAdapter_v3
  3. Migrate policies to new adapter
  4. Call token.setRuleEngine(newAdapter)
  5. Test stateful policies
```

### Path 2: v2.3.0 Adapter → v3.0+ Rule

**Scenario**: Migrate from adapter to rule approach for flexibility

```
Current:
  CMTAT v2.3.0 → ACERuleEngineAdapter

Target:
  CMTAT v3.0+ → RuleEngine → ACERule_v3
                            → Other Rules

Steps:
  1. Upgrade CMTAT token to v3.0+
  2. Deploy RuleEngine v3.0+
  3. Deploy ACERule_v3
  4. Add ACERule_v3 to RuleEngine
  5. Add other compliance rules
  6. Reconfigure policies (RuleEngine address)
  7. Call token.setRuleEngine(ruleEngine)
```

### Path 3: v2.3.0 Rule → v3.0+ Rule

**Scenario**: Upgrade ACERule to support stateful policies

```
Current:
  CMTAT v2.3.0 → RuleEngine v1 → ACERule
                                → Other Rules

Target:
  CMTAT v3.0+ → RuleEngine v3 → ACERule_v3
                               → Other Rules

Steps:
  1. Upgrade CMTAT token to v3.0+
  2. Upgrade RuleEngine to v3.0+
  3. Deploy ACERule_v3
  4. Replace old ACERule with ACERule_v3
  5. Test stateful policies
```

### Path 4: No ACE → Rule (Non-Destructive)

**Scenario**: Add ACE to existing multi-rule system

```
Current:
  CMTAT → RuleEngine → WhitelistRule
                     → ConditionalTransferRule

Target:
  CMTAT → RuleEngine → WhitelistRule
                     → ConditionalTransferRule
                     → ACERule (NEW!)

Steps:
  1. Deploy ACERule (or ACERule_v3)
  2. Configure PolicyEngine
  3. Register policies against RuleEngine
  4. Call ruleEngine.addRule(aceRule)
  5. Test combined validation
```

---

## Summary

This architecture provides a comprehensive, flexible solution for integrating Chainlink ACE with CMTAT tokens:

- **4 distinct options** covering all deployment scenarios
- **Token-agnostic design** for Rule approach (unique innovation)
- **Backward compatible** with CMTAT v2.3.0
- **Future-ready** for CMTAT v3.0+ stateful features
- **Non-destructive migration** paths available
- **Clear decision framework** for choosing the right option

For specific integration workflows and migration scripts, see the `docs/integration/` directory.
