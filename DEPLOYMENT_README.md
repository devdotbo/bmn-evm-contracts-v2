# Deployment Scripts Guide

This guide explains how to use the deployment scripts for Bridge Me Not EVM contracts v2.

## Quick Start

### 1. Setup Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
# IMPORTANT: Never commit your private key!
```

### 2. Local Deployment (Development)

```bash
# Deploy to local Anvil chains
make deploy-local

# Stop local chains when done
make stop-local
```

### 3. Testnet Deployment

```bash
# Deploy to configured testnets
make deploy-testnet
```

### 4. Multi-Chain Deployment

```bash
# Deploy to multiple chains at once
make deploy-multi
```

## Deployment Scripts

### Basic Deployment (`script/Deploy.s.sol`)
- Deploys SimpleEscrowFactory
- Optionally deploys OneInchAdapter
- Saves deployment artifacts to `deployments/`

### Lightning Deployment (`script/DeployWithLightning.s.sol`)
- Includes all basic deployment features
- Additionally deploys LightningBridge
- Requires `RESOLVER_ADDRESS` in environment

### Multi-Chain Deployment (`script/DeployMultiChain.s.sol`)
- Deploys to multiple chains in one script
- Uses deterministic addresses (CREATE2)
- Generates deployment summary

### Verification (`script/Verify.s.sol`)
- Verifies deployed contracts on block explorers
- Generates verification commands
- Creates verification shell script

## Environment Variables

Required:
- `PRIVATE_KEY`: Deployer wallet private key

Optional:
- `LIMIT_ORDER_PROTOCOL`: 1inch Limit Order Protocol address
- `RESOLVER_ADDRESS`: Lightning resolver address (for Lightning deployment)
- `*_RPC_URL`: RPC endpoints for each network
- `*_API_KEY`: Block explorer API keys for verification

## Deployment Artifacts

Deployments are saved to `deployments/` directory:
- `{chainId}-deployment.json`: Basic deployment info
- `{chainId}-lightning-deployment.json`: Lightning deployment info
- `multi-chain-summary.json`: Multi-chain deployment summary
- `verify-{chainId}.sh`: Auto-generated verification script

## Common Commands

```bash
# Build contracts
make build

# Run tests
make test

# Deploy locally
make deploy-local

# Deploy to testnets
make deploy-testnet

# Verify contracts
make verify

# Check contract sizes
make sizes
```

## Troubleshooting

### "No RPC URL found"
- Ensure RPC URLs are set in `.env` file
- Check variable names match expected format (e.g., `SEPOLIA_RPC_URL`)

### "Verification failed"
- Ensure correct API key is set for the network
- Try manual verification with flattened source
- Check compiler settings match deployment

### "Gas price too high"
- Add `--legacy` flag to use legacy gas pricing
- Set custom gas price in environment variables

## Security Notes

1. **Never commit `.env` file or private keys**
2. Use hardware wallets for mainnet deployments
3. Test thoroughly on testnets first
4. Verify all contracts after deployment
5. Use deterministic deployment for consistent addresses