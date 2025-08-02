#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
AUTO_APPROVE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -y|--yes) AUTO_APPROVE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Log setup
LOG_FILE="logs/deploy.log"
mkdir -p logs
> "$LOG_FILE"

echo -e "${BLUE}=== Bridge Me Not V2 - Multi-Chain Deployment ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Load environment
if [ -f ".env" ]; then
    source .env
fi

# Default to test key if not set
DEPLOYER_KEY=${PRIVATE_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}
DEPLOYER_ADDR=$(cast wallet address --private-key $DEPLOYER_KEY)

echo "Deployer: $DEPLOYER_ADDR" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check chains are running
echo -e "${YELLOW}Checking chain status...${NC}" | tee -a "$LOG_FILE"

BASE_RUNNING=false
ETHERLINK_RUNNING=false

if nc -z localhost 8545 2>/dev/null; then
    BASE_RUNNING=true
    echo -e "  Base (8545):      ${GREEN}✓ Running${NC}" | tee -a "$LOG_FILE"
else
    echo -e "  Base (8545):      ${RED}✗ Not running${NC}" | tee -a "$LOG_FILE"
fi

if nc -z localhost 8546 2>/dev/null; then
    ETHERLINK_RUNNING=true
    echo -e "  Etherlink (8546): ${GREEN}✓ Running${NC}" | tee -a "$LOG_FILE"
else
    echo -e "  Etherlink (8546): ${RED}✗ Not running${NC}" | tee -a "$LOG_FILE"
fi

if [ "$BASE_RUNNING" = false ] || [ "$ETHERLINK_RUNNING" = false ]; then
    echo "" | tee -a "$LOG_FILE"
    echo -e "${RED}Error: Both chains must be running!${NC}" | tee -a "$LOG_FILE"
    echo "Run: ./scripts/start-chains.sh" | tee -a "$LOG_FILE"
    exit 1
fi

echo "" | tee -a "$LOG_FILE"

# Confirmation
if [ "$AUTO_APPROVE" = false ]; then
    echo "This will deploy:" | tee -a "$LOG_FILE"
    echo "  - SimpleEscrowFactory to both chains" | tee -a "$LOG_FILE"
    echo "  - Mock USDC to Base" | tee -a "$LOG_FILE"
    echo "  - Mock XTZ to Etherlink" | tee -a "$LOG_FILE"
    echo "  - OneInchAdapter to Base" | tee -a "$LOG_FILE"
    echo "  - LightningBridge to Etherlink" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Compile contracts
echo -e "${YELLOW}Building contracts...${NC}" | tee -a "$LOG_FILE"
forge build >> "$LOG_FILE" 2>&1
echo -e "${GREEN}✓${NC} Contracts compiled" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Initialize deployment JSON
DEPLOYMENT_FILE="deployment.json"
echo "{" > "$DEPLOYMENT_FILE"
echo '  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",' >> "$DEPLOYMENT_FILE"
echo '  "deployer": "'$DEPLOYER_ADDR'",' >> "$DEPLOYMENT_FILE"

# Deploy to Base
echo -e "${BLUE}Deploying to Base (localhost:8545)...${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo '  "base": {' >> "$DEPLOYMENT_FILE"
echo '    "chainId": 8453,' >> "$DEPLOYMENT_FILE"
echo '    "rpc": "http://localhost:8545",' >> "$DEPLOYMENT_FILE"

# Deploy factory
echo "  Deploying SimpleEscrowFactory..." | tee -a "$LOG_FILE"
FACTORY_OUTPUT=$(forge create src/SimpleEscrowFactory.sol:SimpleEscrowFactory \
    --constructor-args "0x0000000000000000000000000000000000000000" \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    --json 2>> "$LOG_FILE")
BASE_FACTORY=$(echo $FACTORY_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} Factory deployed at: $BASE_FACTORY" | tee -a "$LOG_FILE"
echo '    "factory": "'$BASE_FACTORY'",' >> "$DEPLOYMENT_FILE"

# Deploy USDC
echo "  Deploying Mock USDC..." | tee -a "$LOG_FILE"
USDC_OUTPUT=$(forge create src/mocks/MockERC20.sol:MockERC20 \
    --constructor-args "USD Coin" "USDC" 6 0 \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    --json 2>> "$LOG_FILE")
BASE_USDC=$(echo $USDC_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} USDC deployed at: $BASE_USDC" | tee -a "$LOG_FILE"
echo '    "usdc": "'$BASE_USDC'",' >> "$DEPLOYMENT_FILE"

# Deploy OneInchAdapter
echo "  Deploying OneInchAdapter..." | tee -a "$LOG_FILE"
# First deploy mock limit order protocol
MOCK_LOP_OUTPUT=$(forge create test/mocks/MockLimitOrderProtocol.sol:MockLimitOrderProtocol \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    --json 2>> "$LOG_FILE")
BASE_LOP=$(echo $MOCK_LOP_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} Mock LimitOrderProtocol at: $BASE_LOP" | tee -a "$LOG_FILE"

ADAPTER_OUTPUT=$(forge create src/OneInchAdapter.sol:OneInchAdapter \
    --constructor-args $BASE_LOP $BASE_FACTORY \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    --json 2>> "$LOG_FILE")
BASE_ADAPTER=$(echo $ADAPTER_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} OneInchAdapter deployed at: $BASE_ADAPTER" | tee -a "$LOG_FILE"
echo '    "oneInchAdapter": "'$BASE_ADAPTER'",' >> "$DEPLOYMENT_FILE"
echo '    "mockLimitOrderProtocol": "'$BASE_LOP'"' >> "$DEPLOYMENT_FILE"

echo '  },' >> "$DEPLOYMENT_FILE"
echo "" | tee -a "$LOG_FILE"

# Deploy to Etherlink
echo -e "${BLUE}Deploying to Etherlink (localhost:8546)...${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo '  "etherlink": {' >> "$DEPLOYMENT_FILE"
echo '    "chainId": 42793,' >> "$DEPLOYMENT_FILE"
echo '    "rpc": "http://localhost:8546",' >> "$DEPLOYMENT_FILE"

# Deploy factory
echo "  Deploying SimpleEscrowFactory..." | tee -a "$LOG_FILE"
FACTORY_OUTPUT=$(forge create src/SimpleEscrowFactory.sol:SimpleEscrowFactory \
    --constructor-args "0x0000000000000000000000000000000000000000" \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8546 \
    --json 2>> "$LOG_FILE")
ETHERLINK_FACTORY=$(echo $FACTORY_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} Factory deployed at: $ETHERLINK_FACTORY" | tee -a "$LOG_FILE"
echo '    "factory": "'$ETHERLINK_FACTORY'",' >> "$DEPLOYMENT_FILE"

# Deploy XTZ token
echo "  Deploying Mock XTZ..." | tee -a "$LOG_FILE"
XTZ_OUTPUT=$(forge create src/mocks/MockERC20.sol:MockERC20 \
    --constructor-args "Tezos" "XTZ" 18 0 \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8546 \
    --json 2>> "$LOG_FILE")
ETHERLINK_XTZ=$(echo $XTZ_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} XTZ deployed at: $ETHERLINK_XTZ" | tee -a "$LOG_FILE"
echo '    "xtz": "'$ETHERLINK_XTZ'",' >> "$DEPLOYMENT_FILE"

# Deploy LightningBridge
echo "  Deploying LightningBridge..." | tee -a "$LOG_FILE"
BRIDGE_OUTPUT=$(forge create src/LightningBridge.sol:LightningBridge \
    --constructor-args $ETHERLINK_FACTORY \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8546 \
    --json 2>> "$LOG_FILE")
ETHERLINK_BRIDGE=$(echo $BRIDGE_OUTPUT | jq -r '.deployedTo')
echo -e "  ${GREEN}✓${NC} LightningBridge deployed at: $ETHERLINK_BRIDGE" | tee -a "$LOG_FILE"
echo '    "lightningBridge": "'$ETHERLINK_BRIDGE'"' >> "$DEPLOYMENT_FILE"

echo '  }' >> "$DEPLOYMENT_FILE"
echo '}' >> "$DEPLOYMENT_FILE"

echo "" | tee -a "$LOG_FILE"

# Configure contracts
echo -e "${YELLOW}Configuring contracts...${NC}" | tee -a "$LOG_FILE"

# Set OneInchAdapter on Base factory
echo "  Setting OneInchAdapter on Base factory..." | tee -a "$LOG_FILE"
cast send $BASE_FACTORY "setOneInchAdapter(address)" $BASE_ADAPTER \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    >> "$LOG_FILE" 2>&1
echo -e "  ${GREEN}✓${NC} OneInchAdapter configured" | tee -a "$LOG_FILE"

# Set resolver on LightningBridge
if [ ! -z "$RESOLVER_PRIVATE_KEY" ]; then
    RESOLVER_ADDR=$(cast wallet address --private-key $RESOLVER_PRIVATE_KEY)
    echo "  Setting resolver on LightningBridge..." | tee -a "$LOG_FILE"
    cast send $ETHERLINK_BRIDGE "setResolver(address)" $RESOLVER_ADDR \
        --private-key $DEPLOYER_KEY \
        --rpc-url http://localhost:8546 \
        >> "$LOG_FILE" 2>&1
    echo -e "  ${GREEN}✓${NC} Resolver configured: $RESOLVER_ADDR" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"

# Summary
echo -e "${GREEN}=== Deployment Complete ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Base Contracts:" | tee -a "$LOG_FILE"
echo "  Factory:         $BASE_FACTORY" | tee -a "$LOG_FILE"
echo "  USDC:            $BASE_USDC" | tee -a "$LOG_FILE"
echo "  OneInchAdapter:  $BASE_ADAPTER" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Etherlink Contracts:" | tee -a "$LOG_FILE"
echo "  Factory:         $ETHERLINK_FACTORY" | tee -a "$LOG_FILE"
echo "  XTZ:             $ETHERLINK_XTZ" | tee -a "$LOG_FILE"
echo "  LightningBridge: $ETHERLINK_BRIDGE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Deployment details saved to: $DEPLOYMENT_FILE" | tee -a "$LOG_FILE"
echo "Full log saved to: $LOG_FILE"