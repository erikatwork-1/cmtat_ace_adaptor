# Option 1B: ACE Adapter for CMTAT v3.0+ Integration Guide

## Overview

**Option 1B** uses `ACERuleEngineAdapter_v3` as a **drop-in replacement** for the CMTAT v3.0+ RuleEngine, with **full stateful operation support**.

### Quick Facts

| Property | Value |
|----------|-------|
| **Contract** | `ACERuleEngineAdapter_v3` |
| **CMTAT Version** | v3.0+ |
| **Architecture** | Direct replacement |
| **Deployment** | One per token (token-specific) |
| **Returns** | `uint8` restriction codes |
| **Stateful Support** | ✅ Full support (VolumePolicy, VolumeRatePolicy) |
| **Best For** | Greenfield deployments with stateful policies |

### Key Enhancement Over 1A

```
┌─────────────────────────────────────────────────────────┐
│ Option 1A (v2.3.0)     │ Option 1B (v3.0+)            │
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
│              ACERuleEngineAdapter_v3                          │
│                (RuleEngine Interface)                         │
│                                                                │
│  validateTransfer(from, to, amount) → uint8                   │
│      └─► policyEngine.check() ──────────────┐                │
│           (view-only)                        │                │
│                                              │                │
│  operateOnTransfer(from, to, amount) → uint8 │                │
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
                                               │
                                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    ACE Policies                               │
│                                                                │
│  ✅ AllowPolicy, RejectPolicy, MaxPolicy                      │
│  ✅ VolumePolicy (cumulative tracking)                        │
│  ✅ VolumeRatePolicy (rate limiting)                          │
│  ✅ PausePolicy, OnlyOwnerPolicy                              │
│  ✅ All postRun() hooks execute                               │
└──────────────────────────────────────────────────────────────┘
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

### Step 1: Deploy ACERuleEngineAdapter_v3

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ACERuleEngineAdapter_v3} from "src/adapter/ACERuleEngineAdapter_v3.sol";
import {CMTATTransferExtractor} from "src/extractors/CMTATTransferExtractor.sol";

contract DeployAdapter_v3 {
    function run() external returns (ACERuleEngineAdapter_v3) {
        address policyEngine = 0x...; // Your PolicyEngine
        address cmtatToken = 0x...;   // Your CMTAT v3.0+ token
        address owner = msg.sender;
        
        // Deploy extractor (can be shared across adapters)
        CMTATTransferExtractor extractor = new CMTATTransferExtractor();
        
        // Deploy adapter_v3
        ACERuleEngineAdapter_v3 adapter = new ACERuleEngineAdapter_v3(
            policyEngine,
            cmtatToken,
            address(extractor),
            owner
        );
        
        return adapter;
    }
}
```

### Step 2: Configure CMTAT Token

```solidity
// Set ACERuleEngineAdapter_v3 as the RuleEngine
cmtatToken.setRuleEngine(address(adapter));

// Verify integration
require(cmtatToken.ruleEngine() == address(adapter), "Integration failed");
```

### Step 3: Register ACE Policies

**Critical**: Policies must be registered against the **token address**, not the adapter.

```solidity
// Example: Register VolumePolicy for daily limit
bytes4 transferSelector = bytes4(keccak256("transfer(address,uint256)"));

policyEngine.addPolicy(
    cmtatToken,              // ← Token address
    transferSelector,
    volumePolicyAddress,
    abi.encode(
        1000000 ether,       // Daily volume limit
        86400                // 24 hour window
    )
);

// Example: Register VolumeRatePolicy
policyEngine.addPolicy(
    cmtatToken,
    transferSelector,
    volumeRatePolicyAddress,
    abi.encode(
        100 ether,           // Rate per minute
        60                   // Time window in seconds
    )
);
```

### Step 4: Test Integration

```solidity
function testIntegration() public {
    // Mint tokens
    cmtatToken.mint(alice, 1000 ether);
    
    // Test view validation (check)
    bool isValid = adapter.validateTransfer(alice, bob, 100 ether);
    require(isValid, "Validation failed");
    
    // Test stateful operation (run)
    uint8 code = adapter.operateOnTransfer(alice, bob, 100 ether);
    require(code == 0, "Operation failed");
    
    // Perform actual transfer
    vm.prank(alice);
    cmtatToken.transfer(bob, 100 ether);
    
    // Verify balances
    assertEq(cmtatToken.balanceOf(bob), 100 ether);
}
```

---

## Configuration Examples

### Example 1: Volume Tracking

```solidity
// Deploy VolumePolicy
VolumePolicy volumePolicy = new VolumePolicy();

// Configure: 1M daily volume limit per address
policyEngine.addPolicy(
    address(cmtatToken),
    bytes4(keccak256("transfer(address,uint256)")),
    address(volumePolicy),
    abi.encode(
        1000000 ether,    // maxVolume
        86400,            // window (24 hours)
        true              // perAddress
    )
);

// Now transfers will accumulate volume
// First transfer: 100 ETH used / 1M ETH limit
cmtatToken.transfer(bob, 100 ether);

// Second transfer: 300 ETH used / 1M ETH limit
cmtatToken.transfer(bob, 200 ether);

// If cumulative exceeds 1M ETH in 24h → REJECT
```

### Example 2: Rate Limiting

```solidity
// Deploy VolumeRatePolicy
VolumeRatePolicy ratePolicy = new VolumeRatePolicy();

// Configure: Max 10 ETH per minute
policyEngine.addPolicy(
    address(cmtatToken),
    bytes4(keccak256("transfer(address,uint256)")),
    address(ratePolicy),
    abi.encode(
        10 ether,         // maxRate
        60                // window (1 minute)
    )
);

// Transfers within rate limit succeed
cmtatToken.transfer(bob, 5 ether);   // OK: 5/10 used
cmtatToken.transfer(charlie, 4 ether); // OK: 9/10 used

// Exceeding rate limit fails
cmtatToken.transfer(dave, 2 ether);  // FAIL: Would be 11/10
```

### Example 3: Combined Policies

```solidity
// Register multiple stateful policies
bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));

// 1. Volume limit: 1M daily
policyEngine.addPolicy(
    address(cmtatToken),
    selector,
    address(volumePolicy),
    abi.encode(1000000 ether, 86400, false)
);

// 2. Rate limit: 100 ETH/minute
policyEngine.addPolicy(
    address(cmtatToken),
    selector,
    address(ratePolicy),
    abi.encode(100 ether, 60)
);

// 3. KYC check
policyEngine.addPolicy(
    address(cmtatToken),
    selector,
    address(kycPolicy),
    abi.encode()
);

// ALL policies must pass, and state updates for volume/rate
```

---

## Migration Scenarios

### Scenario 1: Upgrade from Option 1A (v2.3.0 → v3.0+)

**Objective**: Migrate from ACERuleEngineAdapter (v2.3.0) to ACERuleEngineAdapter_v3 to enable stateful policies.

#### Step 1: Upgrade CMTAT Token

```solidity
// Deploy new CMTAT v3.0+ token (or upgrade existing via proxy)
CMTATv3 newToken = new CMTATv3("Security Token", "SEC");
```

#### Step 2: Deploy Adapter_v3

```solidity
ACERuleEngineAdapter_v3 newAdapter = new ACERuleEngineAdapter_v3(
    policyEngine,
    address(newToken),
    address(extractor),
    owner
);
```

#### Step 3: Migrate State

```solidity
// Copy holder balances from old token to new token
// (Requires privileged migration logic)
uint256 holderCount = oldToken.holderCount();
for (uint256 i = 0; i < holderCount; i++) {
    address holder = oldToken.holderAt(i);
    uint256 balance = oldToken.balanceOf(holder);
    newToken.mint(holder, balance);
}
```

#### Step 4: Switch RuleEngine

```solidity
// Set new adapter as RuleEngine
newToken.setRuleEngine(address(newAdapter));
```

#### Step 5: Update Policies

```solidity
// Re-register policies for new token
// NOW you can add stateful policies!
bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));

policyEngine.addPolicy(
    address(newToken),        // New token
    selector,
    address(volumePolicy),    // NOW this will track state!
    abi.encode(1000000 ether, 86400, false)
);
```

### Scenario 2: Greenfield Deployment

**Objective**: Deploy new CMTAT v3.0+ token with ACERuleEngineAdapter_v3 from scratch.

```solidity
// 1. Deploy token
CMTATv3 token = new CMTATv3("New Token", "NEW");

// 2. Deploy adapter_v3
ACERuleEngineAdapter_v3 adapter = new ACERuleEngineAdapter_v3(
    policyEngine,
    address(token),
    address(extractor),
    owner
);

// 3. Set as RuleEngine
token.setRuleEngine(address(adapter));

// 4. Register stateful policies
policyEngine.addPolicy(
    address(token),
    bytes4(keccak256("transfer(address,uint256)")),
    address(volumePolicy),
    abi.encode(1000000 ether, 86400, false)
);

// 5. Mint and transfer
token.mint(alice, 1000 ether);
token.transfer(bob, 100 ether); // Stateful validation!
```

---

## Policy Examples

### VolumePolicy Configuration

```solidity
// Policy: Daily volume limit of 10M tokens
struct VolumeConfig {
    uint256 maxVolume;     // 10,000,000 ether
    uint256 window;        // 86400 (24 hours)
    bool perAddress;       // false (global) or true (per address)
}

policyEngine.addPolicy(
    address(cmtatToken),
    transferSelector,
    address(volumePolicy),
    abi.encode(10_000_000 ether, 86400, false)
);
```

**Behavior**:
- Tracks cumulative transfer volume over 24-hour rolling window
- Rejects transfers that would exceed 10M token limit
- State resets after window expires

### VolumeRatePolicy Configuration

```solidity
// Policy: Max 1000 tokens per minute
struct RateConfig {
    uint256 maxRate;       // 1000 ether
    uint256 window;        // 60 seconds
}

policyEngine.addPolicy(
    address(cmtatToken),
    transferSelector,
    address(volumeRatePolicy),
    abi.encode(1000 ether, 60)
);
```

**Behavior**:
- Tracks transfer rate over 1-minute rolling window
- Rejects transfers that would exceed 1000 tokens/minute
- Prevents rapid trading or suspicious activity

### postRun() Hook Example

```solidity
contract NotificationHook {
    event LargeTransfer(address indexed from, address indexed to, uint256 amount);
    
    function postRun(bytes memory context) external {
        // Decode transfer parameters
        (address from, address to, uint256 amount) = abi.decode(
            context,
            (address, address, uint256)
        );
        
        // Emit notification for large transfers
        if (amount > 100000 ether) {
            emit LargeTransfer(from, to, amount);
        }
    }
}

// Register hook
policyEngine.registerPostRunHook(
    address(cmtatToken),
    transferSelector,
    address(notificationHook)
);
```

---

## Testing

### Unit Test Example

```solidity
// test/unit/ACERuleEngineAdapter_v3.t.sol

function test_OperateOnTransfer_UpdatesVolumeState() public {
    // Deploy with VolumePolicy
    VolumePolicy volumePolicy = new VolumePolicy();
    
    policyEngine.addPolicy(
        address(token),
        bytes4(keccak256("transfer(address,uint256)")),
        address(volumePolicy),
        abi.encode(1000 ether, 86400, false)
    );
    
    // First transfer: 100 used
    uint8 code1 = adapter.operateOnTransfer(alice, bob, 100 ether);
    assertEq(code1, 0); // Success
    
    // Second transfer: 300 used
    uint8 code2 = adapter.operateOnTransfer(alice, charlie, 200 ether);
    assertEq(code2, 0); // Success
    
    // Third transfer: Would exceed 1000
    uint8 code3 = adapter.operateOnTransfer(alice, dave, 800 ether);
    assertEq(code3, 1); // Rejected
}
```

### Integration Test Example

```solidity
// test/integration/Adapter_v3_Integration.t.sol

function test_FullTransferFlow_WithStatefulPolicies() public {
    // Setup VolumePolicy
    policyEngine.addPolicy(
        address(token),
        bytes4(keccak256("transfer(address,uint256)")),
        address(volumePolicy),
        abi.encode(500 ether, 86400, true) // 500 per address per day
    );
    
    // Alice transfers within limit
    vm.prank(alice);
    token.transfer(bob, 100 ether);
    assertEq(token.balanceOf(bob), 100 ether);
    
    // Alice transfers more (still within 500)
    vm.prank(alice);
    token.transfer(bob, 200 ether);
    assertEq(token.balanceOf(bob), 300 ether);
    
    // Alice tries to exceed daily limit
    vm.prank(alice);
    vm.expectRevert(); // Should fail
    token.transfer(bob, 300 ether);
}
```

---

## Comparison: 1A vs 1B

| Feature | 1A (v2.3.0) | 1B (v3.0+) |
|---------|-------------|------------|
| **CMTAT Version** | v2.3.0 | v3.0+ |
| **validateTransfer()** | ✅ check() | ✅ check() |
| **operateOnTransfer()** | ❌ Not available | ✅ run() |
| **VolumePolicy** | ⚠️ Reads only | ✅ Tracks state |
| **VolumeRatePolicy** | ⚠️ Reads only | ✅ Tracks state |
| **postRun() hooks** | ❌ Never execute | ✅ Always execute |
| **Stateful policies** | ❌ Won't update | ✅ Fully functional |
| **Use case** | Simple compliance | Advanced compliance |

---

## Troubleshooting

### Issue: "Function operateOnTransfer not found"

**Cause**: CMTAT token is v2.3.0, not v3.0+.

**Solution**: Upgrade to CMTAT v3.0+ or use Option 1A (ACERuleEngineAdapter).

### Issue: VolumePolicy not tracking state

**Cause**: Using validateTransfer() instead of operateOnTransfer().

**Solution**: Ensure CMTAT v3.0+ calls operateOnTransfer() in _transfer().

### Issue: Higher gas costs than v2.3.0

**Explanation**: Stateful operations (run()) cost more gas than view operations (check()) due to state updates.

**Solution**: This is expected. Stateful policies require storage writes.

---

## Best Practices

1. **Use operateOnTransfer()** for all stateful policy enforcement
2. **Keep validateTransfer()** as a quick preliminary check
3. **Monitor gas costs** for state-heavy policies
4. **Test volume limits** thoroughly before production
5. **Use appropriate time windows** for rate limiting (not too short)
6. **Register policies per token** (not per adapter)
7. **Version control** your policy parameters

---

## Next Steps

- Review [Option 2B (ACE Rule v3.0+)](./option-2b-rule-v3.md) for composable alternative
- See [ARCHITECTURE.md](../ARCHITECTURE.md) for design details
- Check [TEST_SUMMARY.md](../../TEST_SUMMARY.md) for test coverage
- Refer to [README.md](./README.md) for commands and quick reference

---

## Summary

**Option 1B (ACERuleEngineAdapter_v3)** provides:

✅ Full stateful policy support  
✅ VolumePolicy and VolumeRatePolicy tracking  
✅ postRun() hook execution  
✅ Drop-in replacement for CMTAT v3.0+ RuleEngine  
✅ Complete ACE policy suite compatibility  

**Best for**: Greenfield deployments requiring advanced compliance features with stateful validation.

For questions or assistance, please consult the main [README.md](../../README.md) or open an issue.
