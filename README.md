# CMTAT-ACE Integration

A comprehensive integration solution that connects **CMTAT (Capital Markets and Technology Association)** tokens with **Chainlink's ACE (Access Control Engine)** PolicyEngine, offering **4 distinct implementation options** for maximum flexibility.

## 🎯 Quick Overview

This project enables seamless integration of ACE's powerful policy framework with CMTAT tokens, supporting both new deployments and existing systems. Choose from 4 implementation options based on your needs:

### The 4-Option Matrix

| Option | Approach | Version | Best For | Contract |
|--------|----------|---------|----------|----------|
| **1A** | Adapter (Replacement) | CMTAT v2.3.0 | ACE as sole compliance layer | `ACERuleEngineAdapter` |
| **1B** | Adapter (Replacement) | CMTAT v3.0+ | ACE sole layer + stateful policies | `ACERuleEngineAdapter_v3` |
| **2A** | Rule (Composition) | CMTAT v2.3.0 | ACE + preserve other rules | `ACERule` |
| **2B** | Rule (Composition) | CMTAT v3.0+ | ACE + other rules + stateful | `ACERule_v3` |

## 🚀 Quick Start

### Installation

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/your-org/cmtat-ace-adapter.git
cd cmtat-ace-adapter

# Install dependencies
forge install

# Build
forge build

# Test
forge test
```

### Choose Your Integration Path

#### Option 1: Adapter Approach (Replacement)

**When to use**: ACE as the sole compliance layer. Works with new OR existing tokens via `setRuleEngine()`. Use when you don't need to preserve other rules.

```solidity
// Deploy adapter for your token
ACERuleEngineAdapter adapter = new ACERuleEngineAdapter(
    policyEngineAddress,
    cmtatTokenAddress,    // Token-specific
    extractorAddress,
    ownerAddress
);

// Replace RuleEngine
cmtatToken.setRuleEngine(address(adapter));

// Register policies against token
policyEngine.addPolicy(cmtatTokenAddress, selector, policy, params);
```

**Architecture**:
```
CMTAT Token → ACERuleEngineAdapter → ACE PolicyEngine
```

#### Option 2: Rule Approach (Composition)

**When to use**: Add ACE alongside existing rules (non-destructive). Essential when you need to preserve other compliance rules like whitelists, holding periods, etc.

```solidity
// Deploy ACERule (works with any token!)
ACERule aceRule = new ACERule(
    policyEngineAddress,
    extractorAddress
    // NO token address - reusable!
);

// Add to existing RuleEngine (non-destructive)
ruleEngine.addRule(address(aceRule));

// Register policies against RuleEngine
policyEngine.addPolicy(ruleEngineAddress, selector, policy, params);
```

**Architecture**:
```
CMTAT Token → RuleEngine → ACERule → ACE PolicyEngine
                         → WhitelistRule
                         → Other Rules
```

## 📊 Feature Comparison

| Feature | Adapter (1A/1B) | Rule (2A/2B) |
|---------|-----------------|--------------|
| **Integration** | Replaces entire RuleEngine | Adds to existing RuleEngine |
| **Deployment** | Token-specific | Token-agnostic (reusable) |
| **Gas Cost** | Lower (direct) | Slightly higher (one hop) |
| **Existing Rules** | ⚠️ Replaces all rules | ✅ Preserves all rules |
| **Works with existing tokens** | ✅ Yes (via `setRuleEngine`) | ✅ Yes (via `addRule`) |
| **Reversible** | ✅ Yes (switch back) | ✅ Yes (remove rule) |
| **Use Case** | ACE-only compliance | Multi-rule compliance |
| **Complexity** | Simpler | More flexible |

### Version Comparison: v2.3.0 vs v3.0+

| Capability | v2.3.0 (1A/2A) | v3.0+ (1B/2B) |
|------------|----------------|---------------|
| Read-only policies | ✅ | ✅ |
| VolumePolicy | ⚠️ Reads only | ✅ Full tracking |
| VolumeRatePolicy | ⚠️ Reads only | ✅ Full limiting |
| postRun() hooks | ❌ | ✅ |
| State updates | ❌ | ✅ |

## 📖 Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed design, capabilities, and decision framework
- **[IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md)** - Implementation status and testing results
- **[Integration Workflows](docs/integration/)** - Step-by-step guides for each option
  - [Option 1A: Adapter v2.3.0](docs/integration/option-1a-adapter-v2.md)
  - [Option 1B: Adapter v3.0+](docs/integration/option-1b-adapter-v3.md)
  - [Option 2A: Rule v2.3.0](docs/integration/option-2a-rule-v2.md)
  - [Option 2B: Rule v3.0+](docs/integration/option-2b-rule-v3.md)

## 🎓 How to Choose

### Decision Tree

```
Do you need to preserve existing compliance rules?
├─ YES → Use Rule Approach (2A or 2B)
│        └─ Need stateful policies? → Use v3.0+ (2B)
│
└─ NO (ACE as sole compliance layer) → Use Adapter Approach (1A or 1B)
         └─ Need stateful policies? → Use v3.0+ (1B)

Note: Both approaches work with new AND existing tokens!
- Adapter: Call token.setRuleEngine(adapterAddress)
- Rule: Call ruleEngine.addRule(aceRuleAddress)
```

### Common Scenarios

| Your Situation | Recommended | Why |
|----------------|-------------|-----|
| ACE as only compliance layer | **1A or 1B** | Simplest, lowest gas, direct integration |
| Need VolumePolicy/VolumeRatePolicy | **1B or 2B** | Requires v3.0+ stateful support |
| Have existing rules to preserve | **2A or 2B** | Non-destructive, keeps all rules |
| Multiple tokens, shared policies | **2A or 2B** | Token-agnostic, one deployment |
| Risk-averse production | **2A or 2B** | Reversible, doesn't replace anything |
| Existing token, ACE-only desired | **1A or 1B** | Use `setRuleEngine()` to switch |

## 🛠️ Project Structure

```
cmtat-ace-adapter/
├── src/
│   ├── ACERuleEngineAdapter.sol           # Option 1A
│   ├── adapter/
│   │   └── ACERuleEngineAdapter_v3.sol    # Option 1B
│   ├── rule/
│   │   ├── ACERule.sol                    # Option 2A
│   │   └── ACERule_v3.sol                 # Option 2B
│   ├── extractors/
│   │   └── CMTATTransferExtractor.sol     # Shared
│   └── interfaces/
│       ├── IACERuleEngineAdapter.sol
│       ├── IACERule.sol
│       └── IACERule_v3.sol
├── test/
│   ├── unit/
│   │   ├── ACERuleEngineAdapter.t.sol     # 32 tests ✅
│   │   └── ACERule.t.sol                  # 32 tests ✅
│   └── integration/
│       ├── CMTATIntegration.t.sol
│       ├── PolicyIntegration.t.sol
│       └── ViewLimitation.t.sol
├── script/
│   └── Deploy.s.sol
└── docs/
    ├── ARCHITECTURE.md                    # Detailed design docs
    ├── IMPLEMENTATION_SUMMARY.md          # Status & results
    └── integration/                       # Integration guides
        ├── option-1a-adapter-v2.md
        ├── option-1b-adapter-v3.md
        ├── option-2a-rule-v2.md
        └── option-2b-rule-v3.md
```

## ✅ Testing

All core contracts are fully tested:

```bash
# Run all tests
forge test

# Run specific option tests
forge test --match-contract ACERuleEngineAdapterTest  # Option 1A
forge test --match-contract ACERuleTest                # Option 2A

# Run with gas reporting
forge test --gas-report

# Run with verbosity
forge test -vvv
```

**Test Results**:
- ✅ ACERuleEngineAdapter: 32/32 tests passing
- ✅ ACERule: 32/32 tests passing
- ✅ >95% code coverage

## 🔑 Key Features

### Token-Agnostic Rule Design

The **ACERule** contracts (Options 2A and 2B) use an innovative token-agnostic design:

- **Reusable**: One deployment works with multiple CMTAT tokens
- **Cost-efficient**: Shared deployment reduces costs
- **RuleEngine-centric**: Policies registered against RuleEngine, not individual tokens
- **Composable**: Works seamlessly with other compliance rules

### Stateful Policy Support (v3.0+)

Options 1B and 2B unlock full ACE capabilities:

- ✅ VolumePolicy with cumulative tracking
- ✅ VolumeRatePolicy with rate limiting
- ✅ postRun() hooks execution
- ✅ State-modifying operations
- ✅ All ACE policies fully functional

## 🔧 Configuration Examples

### Adapter Configuration (Options 1A/1B)

```solidity
// Configure extractor
policyEngine.setExtractor(transferSelector, extractorAddress);

// Add policies (targeting token)
policyEngine.addPolicy(
    cmtatTokenAddress,        // ← Token address
    transferSelector,
    allowPolicyAddress,
    abi.encode(allowedAddresses)
);

// Set adapter
cmtatToken.setRuleEngine(adapterAddress);
```

### Rule Configuration (Options 2A/2B)

```solidity
// Configure extractor
policyEngine.setExtractor(transferSelector, extractorAddress);

// Add policies (targeting RuleEngine)
policyEngine.addPolicy(
    ruleEngineAddress,        // ← RuleEngine address
    transferSelector,
    allowPolicyAddress,
    abi.encode(allowedAddresses)
);

// Add rule (non-destructive)
ruleEngine.addRule(aceRuleAddress);
```

## 🌐 Compatible Policies

### All Versions (1A, 1B, 2A, 2B)

- AllowPolicy (whitelist/blacklist)
- RejectPolicy
- MaxPolicy
- IntervalPolicy
- PausePolicy
- OnlyOwnerPolicy
- BypassPolicy
- RoleBasedAccessControlPolicy
- CredentialRegistryIdentityValidatorPolicy

### v3.0+ Only (1B, 2B)

- **VolumePolicy** - Tracks cumulative transfer volumes
- **VolumeRatePolicy** - Enforces rate limits with time windows

## 📝 License

- Adapter code: MPL-2.0 (matching CMTAT)
- Chainlink ACE: BUSL-1.1

## 🔗 References

- [CMTAT Repository](https://github.com/CMTA/CMTAT)
- [CMTAT RuleEngine](https://github.com/CMTA/RuleEngine)
- [Chainlink ACE](https://github.com/smartcontractkit/chainlink-ace)
- [EIP-1404: Simple Restricted Token Standard](https://eips.ethereum.org/EIPS/eip-1404)

## 🤝 Support

For questions, integration help, or issues:
- 📖 Read the [Architecture Documentation](docs/ARCHITECTURE.md)
- 📋 Check [Integration Workflows](docs/integration/)
- 🐛 Open a GitHub issue
- 💬 Contact the development team

## 🎯 Next Steps

1. **Read** [ARCHITECTURE.md](docs/ARCHITECTURE.md) to understand design choices
2. **Choose** your option using the decision tree above
3. **Follow** the integration workflow in `docs/integration/`
4. **Test** thoroughly in a staging environment
5. **Deploy** with confidence

---

## ⚠️ Disclaimer

**THIS CODE IS FOR TESTING, RESEARCH, AND DEMONSTRATION PURPOSES ONLY.**

### Important Notices

1. **Not Production-Ready**: This code is experimental, unaudited, and NOT intended for production or commercial use.

2. **No Official Endorsement**: This is an independent integration adapter built on top of existing open-source protocols. It is NOT an official integration or endorsement by CMTA or Chainlink.

3. **No Warranty**: The code is provided "AS IS", WITHOUT WARRANTY OF ANY KIND, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and noninfringement.

4. **No Liability**: The authors and contributors accept NO LIABILITY for any loss, damage, or consequences arising from the use of this code, including but not limited to financial losses, security breaches, or compliance violations.

5. **Commercial Use**: Any commercial or production use may require:
   - Separate licenses from underlying projects
   - Security audits
   - Legal review
   - Explicit permissions from CMTA and Chainlink
   
   **Please consult with CMTA and Chainlink** regarding licensing, permissions, and any commercial use requirements before deploying this code in production.

6. **Your Responsibility**: Users are solely responsible for:
   - Code review and security audits
   - Compliance with applicable laws and regulations
   - Understanding and accepting all risks
   - Obtaining necessary permissions and licenses

### Recommended Actions Before Production Use

- ✅ Conduct thorough security audits
- ✅ Review CMTA and Chainlink licensing terms
- ✅ Obtain explicit permissions for commercial use
- ✅ Perform extensive testing in staging environments
- ✅ Consult legal and compliance advisors
- ✅ Implement proper monitoring and incident response

---

**Built with ❤️ for the CMTAT and Chainlink ACE ecosystems**
