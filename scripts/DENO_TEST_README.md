# Deno Tests for Bridge Me Not V2

This directory contains Deno-based tests for the Bridge Me Not atomic swap functionality using the Viem library.

## Prerequisites

- Deno 2.0 or higher
- Foundry (for running local chains)
- Environment variables configured in `.env`

## Environment Variables

Create a `.env` file in the project root with:

```bash
# Private keys (use test keys for development)
ALICE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
BOB_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# RPC endpoints
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

## Running Tests

### 1. Start Local Chains

```bash
cd ..
mprocs -c mprocs.yaml
```

### 2. Deploy Contracts

```bash
./deploy.sh -y
```

### 3. Run Deno Tests

Using deno task (recommended):
```bash
deno task test:atomic-swap
```

Or directly with permissions:
```bash
deno run --allow-read --allow-write --allow-env --allow-net test-atomic-swap.ts
```

## Permissions

The tests require the following Deno permissions:

- `--allow-read`: Read `.env` file and deployment.json
- `--allow-write`: Write log files to `../logs/`
- `--allow-env`: Access environment variables
- `--allow-net`: Connect to Ethereum RPC endpoints

## Test Structure

### Main Test File: `test-atomic-swap.ts`

The test performs a complete atomic swap flow:

1. **Setup**
   - Validates environment variables
   - Checks required permissions
   - Loads deployment addresses
   - Creates Viem clients

2. **Token Minting**
   - Mints USDC to Alice on Base chain
   - Mints XTZ to Bob on Etherlink chain

3. **Atomic Swap Flow**
   - Alice creates escrow on Base with USDC
   - Bob creates escrow on Etherlink with XTZ
   - Alice reveals preimage on Etherlink
   - Bob uses preimage on Base
   - Both parties receive swapped tokens

4. **Verification**
   - Checks final balances
   - Validates swap completion

### Configuration: `config.ts`

Handles:
- Environment variable loading (Deno-native, no external deps)
- Deployment data loading from `deployment.json`
- Configuration validation
- Default values for local testing

### ABIs: `abis/`

Contract ABIs are extracted from Forge artifacts using:
```bash
./copy-abis.sh
```

## Viem Integration

The tests use Viem v2.21.60+ with:
- Type-safe contract interactions
- Account management via `privateKeyToAccount`
- Public and wallet clients for each chain
- Proper error handling and retries

## Debugging

### Enable Debug Logging

```bash
LOG_LEVEL=debug deno run --allow-all test-atomic-swap.ts
```

### Check Logs

Test logs are written to:
```
../logs/atomic-swap.log
```

### Common Issues

1. **"Missing required environment variables"**
   - Ensure `.env` file exists and contains all required variables

2. **"Chain not running"**
   - Start chains with `mprocs -c mprocs.yaml`

3. **"deployment.json not found"**
   - Deploy contracts with `./deploy.sh -y`

4. **Permission denied**
   - Run with all required permissions: `--allow-read --allow-write --allow-env --allow-net`

## Development

### Format Code
```bash
deno fmt
```

### Lint Code
```bash
deno lint
```

### Type Check
```bash
deno check test-atomic-swap.ts
```

### Watch Mode
```bash
deno task test:watch
```

## CI/CD Integration

For GitHub Actions:

```yaml
- name: Setup Deno
  uses: denoland/setup-deno@v2
  with:
    deno-version: v2.x

- name: Run Deno Tests
  run: |
    cd scripts
    deno task test:atomic-swap
```

## Further Reading

- [Deno Manual](https://docs.deno.com/)
- [Viem Documentation](https://viem.sh/)
- [Deno Permissions](https://docs.deno.com/runtime/fundamentals/security)
- [Deno Environment Variables](https://docs.deno.com/runtime/manual/basics/env_variables)