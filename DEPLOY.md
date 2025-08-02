# Bridge Me Not V2 - Deployment Guide

## Quick Start (Local)

1. **Setup Environment**
   ```bash
   cp .env.example .env
   # Edit .env if using custom keys
   ```

2. **Run Local Demo**
   ```bash
   # Start local node
   anvil

   # In another terminal
   forge script script/QuickDemo.s.sol:QuickDemo --broadcast
   ```

## Testnet Deployment

### Sepolia Deployment
```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### Mumbai Deployment
```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MUMBAI_RPC_URL \
  --broadcast \
  --verify
```

## Hackathon Demo

Run the comprehensive demo showing all features:

```bash
# Make sure .env has all three private keys
forge script script/HackathonDemo.s.sol:HackathonDemo --broadcast
```

## Contract Addresses (Local Anvil)

After running QuickDemo:
- USDC Token: `0x5FbDB2315678afecb367f032d93F642f64180aa3`
- SimpleEscrowFactory: `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0`

## Key Features Demonstrated

1. **Simple Atomic Swap**: Direct HTLC-based swap without bridges
2. **1inch Integration**: Seamless integration with limit order protocol
3. **Lightning Bridge**: Same preimage unlocks both EVM and Lightning

## Architecture

```
SimpleEscrow (HTLC)
    ↓
SimpleEscrowFactory (CREATE2)
    ↓
┌─────────────┬──────────────────┐
│ OneInchAdapter │ LightningBridge │
└─────────────┴──────────────────┘
```

## Testing

All tests passing:
```bash
forge test --summary
```

Output:
- 69/69 tests passing (100%)
- Core functionality fully tested
- Gas optimization verified