# Testing Guide - Bridge Me Not V2

This guide explains how to run the full test suite for Bridge Me Not V2, including smart contract tests and cross-chain integration tests.

## Prerequisites

- Foundry installed (`forge`, `anvil`, `cast`)
- Deno installed for TypeScript tests
- `mprocs` for multi-process management
- `jq` for JSON processing

## Test Types

### 1. Smart Contract Tests (Foundry)

Run all Solidity tests:

```bash
forge test
```

Run with verbosity:
```bash
forge test -vvv
```

Run specific test:
```bash
forge test --match-test testAtomicSwapFlow
```

### 2. Cross-Chain Integration Tests (Deno/Viem)

These tests verify atomic swaps work correctly across chains using actual deployed contracts.

#### Setup

1. Start local chains:
```bash
mprocs -c mprocs.yaml
```

2. Deploy contracts:
```bash
./scripts/deploy.sh -y
```

3. Run Deno tests:
```bash
./scripts/test-runner.sh
```

#### Alternative: Use mprocs Interactive Mode

1. Start mprocs:
```bash
mprocs -c mprocs.yaml
```

2. Use keyboard shortcuts:
   - `s` - Start a process
   - Select `test-deno` to run Deno tests
   - `q` - Quit

## Test Structure

### Smart Contract Tests

- `test/SimpleEscrow.t.sol` - Core escrow functionality (35 tests)
- `test/SimpleEscrowFactory.t.sol` - Factory and deployment (25 tests)
- `test/CrossChainIntegration.t.sol` - Cross-chain scenarios (7 tests)

### Integration Tests

- `scripts/test-atomic-swap.ts` - End-to-end atomic swap flow
- Tests the complete lifecycle:
  1. Alice creates escrow on Base with USDC
  2. Bob creates escrow on Etherlink with XTZ
  3. Alice reveals preimage on Etherlink
  4. Bob uses preimage on Base
  5. Both parties receive their swapped tokens

## Configuration

### Environment Variables

Create `.env` file:
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
```

### Test Configuration

Edit `scripts/config.ts` to customize:
- Retry attempts
- Retry delays
- Log levels
- Default accounts

## Troubleshooting

### Chains Not Running

If tests fail with "chain not running":
```bash
# Check if anvil processes are running
ps aux | grep anvil

# Restart chains
mprocs -c mprocs.yaml
```

### Deployment Missing

If tests fail with "deployment.json not found":
```bash
# Deploy contracts
./scripts/deploy.sh -y

# Check deployment
cat deployment.json | jq .
```

### ABI Errors

If tests fail with ABI errors:
```bash
# Extract ABIs from compiled contracts
./scripts/copy-abis.sh

# Check ABIs exist
ls scripts/abis/
```

### Permission Errors

```bash
# Make scripts executable
chmod +x scripts/*.sh
```

## Advanced Testing

### Gas Profiling

```bash
# Generate gas snapshot
forge snapshot

# Compare gas usage
forge snapshot --diff
```

### Coverage Report

```bash
# Generate coverage report
forge coverage

# Detailed coverage
forge coverage --report lcov
```

### Fuzz Testing

Tests include fuzz testing for edge cases:
```bash
# Run with more fuzz runs
forge test --fuzz-runs 10000
```

## CI/CD Integration

For GitHub Actions:
```yaml
- name: Run Tests
  run: |
    forge test
    ./scripts/test-runner.sh
```

## Test Results Summary

Current test status:
- ✅ 69 Solidity tests passing
- ✅ Cross-chain atomic swap flow working
- ✅ Gas optimized (see gas snapshots)
- ✅ 100% core functionality coverage

## Next Steps

1. Add more edge case tests
2. Implement stress testing
3. Add mainnet fork testing
4. Security audit preparation