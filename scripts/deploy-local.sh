#!/bin/bash
set -e

echo "🚀 Starting local deployment..."

# Check if anvil is installed
if ! command -v anvil &> /dev/null; then
    echo "❌ Anvil not found. Please install Foundry first."
    echo "Run: curl -L https://foundry.paradigm.xyz | bash"
    exit 1
fi

# Start local chains
echo "Starting Anvil instances..."
anvil --chain-id 1 --port 8545 --block-time 1 > /tmp/anvil1.log 2>&1 &
ANVIL1_PID=$!
echo "Started Anvil on port 8545 (Chain ID: 1) - PID: $ANVIL1_PID"

anvil --chain-id 137 --port 8546 --block-time 1 > /tmp/anvil2.log 2>&1 &
ANVIL2_PID=$!
echo "Started Anvil on port 8546 (Chain ID: 137) - PID: $ANVIL2_PID"

# Wait for chains to start
sleep 3

# Use default test private key if not set
PRIVATE_KEY=${PRIVATE_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}

# Deploy to chain 1
echo ""
echo "Deploying to chain 1..."
PRIVATE_KEY=$PRIVATE_KEY \
LIMIT_ORDER_PROTOCOL=0x0000000000000000000000000000000000000000 \
forge script script/Deploy.s.sol:Deploy \
    --rpc-url http://localhost:8545 \
    --broadcast \
    -vvv

# Deploy to chain 137
echo ""
echo "Deploying to chain 137..."
PRIVATE_KEY=$PRIVATE_KEY \
LIMIT_ORDER_PROTOCOL=0x0000000000000000000000000000000000000000 \
forge script script/Deploy.s.sol:Deploy \
    --rpc-url http://localhost:8546 \
    --broadcast \
    -vvv

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Anvil processes running:"
echo "  - Chain 1 (port 8545): PID $ANVIL1_PID"
echo "  - Chain 137 (port 8546): PID $ANVIL2_PID"
echo ""
echo "To stop the chains, run:"
echo "  kill $ANVIL1_PID $ANVIL2_PID"
echo ""
echo "Deployment artifacts saved in ./deployments/"

# Save PIDs for cleanup
echo "$ANVIL1_PID" > /tmp/anvil1.pid
echo "$ANVIL2_PID" > /tmp/anvil2.pid

# Show deployed addresses
echo ""
echo "Deployed contracts:"
if [ -f "./deployments/1-deployment.json" ]; then
    echo "Chain 1:"
    cat ./deployments/1-deployment.json | jq -r '{ factory: .factory, adapter: .adapter }'
fi
if [ -f "./deployments/137-deployment.json" ]; then
    echo "Chain 137:"
    cat ./deployments/137-deployment.json | jq -r '{ factory: .factory, adapter: .adapter }'
fi