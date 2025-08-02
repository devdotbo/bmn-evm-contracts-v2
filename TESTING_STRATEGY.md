# Testing Strategy for Simplified Atomic Swaps

## Overview
This document outlines a practical testing approach focused on getting a working demo for the hackathon. We prioritize essential functionality over comprehensive coverage.

## Testing Philosophy for Hackathon
- **Test the happy path thoroughly**
- **Test critical failure modes**
- **Skip edge cases that won't appear in demo**
- **Focus on integration over unit tests**
- **Use mainnet forks for realistic testing**

## Essential Test Coverage

### 1. SimpleEscrow Core Tests

#### Happy Path Tests
```solidity
// test/SimpleEscrow.t.sol
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/SimpleEscrow.sol";
import "../contracts/mocks/MockERC20.sol";

contract SimpleEscrowTest is Test {
    SimpleEscrow escrow;
    MockERC20 token;
    
    address alice = address(0x1);
    address bob = address(0x2);
    bytes32 secret = keccak256("secret123");
    bytes32 hashlock = keccak256(abi.encode(secret));
    uint256 amount = 100e18;
    
    function setUp() public {
        token = new MockERC20("Test", "TEST");
        
        escrow = new SimpleEscrow(
            address(token),
            alice,
            bob,
            hashlock,
            block.timestamp + 1 hours
        );
        
        // Give Alice tokens
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(escrow), amount);
    }
    
    function testSuccessfulAtomicSwap() public {
        // Alice funds
        vm.prank(alice);
        escrow.fund(amount);
        assertEq(token.balanceOf(address(escrow)), amount);
        
        // Bob withdraws with secret
        vm.prank(bob);
        escrow.withdraw(secret);
        
        // Verify
        assertEq(token.balanceOf(bob), amount);
        assertEq(escrow.preimage(), secret);
        assertTrue(escrow.withdrawn());
    }
    
    function testRefundAfterTimeout() public {
        // Fund
        vm.prank(alice);
        escrow.fund(amount);
        
        // Fast forward past timeout
        vm.warp(block.timestamp + 2 hours);
        
        // Refund
        vm.prank(alice);
        escrow.refund();
        
        // Verify
        assertEq(token.balanceOf(alice), amount);
        assertTrue(escrow.refunded());
    }
    
    function testCannotWithdrawWithWrongSecret() public {
        vm.prank(alice);
        escrow.fund(amount);
        
        bytes32 wrongSecret = keccak256("wrong");
        
        vm.expectRevert("Invalid secret");
        escrow.withdraw(wrongSecret);
    }
}
```

### 2. Factory Integration Tests

#### Cross-Chain Coordination Test
```solidity
// test/CrossChainIntegration.t.sol
contract CrossChainIntegrationTest is Test {
    SimpleEscrowFactory factoryChain1;
    SimpleEscrowFactory factoryChain2;
    
    function testDeterministicAddresses() public {
        // Same parameters
        bytes32 salt = keccak256("test-salt");
        address token = address(0x123);
        
        // Compute on chain 1
        address computed1 = factoryChain1.computeEscrowAddress(
            token, alice, bob, hashlock, timeout, salt
        );
        
        // Compute on chain 2  
        address computed2 = factoryChain2.computeEscrowAddress(
            token, alice, bob, hashlock, timeout, salt
        );
        
        // Should be same
        assertEq(computed1, computed2);
    }
    
    function testAtomicSwapFlow() public {
        // Alice creates on chain 1
        address escrow1 = factoryChain1.createEscrow(...);
        
        // Bob creates on chain 2
        address escrow2 = factoryChain2.createEscrow(...);
        
        // Both fund
        SimpleEscrow(escrow1).fund(amount1);
        SimpleEscrow(escrow2).fund(amount2);
        
        // Bob reveals secret on chain 1
        SimpleEscrow(escrow1).withdraw(secret);
        
        // Alice uses revealed secret on chain 2
        bytes32 revealedSecret = SimpleEscrow(escrow1).preimage();
        SimpleEscrow(escrow2).withdraw(revealedSecret);
        
        // Both should have received funds
        assertTrue(SimpleEscrow(escrow1).withdrawn());
        assertTrue(SimpleEscrow(escrow2).withdrawn());
    }
}
```

### 3. 1inch Integration Tests

```solidity
// test/OneInchIntegration.t.sol
contract OneInchIntegrationTest is Test {
    OneInchAdapter adapter;
    ILimitOrderProtocol limitOrderProtocol;
    
    function test1inchOrderCreatesEscrow() public {
        // Create order with atomic swap extension
        IOrderMixin.Order memory order = _createOrder();
        bytes memory extension = _encodeExtension();
        bytes memory signature = _signOrder(order);
        
        // Fill order through 1inch
        vm.prank(taker);
        limitOrderProtocol.fillOrder(
            order,
            signature, 
            makingAmount,
            takingAmount,
            extension
        );
        
        // Verify escrow was created
        address expectedEscrow = factory.computeEscrowAddress(...);
        assertTrue(factory.isEscrowDeployed(expectedEscrow));
        
        // Verify escrow is funded
        assertTrue(SimpleEscrow(expectedEscrow).funded());
    }
}
```

### 4. Lightning Integration Tests

```solidity
// test/LightningIntegration.t.sol
contract LightningIntegrationTest is Test {
    LightningBridge bridge;
    
    // Mock Lightning responses
    function testEVMToLightning() public {
        // Create EVM escrow
        bytes32 paymentHash = keccak256("payment");
        
        vm.prank(alice);
        address escrow = bridge.initiateEVMToLightning(
            address(token),
            100e18,
            100000, // satoshis
            paymentHash,
            block.timestamp + 1 hours
        );
        
        // Fund escrow
        SimpleEscrow(escrow).fund(100e18);
        
        // Simulate Lightning payment
        bytes32 preimage = "secret123";
        vm.prank(resolver);
        bridge.confirmLightningPayment(paymentHash, preimage);
        
        // Verify state
        LightningBridge.LightningSwap memory swap = bridge.getSwapDetails(paymentHash);
        assertEq(swap.state, LightningBridge.SwapState.LightningPaid);
        assertEq(swap.preimage, preimage);
    }
}
```

## Integration Test Scenarios

### Scenario 1: Basic EVM to EVM Swap
```typescript
// test/scenarios/basic-swap.ts
describe("Basic Atomic Swap", () => {
  it("completes swap between Ethereum and Polygon", async () => {
    // 1. Alice creates order
    const order = await alice.createAtomicSwapOrder({
      tokenIn: USDC_ETH,
      amountIn: parseUnits("100", 6),
      tokenOut: USDC_POLYGON,
      amountOut: parseUnits("100", 6),
    });
    
    // 2. Resolver picks up order
    await resolver.start();
    
    // 3. Wait for completion
    await waitForSwapCompletion(order.id);
    
    // 4. Verify balances
    expect(await getBalance(bob, USDC_ETH)).to.equal(parseUnits("100", 6));
    expect(await getBalance(alice, USDC_POLYGON)).to.equal(parseUnits("100", 6));
  });
});
```

### Scenario 2: Lightning Bridge Test
```typescript
describe("Lightning Bridge", () => {
  it("swaps USDC for Lightning payment", async () => {
    // 1. Create Lightning invoice
    const invoice = await lightning.createInvoice(100000); // 100k sats
    
    // 2. Initiate swap
    const swap = await bridge.initiateLightningToEVM(
      invoice,
      USDC_ADDRESS,
      parseUnits("100", 6),
      alice.address
    );
    
    // 3. Resolver handles the swap
    await resolver.handleLightningSwap(swap.id);
    
    // 4. Verify completion
    expect(await bridge.swapState(swap.id)).to.equal("Completed");
  });
});
```

## Quick Testing Commands

### Run Core Tests
```bash
# Quick unit tests
forge test --match-contract SimpleEscrowTest -vv

# Integration tests
forge test --match-contract CrossChainIntegrationTest -vv

# Gas report
forge test --gas-report
```

### Fork Testing
```bash
# Test on mainnet fork
forge test --fork-url $ETH_RPC_URL --match-test testMainnetIntegration

# Test on Polygon fork
forge test --fork-url $POLYGON_RPC_URL --match-test testPolygonIntegration
```

### Lightning Testing
```bash
# Start Lightning regtest
polar start test-network

# Run Lightning tests
deno test test/lightning.test.ts
```

## Testing Checklist for Demo

### Must Test Before Demo
- [ ] Basic atomic swap completes
- [ ] Timeout and refund works
- [ ] Cross-chain address prediction
- [ ] 1inch order creates escrow
- [ ] Resolver detects and executes swaps
- [ ] Lightning invoice creation
- [ ] At least one Lightning swap

### Nice to Test (If Time)
- [ ] Multiple concurrent swaps
- [ ] Different token types
- [ ] Gas optimization
- [ ] Error recovery
- [ ] Performance under load

### Skip for Hackathon
- ❌ Extensive fuzzing
- ❌ Formal verification
- ❌ 100% code coverage
- ❌ All edge cases
- ❌ Security audit tests

## Demo Test Script

```bash
#!/bin/bash
# test-demo.sh - Quick demo validation

echo "🧪 Testing demo flow..."

# 1. Deploy contracts
./scripts/deploy-local.sh

# 2. Run basic tests
forge test --match-test testSuccessfulAtomicSwap -vv

# 3. Test resolver
cd ../bmn-evm-resolver
deno test test/resolver.test.ts

# 4. Integration test
deno run scripts/demo-atomic-swap.ts

echo "✅ Demo tests passed!"
```

## Common Test Issues and Fixes

### Issue: Timestamp drift between chains
```solidity
// Add buffer in tests
uint256 timeout = block.timestamp + 1 hours + 5 minutes; // buffer
```

### Issue: Gas estimation failures
```solidity
// Use fixed gas in tests
vm.txGasPrice(20 gwei);
```

### Issue: Event filtering
```solidity
// Use vm.expectEmit for precise event testing
vm.expectEmit(true, true, false, true);
emit EscrowCreated(escrow, sender, recipient, token, hashlock, timelock, chainId, salt);
```

## Lightning Test Utilities

```typescript
// test/utils/lightning.ts
export class MockLightningNode {
  async createInvoice(amount: number): Promise<string> {
    // Create deterministic invoice for testing
    const paymentHash = createHash('sha256')
      .update('test' + amount)
      .digest();
    
    return encodeBolt11({
      paymentHash,
      amount,
      expiry: 3600,
    });
  }
  
  async payInvoice(invoice: string): Promise<Buffer> {
    // Simulate payment
    const decoded = decodeBolt11(invoice);
    const preimage = Buffer.from('test-preimage');
    
    // Verify hash
    const hash = createHash('sha256').update(preimage).digest();
    assert(hash.equals(decoded.paymentHash));
    
    return preimage;
  }
}
```

## Performance Benchmarks

### Gas Usage Targets
| Operation | Target Gas | Current Implementation |
|-----------|-----------|----------------------|
| Create Escrow | < 200k | ~150k |
| Fund Escrow | < 100k | ~80k |
| Withdraw | < 100k | ~90k |
| Factory Deploy | < 300k | ~250k |

### Speed Targets
- Atomic swap completion: < 2 minutes
- Lightning swap: < 30 seconds
- Cross-chain coordination: < 5 minutes

## Testing Priority for Hackathon

1. **Critical (Must Work)**
   - Basic atomic swap flow
   - Secret revelation and withdrawal
   - Cross-chain coordination

2. **Important (Should Work)**
   - 1inch integration
   - Timeout handling
   - Basic Lightning flow

3. **Nice to Have (If Time)**
   - Gas optimization
   - Concurrent swaps
   - Advanced Lightning scenarios

Remember: **A working demo is better than perfect tests!** Focus on the critical path and ensure the demo scenarios work reliably.