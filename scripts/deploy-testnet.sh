#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "⚠️  .env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

echo "🚀 Deploying to testnets..."

# Check if private key is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ PRIVATE_KEY not set in .env file"
    exit 1
fi

# Supported networks
NETWORKS=("sepolia" "mumbai" "arbitrum-sepolia" "base-sepolia")

# Deploy function
deploy_to_network() {
    local NETWORK=$1
    local RPC_VAR="${NETWORK^^}_RPC_URL"
    RPC_VAR="${RPC_VAR//-/_}"
    local RPC_URL="${!RPC_VAR}"
    
    if [ -z "$RPC_URL" ]; then
        echo "⚠️  No RPC URL for $NETWORK, skipping..."
        return
    fi
    
    echo ""
    echo "Deploying to $NETWORK..."
    echo "RPC URL: $RPC_URL"
    
    # Get the appropriate API key for verification
    local API_KEY_VAR="ETHERSCAN_API_KEY"
    case $NETWORK in
        mumbai)
            API_KEY_VAR="POLYGONSCAN_API_KEY"
            ;;
        arbitrum-sepolia)
            API_KEY_VAR="ARBISCAN_API_KEY"
            ;;
        base-sepolia)
            API_KEY_VAR="BASESCAN_API_KEY"
            ;;
    esac
    
    local API_KEY="${!API_KEY_VAR}"
    
    # Deploy
    if [ -n "$API_KEY" ]; then
        # Deploy with verification
        forge script script/Deploy.s.sol:Deploy \
            --rpc-url "$RPC_URL" \
            --broadcast \
            --verify \
            --etherscan-api-key "$API_KEY" \
            -vvv
    else
        # Deploy without verification
        echo "⚠️  No API key for verification, deploying without verify..."
        forge script script/Deploy.s.sol:Deploy \
            --rpc-url "$RPC_URL" \
            --broadcast \
            -vvv
    fi
    
    echo "✅ Deployed to $NETWORK"
}

# Deploy to each network
for NETWORK in "${NETWORKS[@]}"; do
    deploy_to_network "$NETWORK"
done

echo ""
echo "🎉 All deployments complete!"
echo ""
echo "Deployment artifacts saved in ./deployments/"
echo ""
echo "To verify contracts manually, run:"
echo "  forge script script/Verify.s.sol:Verify --rpc-url <NETWORK_RPC_URL>"