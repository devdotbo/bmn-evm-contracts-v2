# Bridge Me Not - Deno Test Suite

This directory contains a Deno-based test suite for demonstrating cross-chain atomic swaps between Base and Etherlink without using any bridge.

## Prerequisites

1. **Deno** - Install from https://deno.land/
2. **Foundry** - Install from https://getfoundry.sh/
3. **Running local chains** - Base on port 8545, Etherlink on port 8546

## Setup

1. Run the setup script to initialize the environment:
   ```bash
   deno task setup
   ```

2. Start local chains (in parent directory):
   ```bash
   cd .. && ./scripts/deploy-local.sh
   ```

3. Build contracts and copy ABIs:
   ```bash
   deno task build
   ```

## Running Tests

### Atomic Swap Demo
Run the full atomic swap demonstration:
```bash
deno task test:atomic-swap
```

### Unit Tests
Run the test suite:
```bash
deno task test
```

## Configuration

Environment variables can be set in `../.env`:

```env
# Private keys (defaults are Anvil test accounts)
ALICE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
BOB_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# RPC URLs
BASE_RPC=http://localhost:8545
ETHERLINK_RPC=http://localhost:8546

# Chain IDs
BASE_CHAIN_ID=8453
ETHERLINK_CHAIN_ID=42793

# Test configuration
LOG_LEVEL=info
RETRY_ATTEMPTS=3
RETRY_DELAY=1000
```

## Test Flow

The atomic swap test demonstrates:

1. **Alice on Base**: Creates an escrow with 100 USDC locked for Bob
2. **Bob on Etherlink**: Creates an escrow with 10 XTZ locked for Alice (same hashlock)
3. **Alice reveals**: Withdraws XTZ on Etherlink by revealing the preimage
4. **Bob completes**: Uses the revealed preimage to withdraw USDC on Base
5. **Verification**: Confirms both parties received their expected tokens

## Logs

Test logs are saved to `../logs/atomic-swap.log` with detailed information about each step.

## Project Structure

```
scripts/
├── deno.json          # Deno configuration and tasks
├── config.ts          # Environment configuration
├── test-atomic-swap.ts # Main atomic swap demo
├── atomic-swap.test.ts # Unit tests
├── setup.ts           # Setup script
├── copy-abis.sh       # ABI extraction script
└── abis/              # Extracted contract ABIs
```

## Development

### Adding New Tests
1. Create new test files with `.test.ts` extension
2. Import test utilities from `@std/testing`
3. Use the config module for environment settings

### Debugging
- Set `LOG_LEVEL=debug` in `.env` for verbose logging
- Check `../logs/atomic-swap.log` for detailed execution logs
- Use `deno run --inspect` for debugging with Chrome DevTools

## Troubleshooting

### "Contracts not deployed"
Make sure to run the deployment script first:
```bash
cd .. && ./scripts/deploy-local.sh
```

### "Failed to load ABI"
Run the build task to compile contracts and extract ABIs:
```bash
deno task build
```

### Connection errors
Ensure Anvil chains are running on the correct ports:
- Base: http://localhost:8545
- Etherlink: http://localhost:8546