# Lightning Network Integration Guide for Bridge-Me-Not

## 🌩️ Overview: EVM ↔ Lightning ↔ EVM Atomic Swaps

### The Vision
Enable atomic swaps between any EVM chain and Bitcoin Lightning Network, creating a universal cross-chain liquidity bridge.

### Why Lightning?
- **Instant Settlement**: Lightning HTLCs settle in seconds
- **Low Fees**: Fraction of a cent per transaction
- **Bitcoin Liquidity**: Access to largest crypto liquidity pool
- **True Atomic**: Same HTLC mechanism as on-chain swaps

## 🏗️ Architecture

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│   EVM Chain A   │         │Lightning Network│         │   EVM Chain B   │
│                 │         │                 │         │                 │
│  SimpleEscrow   │◄────────┤  HTLC Invoice   ├────────►│  SimpleEscrow   │
│  (hashlock X)   │         │  (hashlock X)   │         │  (hashlock X)   │
└─────────────────┘         └─────────────────┘         └─────────────────┘
        ↑                           ↑                            ↑
        └───────────────────────────┴────────────────────────────┘
                          Same preimage unlocks all
```

## 📋 Implementation Steps

### Step 1: Lightning Node Setup (30 mins)

#### Option A: Use Polar (Recommended for Hackathon)
```bash
# Install Polar
# Download from: https://lightningpolar.com/

# Create network with:
# - 2 LND nodes
# - 1 Bitcoin Core backend
# - Open channels between nodes
```

#### Option B: Local LND Setup
```bash
# Install LND
brew install lnd  # macOS

# Start Bitcoin regtest
bitcoind -regtest -daemon

# Start LND
lnd --bitcoin.active --bitcoin.regtest --bitcoin.node=bitcoind
```

### Step 2: Lightning Service Implementation (1 hour)

#### lightning-service.ts
```typescript
import { Lightning } from '@radar/lnrpc';

export class LightningService {
  private lnd: Lightning;
  
  constructor(config: LightningConfig) {
    this.lnd = new Lightning({
      host: config.host,
      cert: config.cert,
      macaroon: config.macaroon
    });
  }
  
  // Create HTLC invoice with specific payment hash
  async createHTLCInvoice(
    paymentHash: Buffer,
    amountSats: number,
    memo: string
  ): Promise<string> {
    const invoice = await this.lnd.addInvoice({
      r_hash: paymentHash,
      value: amountSats,
      memo: memo,
      expiry: 3600 // 1 hour
    });
    
    return invoice.payment_request;
  }
  
  // Monitor for invoice payment
  async waitForPayment(paymentHash: Buffer): Promise<Buffer> {
    return new Promise((resolve) => {
      const stream = this.lnd.subscribeInvoices({
        r_hash: paymentHash
      });
      
      stream.on('data', (invoice) => {
        if (invoice.settled) {
          resolve(invoice.r_preimage);
          stream.cancel();
        }
      });
    });
  }
  
  // Pay Lightning invoice
  async payInvoice(paymentRequest: string): Promise<Buffer> {
    const payment = await this.lnd.sendPaymentSync({
      payment_request: paymentRequest
    });
    
    if (payment.payment_error) {
      throw new Error(payment.payment_error);
    }
    
    return payment.payment_preimage;
  }
}
```

### Step 3: EVM ↔ Lightning Bridge Contract (1 hour)

#### LightningBridge.sol
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract LightningBridge {
    struct LightningSwap {
        address evmEscrow;
        bytes32 paymentHash;
        uint256 satoshiAmount;
        uint256 weiAmount;
        address initiator;
        address recipient;
        bool settled;
        uint256 createdAt;
    }
    
    mapping(bytes32 => LightningSwap) public swaps;
    
    event LightningSwapCreated(
        bytes32 indexed paymentHash,
        address indexed evmEscrow,
        uint256 satoshiAmount,
        string lightningInvoice
    );
    
    event LightningSwapSettled(
        bytes32 indexed paymentHash,
        bytes32 preimage
    );
    
    // Initiate EVM → Lightning swap
    function createLightningSwap(
        address evmEscrow,
        bytes32 paymentHash,
        uint256 satoshiAmount,
        address recipient
    ) external {
        require(swaps[paymentHash].createdAt == 0, "Swap exists");
        
        swaps[paymentHash] = LightningSwap({
            evmEscrow: evmEscrow,
            paymentHash: paymentHash,
            satoshiAmount: satoshiAmount,
            weiAmount: msg.value,
            initiator: msg.sender,
            recipient: recipient,
            settled: false,
            createdAt: block.timestamp
        });
        
        // Emit for off-chain Lightning node to create invoice
        emit LightningSwapCreated(
            paymentHash,
            evmEscrow,
            satoshiAmount,
            "" // Invoice created off-chain
        );
    }
    
    // Settle after Lightning payment
    function settleLightningSwap(
        bytes32 paymentHash,
        bytes32 preimage
    ) external {
        require(keccak256(abi.encode(preimage)) == paymentHash, "Invalid preimage");
        require(!swaps[paymentHash].settled, "Already settled");
        
        swaps[paymentHash].settled = true;
        
        // Now resolver can use preimage to claim EVM escrow
        emit LightningSwapSettled(paymentHash, preimage);
    }
}
```

### Step 4: Integrated Resolver for Lightning (2 hours)

#### lightning-resolver.ts
```typescript
export class LightningAtomicSwapResolver {
  private lightningService: LightningService;
  private evmService: EVMService;
  private bridgeContract: LightningBridge;
  
  // Monitor for EVM → Lightning swaps
  async monitorEVMToLightning() {
    this.bridgeContract.on('LightningSwapCreated', async (event) => {
      const { paymentHash, satoshiAmount } = event;
      
      // Create Lightning invoice
      const invoice = await this.lightningService.createHTLCInvoice(
        paymentHash,
        satoshiAmount,
        'Bridge-Me-Not Atomic Swap'
      );
      
      console.log(`Lightning invoice created: ${invoice}`);
      
      // Wait for payment
      const preimage = await this.lightningService.waitForPayment(paymentHash);
      
      // Settle on EVM
      await this.bridgeContract.settleLightningSwap(paymentHash, preimage);
      
      // Withdraw from source EVM escrow
      await this.withdrawFromEscrow(event.evmEscrow, preimage);
    });
  }
  
  // Execute Lightning → EVM swap
  async executeLightningToEVM(
    invoice: string,
    evmRecipient: string,
    evmToken: string,
    evmAmount: bigint
  ) {
    // Decode invoice to get payment hash
    const decoded = await this.lightningService.decodeInvoice(invoice);
    const paymentHash = decoded.payment_hash;
    
    // Create EVM escrow with same hash
    const escrow = await this.evmService.createEscrow({
      token: evmToken,
      recipient: evmRecipient,
      hashlock: paymentHash,
      amount: evmAmount,
      timeout: Math.floor(Date.now() / 1000) + 3600
    });
    
    // Fund escrow
    await this.evmService.fundEscrow(escrow, evmAmount);
    
    // Pay Lightning invoice
    const preimage = await this.lightningService.payInvoice(invoice);
    
    // Recipient can now claim EVM funds with preimage
    console.log(`Lightning payment complete. Preimage: ${preimage}`);
  }
  
  // Three-way swap: EVM A → Lightning → EVM B
  async executeThreeWaySwap(
    sourceChain: ChainConfig,
    destChain: ChainConfig,
    amount: bigint,
    lightningAmount: number
  ) {
    // Generate shared secret
    const preimage = crypto.randomBytes(32);
    const paymentHash = crypto.createHash('sha256').update(preimage).digest();
    
    // Step 1: Create escrows on both EVM chains
    const srcEscrow = await this.createEscrowOnChain(
      sourceChain,
      paymentHash,
      amount
    );
    
    const dstEscrow = await this.createEscrowOnChain(
      destChain,
      paymentHash,
      amount
    );
    
    // Step 2: Create Lightning invoice
    const invoice = await this.lightningService.createHTLCInvoice(
      paymentHash,
      lightningAmount,
      'Three-way atomic swap'
    );
    
    // Step 3: Fund source escrow
    await this.fundEscrow(sourceChain, srcEscrow, amount);
    
    // Step 4: Pay Lightning invoice
    await this.lightningService.payInvoice(invoice);
    
    // Step 5: Use preimage to claim both EVM escrows
    await this.withdrawFromEscrow(destChain, dstEscrow, preimage);
    await this.withdrawFromEscrow(sourceChain, srcEscrow, preimage);
    
    console.log('Three-way atomic swap complete!');
  }
}
```

### Step 5: Demo Scenarios (1 hour)

#### Scenario 1: EVM → Lightning
```typescript
// Alice locks USDC on Ethereum
const escrow = await factory.createEscrow({
  token: USDC,
  amount: 100e6, // 100 USDC
  recipient: bridgeAddress,
  hashlock: paymentHash,
  timeout: now + 3600
});

// Bridge creates Lightning invoice
const invoice = await lightning.createInvoice(paymentHash, 100000); // 100k sats

// Alice pays Lightning invoice
await aliceLightning.payInvoice(invoice);

// Bridge receives preimage and withdraws USDC
await escrow.withdraw(preimage);
```

#### Scenario 2: Lightning → EVM
```typescript
// Bob creates Lightning invoice
const invoice = await bobLightning.createInvoice(paymentHash, 100000);

// Bridge locks USDT on Polygon
const escrow = await factory.createEscrow({
  token: USDT,
  amount: 100e6,
  recipient: bobAddress,
  hashlock: paymentHash,
  timeout: now + 3600
});

// Bridge pays Lightning invoice
const preimage = await bridgeLightning.payInvoice(invoice);

// Bob claims USDT with preimage
await escrow.withdraw(preimage);
```

#### Scenario 3: EVM ↔ Lightning ↔ EVM
```typescript
// Alice wants to swap ETH on Ethereum for MATIC on Polygon via Lightning

// Step 1: Lock ETH on Ethereum
const ethEscrow = await createEscrow(ETH, amount, paymentHash);

// Step 2: Create Lightning invoice
const invoice = await createInvoice(paymentHash, satoshis);

// Step 3: Lock MATIC on Polygon
const maticEscrow = await createEscrow(MATIC, amount, paymentHash);

// Step 4: Complete the swap
await payInvoice(invoice); // Reveals preimage
await withdraw(ethEscrow, preimage);
await withdraw(maticEscrow, preimage);
```

## 🎮 Demo Setup Instructions

### 1. Prepare Lightning Environment
```bash
# Start Polar
# Create 2 LND nodes: Alice and Bob
# Open channel: Alice -> Bob (1M sats)
# Get connection details for both nodes
```

### 2. Deploy Contracts
```bash
# Deploy on Ethereum fork
forge script DeployLightning.s.sol --rpc-url eth

# Deploy on Polygon fork  
forge script DeployLightning.s.sol --rpc-url polygon
```

### 3. Run Demo
```bash
# Terminal 1: Start Lightning resolver
deno task lightning:resolver

# Terminal 2: Run demo scenario
deno task demo:lightning-swap

# Terminal 3: Monitor both chains
deno task monitor:all
```

## 🚀 Hackathon Talking Points

1. **Innovation**: First to combine 1inch atomic swaps with Lightning Network
2. **Universality**: Any EVM chain ↔ Bitcoin Lightning ↔ Any EVM chain
3. **Speed**: Lightning settles in seconds vs minutes for on-chain
4. **Cost**: Lightning fees are negligible (<1 cent)
5. **Security**: Same HTLC security model across all layers

## 📊 Performance Metrics

| Metric | Traditional Bridge | Atomic Swap | Lightning Atomic |
|--------|-------------------|-------------|------------------|
| Settlement Time | 10-30 mins | 5-10 mins | 5-30 seconds |
| Security | Trust required | Trustless | Trustless |
| Fees | 0.1-1% | Gas only | Gas + <$0.01 |
| Liquidity | Fragmented | Direct | Bitcoin + EVM |

## 🎯 Success Criteria

- [ ] Complete EVM → Lightning swap
- [ ] Complete Lightning → EVM swap  
- [ ] Complete three-way swap (EVM → Lightning → EVM)
- [ ] Live demo without crashes
- [ ] Clear value proposition explained

## 🔧 Troubleshooting

### Common Issues

1. **Lightning node not synced**
   - Solution: Use Polar for instant setup

2. **Invoice expires**
   - Solution: Increase expiry time or automate payment

3. **Gas estimation fails**
   - Solution: Use fixed gas limits for demo

4. **Preimage mismatch**
   - Solution: Ensure consistent encoding (Buffer vs hex)

### Emergency Demo Fallback
- Pre-record video of successful swap
- Have screenshots ready
- Prepare clear explanation of what would happen

Remember: The goal is to show the **concept** works. Polish can come later!