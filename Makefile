# Bridge Me Not - EVM Contracts v2 Makefile

.PHONY: install build test deploy-local deploy-testnet deploy-multi clean verify help

# Default target
help:
	@echo "Bridge Me Not - Available commands:"
	@echo "  make install        - Install dependencies"
	@echo "  make build          - Build contracts"
	@echo "  make test           - Run all tests"
	@echo "  make deploy-local   - Deploy to local Anvil chains"
	@echo "  make deploy-testnet - Deploy to configured testnets"
	@echo "  make deploy-multi   - Deploy to multiple chains"
	@echo "  make verify         - Verify deployed contracts"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make stop-local     - Stop local Anvil instances"

# Install dependencies
install:
	@echo "Installing dependencies..."
	@forge install

# Build contracts
build:
	@echo "Building contracts..."
	@forge build

# Run tests
test:
	@echo "Running tests..."
	@forge test -vvv

# Deploy to local chains
deploy-local: build
	@echo "Deploying to local chains..."
	@./scripts/deploy-local.sh

# Deploy to testnets
deploy-testnet: build
	@echo "Deploying to testnets..."
	@./scripts/deploy-testnet.sh

# Deploy to multiple chains
deploy-multi: build
	@echo "Deploying to multiple chains..."
	@forge script script/DeployMultiChain.s.sol:DeployMultiChain --broadcast -vvv

# Deploy with Lightning support
deploy-lightning: build
	@echo "Deploying with Lightning support..."
	@forge script script/DeployWithLightning.s.sol:DeployWithLightning --broadcast -vvv

# Verify contracts
verify:
	@echo "Verifying contracts..."
	@forge script script/Verify.s.sol:Verify

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@forge clean
	@rm -rf out cache

# Stop local chains
stop-local:
	@echo "Stopping local chains..."
	@./scripts/stop-local.sh

# Format code
format:
	@echo "Formatting code..."
	@forge fmt

# Check formatting
format-check:
	@echo "Checking code format..."
	@forge fmt --check

# Generate gas snapshot
gas:
	@echo "Generating gas snapshot..."
	@forge snapshot

# Show contract sizes
sizes: build
	@echo "Contract sizes:"
	@forge build --sizes