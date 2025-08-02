# Deployment Scripts for Simplified Atomic Swaps

## Overview
This document provides ready-to-use deployment scripts for the simplified atomic swap system. Scripts are designed for quick hackathon deployment with minimal configuration.

## Directory Structure
```
bmn-evm-contracts-v2/
├── script/
│   ├── Deploy.s.sol              # Main deployment script
│   ├── DeployWithLightning.s.sol # Deploy with Lightning support
│   ├── DeployMultiChain.s.sol   # Deploy to multiple chains
│   └── VerifyContracts.s.sol    # Verification script
├── scripts/
│   ├── deploy-local.sh           # Local deployment helper
│   ├── deploy-testnet.sh         # Testnet deployment helper
│   └── setup-demo.sh             # Complete demo setup
```

## Foundry Deployment Scripts

### Deploy.s.sol - Basic Deployment
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../contracts/SimpleEscrow.sol";
import "../contracts/SimpleEscrowFactory.sol";
import "../contracts/OneInchAdapter.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address limitOrderProtocol = vm.envAddress("LIMIT_ORDER_PROTOCOL");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy SimpleEscrowFactory
        SimpleEscrowFactory factory = new SimpleEscrowFactory();
        console.log("SimpleEscrowFactory deployed at:", address(factory));
        
        // Deploy OneInchAdapter (optional)
        if (limitOrderProtocol != address(0)) {
            OneInchAdapter adapter = new OneInchAdapter(
                address(factory),
                limitOrderProtocol
            );
            console.log("OneInchAdapter deployed at:", address(adapter));
            
            // Set adapter in factory
            factory.setOneInchAdapter(address(adapter));
        }
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        _saveDeployment(address(factory), address(adapter));
    }
    
    function _saveDeployment(address factory, address adapter) internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "factory", factory);
        vm.serializeAddress(json, "adapter", adapter);
        vm.serializeUint(json, "chainId", block.chainid);
        string memory output = vm.serializeUint(json, "timestamp", block.timestamp);
        
        string memory filename = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-deployment.json"
        );
        vm.writeJson(output, filename);
    }
}
```

### DeployWithLightning.s.sol - Lightning Integration
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Deploy.s.sol";
import "../contracts/LightningBridge.sol";

contract DeployWithLightning is Deploy {
    function run() external override {
        // Deploy base contracts
        super.run();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address resolver = vm.envAddress("RESOLVER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Load factory address from previous deployment
        string memory deploymentPath = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-deployment.json"
        );
        string memory deploymentData = vm.readFile(deploymentPath);
        address factoryAddress = vm.parseJsonAddress(deploymentData, ".factory");
        
        // Deploy LightningBridge
        LightningBridge bridge = new LightningBridge(
            factoryAddress,
            resolver
        );
        console.log("LightningBridge deployed at:", address(bridge));
        
        vm.stopBroadcast();
        
        // Update deployment file
        _saveLightningDeployment(address(bridge));
    }
    
    function _saveLightningDeployment(address bridge) internal {
        string memory deploymentPath = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-deployment.json"
        );
        
        string memory json = "lightning";
        vm.serializeAddress(json, "bridge", bridge);
        string memory output = vm.serializeUint(json, "timestamp", block.timestamp);
        
        vm.writeJson(output, deploymentPath);
    }
}
```

### DeployMultiChain.s.sol - Multi-Chain Deployment
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Deploy.s.sol";

contract DeployMultiChain is Script {
    struct ChainConfig {
        string name;
        string rpcUrl;
        uint256 chainId;
        address limitOrderProtocol;
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        ChainConfig[] memory chains = new ChainConfig[](2);
        chains[0] = ChainConfig({
            name: "Ethereum",
            rpcUrl: vm.envString("ETH_RPC_URL"),
            chainId: 1,
            limitOrderProtocol: 0x1111111254EEB25477B68fb85Ed929f73A960582
        });
        chains[1] = ChainConfig({
            name: "Polygon",
            rpcUrl: vm.envString("POLYGON_RPC_URL"),
            chainId: 137,
            limitOrderProtocol: 0x1111111254EEB25477B68fb85Ed929f73A960582
        });
        
        // Deploy to each chain
        for (uint256 i = 0; i < chains.length; i++) {
            console.log(
                string.concat("Deploying to ", chains[i].name, "...")
            );
            
            vm.createSelectFork(chains[i].rpcUrl);
            
            vm.startBroadcast(deployerPrivateKey);
            
            // Deploy contracts
            SimpleEscrowFactory factory = new SimpleEscrowFactory();
            
            OneInchAdapter adapter;
            if (chains[i].limitOrderProtocol != address(0)) {
                adapter = new OneInchAdapter(
                    address(factory),
                    chains[i].limitOrderProtocol
                );
                factory.setOneInchAdapter(address(adapter));
            }
            
            vm.stopBroadcast();
            
            console.log("Factory:", address(factory));
            console.log("Adapter:", address(adapter));
            
            // Save deployment
            _saveChainDeployment(
                chains[i].chainId,
                address(factory),
                address(adapter)
            );
        }
    }
    
    function _saveChainDeployment(
        uint256 chainId,
        address factory,
        address adapter
    ) internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "factory", factory);
        vm.serializeAddress(json, "adapter", adapter);
        string memory output = vm.serializeUint(json, "chainId", chainId);
        
        string memory filename = string.concat(
            "./deployments/",
            vm.toString(chainId),
            "-deployment.json"
        );
        vm.writeJson(output, filename);
    }
}
```

## Shell Scripts

### deploy-local.sh - Local Development
```bash
#!/bin/bash
set -e

echo "🚀 Starting local deployment..."

# Start local chains
echo "Starting Anvil instances..."
anvil --chain-id 1 --port 8545 --block-time 1 > /tmp/anvil1.log 2>&1 &
ANVIL1_PID=$!
anvil --chain-id 137 --port 8546 --block-time 1 > /tmp/anvil2.log 2>&1 &
ANVIL2_PID=$!

sleep 3

# Deploy to chain 1
echo "Deploying to chain 1..."
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
LIMIT_ORDER_PROTOCOL=0x0000000000000000000000000000000000000000 \
forge script script/Deploy.s.sol:Deploy \
    --rpc-url http://localhost:8545 \
    --broadcast

# Deploy to chain 2
echo "Deploying to chain 137..."
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
LIMIT_ORDER_PROTOCOL=0x0000000000000000000000000000000000000000 \
forge script script/Deploy.s.sol:Deploy \
    --rpc-url http://localhost:8546 \
    --broadcast

echo "✅ Deployment complete!"
echo "Anvil PIDs: $ANVIL1_PID, $ANVIL2_PID"
echo "Run 'kill $ANVIL1_PID $ANVIL2_PID' to stop chains"

# Save PIDs for cleanup
echo "$ANVIL1_PID" > /tmp/anvil1.pid
echo "$ANVIL2_PID" > /tmp/anvil2.pid
```

### deploy-testnet.sh - Testnet Deployment
```bash
#!/bin/bash
set -e

# Load environment variables
source .env

echo "🚀 Deploying to testnets..."

# Supported networks
NETWORKS=("sepolia" "mumbai" "arbitrum-sepolia" "base-sepolia")

for NETWORK in "${NETWORKS[@]}"; do
    echo "Deploying to $NETWORK..."
    
    # Get RPC URL variable name
    RPC_VAR="${NETWORK^^}_RPC_URL"
    RPC_VAR="${RPC_VAR//-/_}"
    RPC_URL="${!RPC_VAR}"
    
    if [ -z "$RPC_URL" ]; then
        echo "Warning: No RPC URL for $NETWORK, skipping..."
        continue
    fi
    
    # Deploy
    forge script script/Deploy.s.sol:Deploy \
        --rpc-url "$RPC_URL" \
        --broadcast \
        --verify \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        -vvv
    
    echo "✅ Deployed to $NETWORK"
done

echo "🎉 All deployments complete!"
```

### setup-demo.sh - Complete Demo Setup
```bash
#!/bin/bash
set -e

echo "🎬 Setting up complete demo environment..."

# Step 1: Deploy contracts
echo "Step 1: Deploying contracts..."
./scripts/deploy-local.sh

# Step 2: Deploy mock tokens
echo "Step 2: Deploying mock tokens..."
forge script script/DeployMockTokens.s.sol:DeployMockTokens \
    --rpc-url http://localhost:8545 \
    --broadcast

forge script script/DeployMockTokens.s.sol:DeployMockTokens \
    --rpc-url http://localhost:8546 \
    --broadcast

# Step 3: Setup Lightning (if Polar is running)
if command -v polar &> /dev/null; then
    echo "Step 3: Setting up Lightning network..."
    # Check if Polar network exists
    if polar networks list | grep -q "atomic-swap-demo"; then
        polar networks start atomic-swap-demo
    else
        echo "Please create 'atomic-swap-demo' network in Polar"
    fi
else
    echo "Step 3: Skipping Lightning setup (Polar not found)"
fi

# Step 4: Start resolver
echo "Step 4: Starting resolver..."
cd ../bmn-evm-resolver
deno task resolver:dev &
RESOLVER_PID=$!

# Step 5: Run demo scenario
echo "Step 5: Running demo scenario..."
sleep 5
deno task demo:atomic-swap

echo "✅ Demo setup complete!"
echo "Resolver PID: $RESOLVER_PID"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    kill $RESOLVER_PID 2>/dev/null || true
    if [ -f /tmp/anvil1.pid ]; then
        kill $(cat /tmp/anvil1.pid) 2>/dev/null || true
    fi
    if [ -f /tmp/anvil2.pid ]; then
        kill $(cat /tmp/anvil2.pid) 2>/dev/null || true
    fi
}

trap cleanup EXIT
```

## Configuration Files

### .env.example - Environment Template
```bash
# Private key for deployment (DO NOT COMMIT!)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# RPC URLs
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
MUMBAI_RPC_URL=https://polygon-mumbai.g.alchemy.com/v2/YOUR_KEY

# Contract addresses
LIMIT_ORDER_PROTOCOL=0x1111111254EEB25477B68fb85Ed929f73A960582
RESOLVER_ADDRESS=0x...

# API Keys
ETHERSCAN_API_KEY=YOUR_KEY
POLYGONSCAN_API_KEY=YOUR_KEY
```

### foundry.toml - Foundry Configuration
```toml
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200

[profile.deploy]
optimizer = true
optimizer_runs = 10000
via_ir = true

[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }
polygon = { key = "${POLYGONSCAN_API_KEY}" }
sepolia = { key = "${ETHERSCAN_API_KEY}" }
mumbai = { key = "${POLYGONSCAN_API_KEY}" }

[rpc_endpoints]
mainnet = "${ETH_RPC_URL}"
polygon = "${POLYGON_RPC_URL}"
sepolia = "${SEPOLIA_RPC_URL}"
mumbai = "${MUMBAI_RPC_URL}"
localhost = "http://localhost:8545"
```

## Quick Commands

### Deploy Everything Locally
```bash
make deploy-local
```

### Deploy to Specific Network
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify
```

### Verify Contracts
```bash
forge verify-contract <ADDRESS> SimpleEscrowFactory --chain sepolia
```

### Generate Deployment Report
```bash
forge script script/GenerateReport.s.sol:GenerateReport
```

## Deployment Checklist

### Pre-Deployment
- [ ] Set up environment variables
- [ ] Fund deployer wallet
- [ ] Test on local fork first
- [ ] Review gas prices

### Deployment
- [ ] Deploy SimpleEscrowFactory
- [ ] Deploy OneInchAdapter (if needed)
- [ ] Deploy LightningBridge (if needed)
- [ ] Verify all contracts
- [ ] Test basic functionality

### Post-Deployment
- [ ] Update resolver configuration
- [ ] Run integration tests
- [ ] Document addresses
- [ ] Set up monitoring

## Common Issues

### Issue: CREATE2 Address Mismatch
```bash
# Ensure same bytecode on all chains
forge verify-contract --show-standard-json-input <ADDRESS> SimpleEscrowFactory
```

### Issue: Gas Price Too High
```bash
# Use legacy gas pricing
--legacy
```

### Issue: Verification Fails
```bash
# Manual verification with flattened source
forge flatten contracts/SimpleEscrow.sol > SimpleEscrow_flat.sol
```

Remember: For hackathon, focus on getting it deployed and working. Optimization can come later!