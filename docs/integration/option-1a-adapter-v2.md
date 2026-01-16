# Option 1A: ACERuleEngineAdapter (CMTAT v2.3.0)

## Overview

**Option 1A** uses `ACERuleEngineAdapter` as a **drop-in replacement** for CMTAT v2.3.0's RuleEngine, providing direct integration with ACE PolicyEngine.

### When to Use

✅ **Best for**:
- New CMTAT v2.3.0 token deployments
- Full migration to ACE (no existing rules to preserve)
- Maximum gas efficiency
- Simple compliance requirements

⚠️ **Limitations**:
- View-only validation (no stateful policies)
- Cannot preserve existing compliance rules
- Token-specific deployment (one adapter per token)
- VolumePolicy and VolumeRatePolicy won't track state

### Architecture

```
CMTAT Token v2.3.0
    ↓
ACERuleEngineAdapter
    ↓
ACE PolicyEngine.check() [VIEW only]
```

---

## Pre-requisites

### Required Components

- [ ] CMTAT v2.3.0 token (deployed or ready to deploy)
- [ ] ACE PolicyEngine (deployed)
- [ ] ACE Policies (AllowPolicy, MaxPolicy, etc.)
- [ ] Deployment wallet with sufficient funds
- [ ] Admin access to CMTAT token (to call `setRuleEngine`)

### Verify Versions

```bash
# Check CMTAT version
cast call $CMTAT_TOKEN "version()(string)" --rpc-url $RPC_URL

# Expected output: "2.3.0" or similar
```

---

## Step-by-Step Integration

### Step 1: Deploy CMTATTransferExtractor

The extractor parses transfer parameters for ACE PolicyEngine.

```solidity
// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import {CMTATTransferExtractor} from "src/extractors/CMTATTransferExtractor.sol";

contract DeployExtractor {
    function run() external returns (address) {
        CMTATTransferExtractor extractor = new CMTATTransferExtractor();
        return address(extractor);
    }
}
```

**Deploy Command**:
```bash
forge script script/deploy/DeployExtractor.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

**Save the address**:
```bash
export EXTRACTOR_ADDRESS=0x...
```

### Step 2: Deploy ACERuleEngineAdapter

Deploy the adapter with references to PolicyEngine, token, and extractor.

**Deployment Script**:
```solidity
// script/deploy/adapter/DeployAdapter_v2.s.sol
// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {ACERuleEngineAdapter} from "src/adapter/ACERuleEngineAdapter.sol";

contract DeployAdapter_v2 is Script {
    function run() external returns (address) {
        address policyEngine = vm.envAddress("POLICY_ENGINE_ADDRESS");
        address cmtatToken = vm.envAddress("CMTAT_TOKEN_ADDRESS");
        address extractor = vm.envAddress("EXTRACTOR_ADDRESS");
        address owner = vm.envAddress("ADAPTER_OWNER");

        vm.startBroadcast();
        
        ACERuleEngineAdapter adapter = new ACERuleEngineAdapter(
            policyEngine,
            cmtatToken,    // ← Token-specific!
            extractor,
            owner
        );
        
        console.log("ACERuleEngineAdapter deployed:", address(adapter));
        console.log("  PolicyEngine:", policyEngine);
        console.log("  Target Token:", cmtatToken);
        console.log("  Extractor:", extractor);
        console.log("  Owner:", owner);
        
        vm.stopBroadcast();
        
        return address(adapter);
    }
}
```

**Deploy Command**:
```bash
# Set environment variables
export POLICY_ENGINE_ADDRESS=0x...
export CMTAT_TOKEN_ADDRESS=0x...
export EXTRACTOR_ADDRESS=0x...
export ADAPTER_OWNER=0x...
export RPC_URL=https://...
export PRIVATE_KEY=0x...

# Deploy
forge script script/deploy/adapter/DeployAdapter_v2.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# Save address
export ADAPTER_ADDRESS=0x...
```

### Step 3: Configure ACE PolicyEngine

Register the extractor and add policies.

**Configuration Script**:
```solidity
// script/integration/adapter/ConfigurePolicyEngine.s.sol
// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

contract ConfigurePolicyEngine is Script {
    bytes4 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    bytes4 constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 constant VALIDATE_TRANSFER_SELECTOR = bytes4(keccak256("validateTransfer(address,address,uint256)"));
    
    function run() external {
        address policyEngine = vm.envAddress("POLICY_ENGINE_ADDRESS");
        address extractor = vm.envAddress("EXTRACTOR_ADDRESS");
        address cmtatToken = vm.envAddress("CMTAT_TOKEN_ADDRESS");
        address allowPolicy = vm.envAddress("ALLOW_POLICY_ADDRESS");
        
        vm.startBroadcast();
        
        IPolicyEngine pe = IPolicyEngine(policyEngine);
        
        // Step 1: Set extractor for all transfer selectors
        console.log("Setting extractors...");
        pe.setExtractor(TRANSFER_SELECTOR, extractor);
        pe.setExtractor(TRANSFER_FROM_SELECTOR, extractor);
        pe.setExtractor(VALIDATE_TRANSFER_SELECTOR, extractor);
        console.log("  ✓ Extractors configured");
        
        // Step 2: Add policies (targeting TOKEN address)
        console.log("Adding policies...");
        pe.addPolicy(
            cmtatToken,           // ← Target is TOKEN address
            TRANSFER_SELECTOR,
            allowPolicy,
            new bytes32[](0)      // Policy parameters
        );
        console.log("  ✓ Policies added for token:", cmtatToken);
        
        vm.stopBroadcast();
        
        console.log("\nConfiguration complete!");
    }
}
```

**Run Configuration**:
```bash
export ALLOW_POLICY_ADDRESS=0x...  # Your ACE AllowPolicy

forge script script/integration/adapter/ConfigurePolicyEngine.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 4: Set Adapter as RuleEngine

Replace the token's RuleEngine with the adapter.

**Integration Script**:
```solidity
// script/integration/adapter/SetRuleEngine.s.sol
// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import "forge-std/Script.sol";

interface ICMTAT {
    function setRuleEngine(address ruleEngine) external;
    function ruleEngine() external view returns (address);
}

contract SetRuleEngine is Script {
    function run() external {
        address cmtatToken = vm.envAddress("CMTAT_TOKEN_ADDRESS");
        address adapter = vm.envAddress("ADAPTER_ADDRESS");
        
        ICMTAT token = ICMTAT(cmtatToken);
        
        console.log("Current RuleEngine:", token.ruleEngine());
        console.log("New Adapter:", adapter);
        
        vm.startBroadcast();
        
        // Set adapter as RuleEngine
        token.setRuleEngine(adapter);
        
        vm.stopBroadcast();
        
        console.log("✓ RuleEngine updated to:", token.ruleEngine());
        console.log("\nIntegration complete!");
    }
}
```

**Run Integration**:
```bash
forge script script/integration/adapter/SetRuleEngine.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 5: Verify Integration

Test the integration with sample transfers.

**Verification Script**:
```solidity
// script/integration/adapter/VerifyIntegration.s.sol
// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.26;

import "forge-std/Script.sol";

interface ICMTAT {
    function validateTransfer(address from, address to, uint256 amount) external view returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract VerifyIntegration is Script {
    function run() external view {
        address cmtatToken = vm.envAddress("CMTAT_TOKEN_ADDRESS");
        address testRecipient = vm.envAddress("TEST_RECIPIENT");
        
        ICMTAT token = ICMTAT(cmtatToken);
        
        console.log("Testing integration...");
        console.log("Token:", cmtatToken);
        console.log("Recipient:", testRecipient);
        
        // Test validation
        bool allowed = token.validateTransfer(
            msg.sender,
            testRecipient,
            1 ether
        );
        
        console.log("Validation result:", allowed);
        
        if (allowed) {
            console.log("✓ Transfer would be allowed by ACE policies");
        } else {
            console.log("✗ Transfer would be rejected by ACE policies");
        }
    }
}
```

**Run Verification**:
```bash
export TEST_RECIPIENT=0x...

forge script script/integration/adapter/VerifyIntegration.s.sol \
  --rpc-url $RPC_URL
```

---

## Migration Scenarios

### Scenario 1: New Token Deployment

**Steps**:
1. Deploy CMTAT v2.3.0 token (without RuleEngine)
2. Deploy ACERuleEngineAdapter
3. Configure PolicyEngine
4. Set adapter as RuleEngine
5. Test transfers

### Scenario 2: Existing Token with Old RuleEngine

**Steps**:
1. Deploy ACERuleEngineAdapter
2. Configure PolicyEngine with equivalent policies
3. **Test thoroughly in staging**
4. Call `token.setRuleEngine(adapterAddress)`
5. Monitor first transfers closely
6. **Keep old RuleEngine address for rollback**

**Rollback Procedure**:
```solidity
// If issues arise, revert to old RuleEngine
token.setRuleEngine(oldRuleEngineAddress);
```

### Scenario 3: Multiple Tokens

For multiple CMTAT tokens, repeat the process:

1. Deploy **one adapter per token**
2. Configure policies for each token address
3. Set each token's RuleEngine

**Cost Consideration**: Each token requires a separate adapter deployment.

---

## Policy Examples

### Example 1: AllowPolicy (Whitelist)

```solidity
// Configure whitelist policy
address[] memory allowedAddresses = new address[](3);
allowedAddresses[0] = 0xAlice;
allowedAddresses[1] = 0xBob;
allowedAddresses[2] = 0xCharlie;

policyEngine.addPolicy(
    cmtatTokenAddress,
    transferSelector,
    allowPolicyAddress,
    abi.encode(allowedAddresses)
);
```

### Example 2: MaxPolicy (Amount Limit)

```solidity
// Set maximum transfer amount
uint256 maxAmount = 1000 ether;

policyEngine.addPolicy(
    cmtatTokenAddress,
    transferSelector,
    maxPolicyAddress,
    abi.encode(maxAmount)
);
```

### Example 3: PausePolicy

```solidity
// Add pausable transfers
policyEngine.addPolicy(
    cmtatTokenAddress,
    transferSelector,
    pausePolicyAddress,
    new bytes32[](0)
);

// Later, pause transfers
IPausePolicy(pausePolicyAddress).pause();
```

---

## Testing Checklist

Before going to production:

- [ ] Test successful transfers with allowed addresses
- [ ] Test rejected transfers with blocked addresses
- [ ] Test amount limits work correctly
- [ ] Test pause/unpause functionality
- [ ] Test gas costs are acceptable
- [ ] Verify restriction messages are clear
- [ ] Test with edge cases (zero amounts, max uint256)
- [ ] Monitor events for policy rejections
- [ ] Have rollback plan ready

---

## Troubleshooting

### Issue: Transfers Always Revert

**Possible Causes**:
1. Policies not configured correctly
2. Extractor not set for selector
3. Policy address incorrect

**Solution**:
```bash
# Check extractor
cast call $POLICY_ENGINE "getExtractor(bytes4)(address)" $TRANSFER_SELECTOR

# Check policies
cast call $POLICY_ENGINE "getPolicies(address,bytes4)(address[])" $TOKEN $TRANSFER_SELECTOR
```

### Issue: Transfers Always Succeed (Bypassing ACE)

**Possible Causes**:
1. Adapter not set as RuleEngine
2. Wrong adapter address

**Solution**:
```bash
# Verify RuleEngine
cast call $CMTAT_TOKEN "ruleEngine()(address)"
# Should return adapter address
```

### Issue: Gas Costs Too High

**Solutions**:
1. Optimize policy count
2. Use simpler policies
3. Consider caching results off-chain

---

## Limitations to Remember

### View-Only Validation

⚠️ **CRITICAL**: CMTAT v2.3.0's `validateTransfer()` is VIEW-only.

**Impacts**:
- ❌ VolumePolicy won't track cumulative volume
- ❌ VolumeRatePolicy won't enforce rates
- ❌ postRun() hooks won't execute
- ❌ State-modifying policies won't work

**Workarounds**:
1. Use static MaxPolicy instead of VolumePolicy
2. Track volumes off-chain
3. Upgrade to CMTAT v3.0+ (Option 1B)

---

## Next Steps

After successful integration:

1. **Monitor**: Watch transfer events and policy rejections
2. **Optimize**: Tune policies based on usage patterns
3. **Document**: Update your compliance documentation
4. **Consider Upgrade**: Evaluate CMTAT v3.0+ for stateful policies (Option 1B)

## Support

- 📖 [Architecture Documentation](../ARCHITECTURE.md)
- 🐛 Open GitHub issue for problems
