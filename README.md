# CMTAT-ACE Integration

An integration solution that connects **CMTAT (Capital Markets and Technology Association)** tokens with **Chainlink's ACE (Automated Compliance Engine)** PolicyEngine for transfer compliance enforcement in security tokens.

## Overview

This project provides integration between CMTAT tokens and Chainlink ACE PolicyEngine, enabling flexible compliance policies for token transfers. The solution supports both existing and new CMTAT token deployments.

## Integration Approaches

The project implements **two integration approaches**, each available for **two CMTAT versions**:

### Adapter Approach
- **Description**: ACE PolicyEngine replaces the entire CMTAT RuleEngine, providing direct ACE control over token transfers
- **Use Case**: When ACE is the sole compliance layer needed
- **Benefits**: Simplest integration, lowest gas cost, direct ACE policy enforcement
- **Versions Available**:
  - **CMTAT v2.3.0**: Supports read-only ACE policies (AllowPolicy, RejectPolicy, MaxPolicy, IntervalPolicy, etc.)
  - **CMTAT v3.0+**: Full ACE capabilities including stateful policies (VolumePolicy, VolumeRatePolicy) and postRun() hooks

### Rule Approach
- **Description**: ACE PolicyEngine acts as one rule within the existing CMTAT RuleEngine, allowing composition with other compliance rules
- **Use Case**: When you need to preserve existing compliance rules alongside ACE policies
- **Benefits**: Non-destructive integration, token-agnostic deployment (one instance serves multiple tokens), composable with other rules
- **Versions Available**:
  - **CMTAT v2.3.0**: Supports read-only ACE policies alongside existing rules
  - **CMTAT v3.0+**: Full ACE capabilities including stateful policies, working in composition with other rules

## Key Concepts

- **CMTAT Tokens**: Security tokens following the Capital Markets and Technology Association standard
- **Chainlink ACE**: Automated Compliance Engine providing policy-based compliance enforcement
- **RuleEngine**: CMTAT's compliance framework that orchestrates multiple rules
- **Adapter Pattern**: Direct replacement of RuleEngine with ACE PolicyEngine
- **Rule Pattern**: ACE integrated as one rule within the existing RuleEngine
- **Read-only Policies**: Policies that validate transfers without modifying state (v2.3.0)
- **Stateful Policies**: Policies that track state and modify storage (v3.0+ only)

## Implementation Details

### Contracts

**Adapter Approach Contracts**:
- `ACERuleEngineAdapter` - For CMTAT v2.3.0 (read-only policies)
- `ACERuleEngineAdapter_v3` - For CMTAT v3.0+ (stateful policies)

**Rule Approach Contracts**:
- `ACERule` - For CMTAT v2.3.0 (read-only policies, token-agnostic)
- `ACERule_v3` - For CMTAT v3.0+ (stateful policies, token-agnostic)

**Shared Components**:
- `CMTATTransferExtractor` - Extracts transfer parameters for ACE PolicyEngine

### Integration Methods

**For Existing Tokens**:
- **Adapter**: Use `token.setRuleEngine(adapterAddress)` to replace existing RuleEngine
- **Rule**: Use `ruleEngine.addRule(aceRuleAddress)` to add ACE alongside existing rules

**For New Tokens**:
- **Adapter**: Deploy adapter and set as RuleEngine during token initialization
- **Rule**: Deploy ACERule and add to RuleEngine during token setup

## Quick Start

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/erikatwork-1/cmtat_ace_adaptor.git
cd cmtat_ace_adaptor

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

## Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed architecture, design decisions, and technical specifications
- **[Integration Workflows](docs/integration/)** - Step-by-step integration guides:
  - [Adapter for CMTAT v2.3.0](docs/integration/option-1a-adapter-v2.md)
  - [Adapter for CMTAT v3.0+](docs/integration/option-1b-adapter-v3.md)
  - [Rule for CMTAT v2.3.0](docs/integration/option-2a-rule-v2.md)
  - [Rule for CMTAT v3.0+](docs/integration/option-2b-rule-v3.md)

## Features

- ✅ **Works with existing tokens**: Both approaches support existing CMTAT deployments
- ✅ **Token-agnostic rules**: Rule approach allows one deployment to serve multiple tokens
- ✅ **Full ACE policy support**: Compatible with all ACE policies (AllowPolicy, RejectPolicy, MaxPolicy, VolumePolicy, VolumeRatePolicy, etc.)
- ✅ **Version compatibility**: Supports CMTAT v2.3.0 and v3.0+
- ✅ **Composable compliance**: Rule approach preserves existing compliance rules
- ✅ **Stateful policies**: v3.0+ versions support VolumePolicy and VolumeRatePolicy with state tracking

## Testing

All implementations are fully tested with:
- Unit tests for each contract
- Integration tests with CMTAT tokens
- Multi-rule composition tests
- Gas optimization verification

## Related Projects

- [CMTAT Repository](https://github.com/CMTA/CMTAT) - CMTAT token standard implementation
- [CMTAT RuleEngine](https://github.com/CMTA/RuleEngine) - CMTAT compliance rule framework
- [Chainlink ACE](https://github.com/smartcontractkit/chainlink-ace) - Chainlink Automated Compliance Engine
- [EIP-1404](https://eips.ethereum.org/EIPS/eip-1404) - Simple Restricted Token Standard

## License

- Integration code: MPL-2.0 (matching CMTAT license)
- Chainlink ACE: BUSL-1.1

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
