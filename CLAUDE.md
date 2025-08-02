# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Instructions

- **ALWAYS use Context7 to look up any errors encountered during development**. When you get an error, search Context7 for documentation about that specific error before attempting to fix it.

## Project Overview

This is a Foundry-based smart contract project for Bridge Me Not (BMN) EVM contracts v2. The project uses Foundry's development toolkit including Forge for testing, Cast for interacting with contracts, and Anvil for local development.

## Development Commands

### Build
```bash
forge build
```

### Test
```bash
forge test          # Run all tests
forge test -vvv     # Run tests with maximum verbosity
forge test --match-test testName  # Run specific test
forge test --match-contract ContractName  # Run tests for specific contract
```

### Format
```bash
forge fmt           # Format code
forge fmt --check   # Check formatting without changes
```

### Deploy
```bash
forge script script/Counter.s.sol:CounterScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

### Gas Optimization
```bash
forge snapshot      # Generate gas snapshots
forge build --sizes # Show contract sizes
```

## Project Structure

- `src/` - Smart contract source files
- `test/` - Test files using Forge's testing framework
- `script/` - Deployment and interaction scripts
- `lib/forge-std/` - Foundry standard library (testing utilities)

## Testing Patterns

Tests follow Foundry conventions:
- Test contracts inherit from `Test`
- Test functions start with `test_` or `testFuzz_`
- Use `setUp()` for test initialization
- Import test utilities from `forge-std/Test.sol`