# Resolver Update Guide for Simplified Contracts

## Overview
This guide details the necessary updates to transform the existing bmn-evm-resolver to work with the new simplified contract architecture. The focus is on reducing complexity while maintaining atomic swap functionality.

## Key Changes Summary

### Contract Changes
- **Old**: Separate EscrowSrc/EscrowDst contracts with complex phases
- **New**: Single SimpleEscrow contract for both sides
- **Old**: 7-stage timelock system with multiple phases
- **New**: Single timeout timestamp
- **Old**: Complex factory with 1inch callbacks required
- **New**: Direct creation + optional 1inch compatibility

### Resolver Architecture Changes
- Simplified state management (no complex phases)
- Direct escrow creation without 1inch dependency
- Cleaner event monitoring
- Lightning Network integration support

## File-by-File Update Guide

### 1. Update Contract ABIs (/abis/)

Replace existing ABIs with new simplified versions:

```typescript
// SimpleEscrow.json - New unified escrow ABI
{
  "abi": [
    "constructor(address token, address sender, address recipient, bytes32 hashlock, uint256 timelock)",
    "function fund(uint256 amount)",
    "function withdraw(bytes32 preimage)",
    "function refund()",
    "function getDetails() view returns (tuple(address token, address sender, address recipient, bytes32 hashlock, uint256 timelock, uint256 amount, bool funded, bool withdrawn, bool refunded, bytes32 preimage))",
    "event EscrowFunded(address indexed sender, uint256 amount, address token)",
    "event EscrowWithdrawn(address indexed recipient, bytes32 preimage, uint256 amount)",
    "event EscrowRefunded(address indexed sender, uint256 amount)"
  ]
}

// SimpleEscrowFactory.json - New factory ABI
{
  "abi": [
    "function createEscrow(address token, address sender, address recipient, bytes32 hashlock, uint256 timelock, bytes32 salt) returns (address)",
    "function computeEscrowAddress(address token, address sender, address recipient, bytes32 hashlock, uint256 timelock, bytes32 salt) view returns (address)",
    "event EscrowCreated(address indexed escrow, address indexed sender, address indexed recipient, address token, bytes32 hashlock, uint256 timelock, uint256 chainId, bytes32 salt)"
  ]
}
```

### 2. Update Types (/src/types/)

#### atomic-swap.ts - Simplified Types
```typescript
// Remove complex types, use simple ones
export interface SimpleEscrowParams {
  token: Address;
  sender: Address;
  recipient: Address;
  hashlock: Hex;
  timelock: bigint;
  amount: bigint;
}

export interface SwapState {
  escrowAddress: Address;
  funded: boolean;
  withdrawn: boolean;
  refunded: boolean;
  preimage?: Hex;
}

// Remove all the complex phase enums and timelock structures
```

#### order.ts - Keep but Simplify
```typescript
export interface AtomicSwapData {
  hashlock: Hex;
  crossChainRecipient: Address;
  timeoutDuration: number; // seconds
  destinationChainId: number;
  salt: Hex;
}

// Keep CrossChainOrder interface but update escrow fields
```

### 3. Update Configuration (/src/config/)

#### contracts.ts - New Contract Addresses
```typescript
export const CONTRACT_ADDRESSES = {
  [CHAIN_ID.ETHEREUM]: {
    simpleEscrowFactory: "0x...", // New factory address
    oneInchAdapter: "0x...",      // Optional adapter
    lightningBridge: "0x...",      // Lightning integration
  },
  [CHAIN_ID.POLYGON]: {
    simpleEscrowFactory: "0x...",
    oneInchAdapter: "0x...",
    lightningBridge: "0x...",
  },
};

// Remove old escrow factory and complex contract addresses
```

### 4. Update Alice Order Creation (/src/alice/)

#### create-order.ts - Simplify Order Creation
```typescript
export async function createAtomicSwapOrder(params: {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  amountOut: bigint;
  recipient: Address;
  chainIdOut: number;
}) {
  // Generate secret and hashlock
  const secret = generateSecret();
  const hashlock = keccak256(secret);
  
  // Create atomic swap extension data
  const atomicSwapData: AtomicSwapData = {
    hashlock,
    crossChainRecipient: params.recipient,
    timeoutDuration: 3600, // 1 hour
    destinationChainId: params.chainIdOut,
    salt: generateSalt(),
  };
  
  // For direct path (no 1inch)
  const escrowParams = {
    token: params.tokenIn,
    sender: await wallet.account.address,
    recipient: RESOLVER_ADDRESS,
    hashlock,
    timelock: BigInt(Math.floor(Date.now() / 1000) + 3600),
  };
  
  return { escrowParams, secret, atomicSwapData };
}
```

### 5. Update Resolver Core (/src/resolver/)

#### executor.ts - Simplified Execution Logic
```typescript
export class SimplifiedAtomicSwapExecutor {
  async executeSwap(order: CrossChainOrder): Promise<void> {
    // Step 1: Create source escrow
    const srcEscrow = await this.createEscrow(
      order.srcChain,
      order.srcToken,
      order.maker,
      this.resolverAddress,
      order.hashlock,
      order.srcTimeout
    );
    
    // Step 2: Create destination escrow
    const dstEscrow = await this.createEscrow(
      order.dstChain,
      order.dstToken,
      this.resolverAddress,
      order.taker,
      order.hashlock,
      order.dstTimeout
    );
    
    // Step 3: Fund source escrow (Alice already funded)
    // Step 4: Fund destination escrow
    await this.fundEscrow(order.dstChain, dstEscrow, order.dstAmount);
    
    // Step 5: Withdraw from source with secret
    await this.withdrawFromEscrow(order.srcChain, srcEscrow, order.secret);
    
    // Step 6: Alice can now withdraw from destination
    // (she observes the revealed secret)
  }
  
  async createEscrow(
    chainId: number,
    token: Address,
    sender: Address,
    recipient: Address,
    hashlock: Hex,
    timelock: bigint
  ): Promise<Address> {
    const factory = this.getFactory(chainId);
    const salt = generateSalt();
    
    const tx = await factory.write.createEscrow([
      token,
      sender,
      recipient,
      hashlock,
      timelock,
      salt
    ]);
    
    // Get escrow address from event
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash: tx });
    const event = parseEventLogs(receipt.logs, factory.abi, 'EscrowCreated')[0];
    
    return event.args.escrow;
  }
  
  async withdrawFromEscrow(
    chainId: number,
    escrowAddress: Address,
    secret: Hex
  ): Promise<void> {
    const escrow = this.getEscrow(chainId, escrowAddress);
    await escrow.write.withdraw([secret]);
  }
}
```

#### monitor.ts - Simplified Monitoring
```typescript
export class SimplifiedOrderMonitor {
  async startMonitoring(): Promise<void> {
    // Monitor for EscrowCreated events
    this.factory.watchEvent.EscrowCreated({
      onLogs: (logs) => {
        for (const log of logs) {
          this.handleNewEscrow(log.args);
        }
      },
    });
    
    // Monitor for withdrawals to get revealed secrets
    this.watchForWithdrawals();
  }
  
  async handleNewEscrow(args: {
    escrow: Address;
    sender: Address;
    recipient: Address;
    hashlock: Hex;
    timelock: bigint;
  }): Promise<void> {
    // Check if this is for us (resolver is recipient)
    if (args.recipient !== this.resolverAddress) return;
    
    // Check if profitable and execute
    if (await this.isProfitable(args)) {
      await this.executor.executeSwap({
        srcEscrow: args.escrow,
        hashlock: args.hashlock,
        // ... map to order format
      });
    }
  }
}
```

### 6. Add Lightning Support (/src/lightning/)

#### lightning-service.ts - New Lightning Integration
```typescript
import { Invoice, LightningClient } from '@radar/lnrpc';

export class LightningService {
  private client: LightningClient;
  
  async createHTLCInvoice(
    paymentHash: Buffer,
    amountSats: number
  ): Promise<string> {
    const invoice = await this.client.addInvoice({
      rHash: paymentHash,
      value: amountSats,
      expiry: 3600,
      memo: 'Bridge-Me-Not Atomic Swap',
    });
    
    return invoice.paymentRequest;
  }
  
  async waitForPayment(paymentHash: Buffer): Promise<Buffer> {
    // Subscribe to invoice updates
    const stream = this.client.subscribeInvoices({ rHash: paymentHash });
    
    return new Promise((resolve) => {
      stream.on('data', (invoice) => {
        if (invoice.settled) {
          resolve(invoice.rPreimage);
          stream.cancel();
        }
      });
    });
  }
  
  async payInvoice(paymentRequest: string): Promise<Buffer> {
    const result = await this.client.sendPaymentSync({
      paymentRequest,
    });
    
    if (result.paymentError) {
      throw new Error(result.paymentError);
    }
    
    return result.paymentPreimage;
  }
}
```

#### lightning-resolver.ts - Lightning Atomic Swap Handler
```typescript
export class LightningResolver {
  async handleEVMToLightning(
    evmEscrow: Address,
    paymentHash: Hex,
    satoshiAmount: number
  ): Promise<void> {
    // Create Lightning invoice
    const invoice = await this.lightning.createHTLCInvoice(
      hexToBuffer(paymentHash),
      satoshiAmount
    );
    
    console.log(`Lightning invoice created: ${invoice}`);
    
    // Wait for payment
    const preimage = await this.lightning.waitForPayment(
      hexToBuffer(paymentHash)
    );
    
    // Withdraw from EVM escrow
    await this.withdrawFromEscrow(evmEscrow, bufferToHex(preimage));
  }
  
  async handleLightningToEVM(
    invoice: string,
    evmToken: Address,
    evmAmount: bigint,
    recipient: Address
  ): Promise<void> {
    // Decode invoice
    const decoded = await this.lightning.decodeInvoice(invoice);
    const paymentHash = bufferToHex(decoded.paymentHash);
    
    // Create EVM escrow
    const escrow = await this.createEscrow({
      token: evmToken,
      recipient,
      hashlock: paymentHash,
      amount: evmAmount,
    });
    
    // Fund escrow
    await this.fundEscrow(escrow, evmAmount);
    
    // Pay Lightning invoice
    const preimage = await this.lightning.payInvoice(invoice);
    
    console.log(`Lightning paid, preimage: ${bufferToHex(preimage)}`);
  }
}
```

### 7. Update State Management (/src/state/)

#### Simplify State Structure
```typescript
export interface SimplifiedSwapState {
  orderId: string;
  status: 'pending' | 'funded' | 'completed' | 'expired';
  srcEscrow?: Address;
  dstEscrow?: Address;
  secret?: Hex;
  preimage?: Hex;
  createdAt: number;
  
  // Remove complex phase tracking
}

export class SimplifiedStateManager {
  async updateSwapStatus(orderId: string, status: SwapStatus): Promise<void> {
    const state = await this.getState(orderId);
    state.status = status;
    await this.saveState(orderId, state);
  }
  
  // Remove complex state transition logic
}
```

### 8. Update Utils (/src/utils/)

#### Add Lightning Utilities
```typescript
// lightning.ts
export function hexToBuffer(hex: Hex): Buffer {
  return Buffer.from(hex.slice(2), 'hex');
}

export function bufferToHex(buffer: Buffer): Hex {
  return `0x${buffer.toString('hex')}` as Hex;
}

export function decodeLightningInvoice(invoice: string): {
  paymentHash: Buffer;
  amount: number;
  expiry: number;
} {
  // Implement BOLT11 invoice decoding
  // Or use a library like @node-lightning/invoice
}
```

## Testing the Updated Resolver

### 1. Unit Tests to Update
```typescript
// Test simple escrow creation
describe('SimpleEscrowFactory', () => {
  it('should create escrow with correct parameters', async () => {
    const escrow = await factory.createEscrow(...);
    expect(escrow).toMatch(/^0x[a-fA-F0-9]{40}$/);
  });
  
  it('should compute deterministic addresses', async () => {
    const computed = await factory.computeEscrowAddress(...);
    const actual = await factory.createEscrow(...);
    expect(computed).toBe(actual);
  });
});
```

### 2. Integration Tests
```typescript
// Test full atomic swap flow
describe('Atomic Swap Flow', () => {
  it('should complete EVM to EVM swap', async () => {
    // Create orders on both chains
    // Fund escrows
    // Execute swap
    // Verify completion
  });
  
  it('should handle timeout and refund', async () => {
    // Create escrow
    // Wait for timeout
    // Execute refund
    // Verify state
  });
});
```

### 3. Lightning Tests
```typescript
describe('Lightning Integration', () => {
  it('should complete EVM to Lightning swap', async () => {
    // Mock Lightning invoice creation
    // Create EVM escrow
    // Simulate Lightning payment
    // Verify withdrawal
  });
});
```

## Migration Checklist

- [ ] Update all contract ABIs
- [ ] Simplify type definitions
- [ ] Update contract addresses in config
- [ ] Refactor Alice order creation
- [ ] Simplify resolver executor
- [ ] Update monitoring logic
- [ ] Add Lightning service
- [ ] Simplify state management
- [ ] Update utility functions
- [ ] Write new tests
- [ ] Test with local chains
- [ ] Test Lightning integration

## Key Benefits After Update

1. **Simpler Code**: ~60% less code in resolver
2. **Easier Testing**: No complex state machines
3. **Faster Execution**: Fewer transactions needed
4. **Lightning Ready**: Direct integration path
5. **Better Debugging**: Clearer flow and state

## Common Issues and Solutions

### Issue: Secret/Preimage Format
- Always use consistent encoding (hex with 0x prefix)
- Convert between Buffer and hex for Lightning

### Issue: Timeout Coordination
- Source chain timeout > Destination chain timeout
- Add buffer for network delays (5-10 minutes)

### Issue: Gas Estimation
- SimpleEscrow uses less gas than old system
- Can use fixed gas limits for demo

### Issue: Event Monitoring
- Fewer events to monitor
- Use indexed fields for efficient filtering

Remember: The goal is a working demo. Focus on core functionality first, optimize later!