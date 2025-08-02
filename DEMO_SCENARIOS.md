# Demo Scenarios for Bridge-Me-Not Hackathon

## Overview
This document provides step-by-step demo scenarios showcasing the simplified atomic swap system with 1inch compatibility and Lightning Network integration. Each scenario is designed to highlight key innovations within a short presentation window.

## Demo Environment Setup

### Prerequisites
```bash
# Terminal Setup (split into 4 windows)
# Terminal 1: Chain 1 (Ethereum)
# Terminal 2: Chain 2 (Polygon)  
# Terminal 3: Resolver
# Terminal 4: Demo execution

# Lightning Setup (if demonstrating)
# Polar with 2 nodes: Alice and Bob
# Channel: Alice -> Bob (1M sats)
```

### Quick Setup Commands
```bash
# Start everything
./scripts/setup-demo.sh

# This will:
# 1. Start two Anvil chains
# 2. Deploy all contracts
# 3. Start resolver
# 4. Fund demo accounts
```

## Scenario 1: Basic Atomic Swap (5 minutes)

### Story
"Alice wants to swap 100 USDC on Ethereum for 100 USDT on Polygon without using a bridge"

### Demo Flow

#### Step 1: Show Initial State
```typescript
// scripts/demo/01-basic-swap.ts
console.log("🎬 Demo: Basic Atomic Swap");
console.log("Alice has 100 USDC on Ethereum");
console.log("Bob has 100 USDT on Polygon");
console.log("Goal: Swap without bridge risk!");
```

#### Step 2: Alice Creates Atomic Swap
```typescript
// Alice creates the swap order
const secret = generateSecret();
const hashlock = keccak256(secret);

const aliceEscrow = await factoryEth.createEscrow(
  USDC_ETH,
  alice.address,
  bob.address,
  hashlock,
  timestamp + 3600, // 1 hour
  salt
);

console.log("✅ Alice's escrow created:", aliceEscrow);

// Alice funds the escrow
await usdcEth.approve(aliceEscrow, parseUnits("100", 6));
await SimpleEscrow(aliceEscrow).fund(parseUnits("100", 6));

console.log("💰 Alice locked 100 USDC");
```

#### Step 3: Bob Responds
```typescript
// Bob sees Alice's escrow and creates matching one
const bobEscrow = await factoryPolygon.createEscrow(
  USDT_POLYGON,
  bob.address,
  alice.address,
  hashlock, // Same hashlock!
  timestamp + 1800, // 30 min (shorter timeout)
  salt
);

// Bob funds his escrow
await usdtPolygon.approve(bobEscrow, parseUnits("100", 6));
await SimpleEscrow(bobEscrow).fund(parseUnits("100", 6));

console.log("💰 Bob locked 100 USDT");
```

#### Step 4: Atomic Execution
```typescript
// Bob withdraws from Alice's escrow with secret
await SimpleEscrow(aliceEscrow).withdraw(secret);
console.log("✅ Bob claimed 100 USDC on Ethereum!");

// Secret is now revealed on-chain
const revealedSecret = await SimpleEscrow(aliceEscrow).preimage();
console.log("🔓 Secret revealed:", revealedSecret);

// Alice uses the revealed secret
await SimpleEscrow(bobEscrow).withdraw(revealedSecret);
console.log("✅ Alice claimed 100 USDT on Polygon!");

// Show final balances
console.log("Final state:");
console.log("- Alice: 100 USDT on Polygon ✅");
console.log("- Bob: 100 USDC on Ethereum ✅");
console.log("🎉 Atomic swap complete! No bridge needed!");
```

### Key Points to Emphasize
- No intermediary or bridge contract
- Atomic: either both get funds or neither
- Cross-chain coordination via same hashlock
- Trustless execution

## Scenario 2: 1inch Integration (5 minutes)

### Story
"Alice wants to use 1inch interface for atomic swaps to access liquidity"

### Demo Flow

#### Step 1: Create 1inch Order
```typescript
console.log("🎬 Demo: 1inch Compatible Atomic Swap");

// Create order with atomic swap extension
const extension = encodeAtomicSwapData({
  hashlock,
  crossChainRecipient: bob.address,
  timeoutDuration: 3600,
  destinationChainId: 137,
  salt: generateSalt()
});

const order = {
  salt: BigInt(keccak256(extension)),
  maker: alice.address,
  receiver: ZERO_ADDRESS,
  makerAsset: USDC_ETH,
  takerAsset: USDT_ETH,
  makingAmount: parseUnits("100", 6),
  takingAmount: parseUnits("100", 6),
  makerTraits: buildMakerTraits({
    allowPartialFill: false,
    needPostInteraction: true,
    extension: ADAPTER_ADDRESS
  })
};

console.log("📝 1inch order created with atomic swap data");
```

#### Step 2: Fill Order Through 1inch
```typescript
// Sign order
const signature = await alice.signOrder(order);

// Bob fills the order through 1inch
await limitOrderProtocol.fillOrder(
  order,
  signature,
  order.makingAmount,
  order.takingAmount,
  extension
);

console.log("✅ Order filled through 1inch!");
console.log("🏭 OneInchAdapter automatically created escrow");
```

#### Step 3: Show Escrow Creation
```typescript
// Adapter created and funded the escrow
const escrowAddress = await factory.computeEscrowAddress(
  order.makerAsset,
  order.maker,
  bob.address,
  hashlock,
  blockTimestamp + 3600,
  salt
);

const escrowDetails = await SimpleEscrow(escrowAddress).getDetails();
console.log("📦 Escrow details:", escrowDetails);
console.log("✅ Fully compatible with 1inch ecosystem!");
```

### Key Points to Emphasize
- Seamless 1inch integration
- Same UI/UX as regular 1inch orders
- Atomic swap happens automatically
- Access to 1inch liquidity network

## Scenario 3: Lightning Network Bridge (7 minutes)

### Story
"Alice wants to swap ETH on Ethereum for Bitcoin via Lightning Network"

### Demo Flow

#### Step 1: Setup Lightning
```typescript
console.log("🎬 Demo: EVM to Lightning Atomic Swap");
console.log("⚡ Lightning nodes ready:");
console.log("- Alice LND: 1M sats capacity");
console.log("- Bridge LND: Connected to both");
```

#### Step 2: Initiate EVM to Lightning Swap
```typescript
// Alice initiates swap
const paymentHash = sha256(preimage);

const { escrow } = await lightningBridge.initiateEVMToLightning(
  WETH_ADDRESS,
  parseEther("0.1"), // 0.1 ETH
  100000, // 100k sats
  paymentHash,
  timestamp + 3600
);

console.log("🔐 EVM escrow created:", escrow);

// Alice funds the escrow
await weth.approve(escrow, parseEther("0.1"));
await SimpleEscrow(escrow).fund(parseEther("0.1"));

console.log("💰 Alice locked 0.1 ETH");
```

#### Step 3: Lightning Invoice Creation
```typescript
// Bridge creates Lightning invoice
const invoice = await bridgeLightning.createInvoice({
  rHash: paymentHash,
  value: 100000,
  memo: "Bridge-Me-Not: ETH to BTC swap"
});

console.log("⚡ Lightning invoice:", invoice);
console.log("📱 QR Code: [show QR code]");

// Update bridge contract
await lightningBridge.setLightningInvoice(paymentHash, invoice);
```

#### Step 4: Complete Lightning Payment
```typescript
// Alice pays Lightning invoice
const payResult = await aliceLightning.payInvoice(invoice);
console.log("⚡ Lightning payment sent!");

// Bridge detects payment and gets preimage
const preimage = payResult.paymentPreimage;
console.log("🔓 Preimage revealed:", preimage);

// Bridge updates contract
await lightningBridge.confirmLightningPayment(paymentHash, preimage);

// Bridge withdraws ETH
await SimpleEscrow(escrow).withdraw(preimage);
console.log("✅ Bridge claimed 0.1 ETH");

// Final state
console.log("Final state:");
console.log("- Alice: +100k sats on Lightning ⚡");
console.log("- Bridge: +0.1 ETH on Ethereum ⚜️");
console.log("🎉 First EVM-Lightning atomic swap!");
```

### Key Points to Emphasize
- True atomic swap with Bitcoin Lightning
- Same security model (HTLC)
- Instant settlement via Lightning
- Opens Bitcoin liquidity to EVM

## Scenario 4: Three-Way Swap (5 minutes)

### Story
"Alice wants to swap USDC on Ethereum for MATIC on Polygon using Lightning as intermediary"

### Demo Flow

```typescript
console.log("🎬 Demo: Three-Way Atomic Swap");
console.log("USDC (Ethereum) → Lightning → MATIC (Polygon)");

// Step 1: Create all three escrows
const payment1 = await createEVMToLightningSwap(USDC_ETH, 100e6, 100000);
const invoice = await createLightningInvoice(paymentHash, 100000);
const payment2 = await createLightningToEVMSwap(invoice, MATIC, 100e18);

// Step 2: Fund first escrow
await fundEscrow(payment1.escrow, 100e6);

// Step 3: Lightning payment reveals preimage
await payLightningInvoice(invoice);

// Step 4: Use preimage to claim both EVM escrows
await withdrawWithPreimage(payment1.escrow, preimage);
await withdrawWithPreimage(payment2.escrow, preimage);

console.log("✅ Three-way atomic swap complete!");
console.log("No bridges, no trust, pure atomic execution!");
```

## Demo Tips

### Preparation Checklist
- [ ] Test all scenarios in order
- [ ] Have backup recorded video
- [ ] Prepare network diagram visuals
- [ ] Test with actual testnet if possible
- [ ] Have fallback local demo ready

### Presentation Flow
1. **Problem Statement** (1 min)
   - Bridge hacks and risks
   - Liquidity fragmentation
   - Lightning Network isolation

2. **Solution Overview** (1 min)
   - Atomic swaps via HTLC
   - 1inch compatibility
   - Lightning integration

3. **Live Demo** (8-10 min)
   - Run 2-3 scenarios
   - Show actual transactions
   - Emphasize atomic nature

4. **Technical Innovation** (2 min)
   - Simplified architecture
   - Gas efficiency
   - Universal compatibility

5. **Future Vision** (1 min)
   - Any asset to any asset
   - Decentralized liquidity
   - No more bridges

### Common Demo Issues

#### Issue: Transaction Fails
```typescript
// Have pre-funded accounts
const DEMO_ACCOUNTS = {
  alice: "0x...", // Pre-funded with tokens
  bob: "0x...",   // Pre-funded with tokens
};
```

#### Issue: Lightning Connection
```typescript
// Fallback to mock Lightning
if (!lightning.isConnected()) {
  console.log("Using mock Lightning for demo");
  lightning = new MockLightning();
}
```

#### Issue: Timeout During Demo
```typescript
// Use shorter timeouts for demo
const DEMO_TIMEOUT = 300; // 5 minutes
```

## Visual Aids

### Diagram 1: Traditional Bridge vs Atomic Swap
```
Traditional Bridge:
User → Bridge Contract → ??? → User
        (Trusted)    (Risk)

Atomic Swap:
User A ← HTLC → ← HTLC → User B
      (Trustless)
```

### Diagram 2: Lightning Integration
```
   EVM Chain A          Lightning Network         EVM Chain B
       |                      |                        |
   [Escrow A] ←----→ [Lightning HTLC] ←----→ [Escrow B]
       |                      |                        |
   Same Preimage Unlocks All Three!
```

## Post-Demo Q&A Prep

### Likely Questions
1. **"How is this different from existing bridges?"**
   - No custody, no wrapped tokens, truly atomic

2. **"What about liquidity?"**
   - 1inch integration provides liquidity access
   - Lightning opens Bitcoin liquidity

3. **"Is it production ready?"**
   - Core concept proven, needs audit and optimization

4. **"What chains are supported?"**
   - Any EVM chain + Bitcoin Lightning
   - Easy to add new chains

### Success Metrics
- Demo completes without errors ✅
- Audience understands atomic nature ✅
- Clear value proposition delivered ✅
- Technical innovation appreciated ✅

Remember: **Keep it simple, focus on the magic moment when the atomic swap completes!**