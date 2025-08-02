#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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
LOG_FILE="logs/fund-accounts.log"
mkdir -p logs
> "$LOG_FILE"

echo -e "${BLUE}=== Bridge Me Not V2 - Fund Test Accounts ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Load environment
if [ -f ".env" ]; then
    source .env
fi

# Check deployment exists
if [ ! -f "deployment.json" ]; then
    echo -e "${RED}Error: deployment.json not found!${NC}" | tee -a "$LOG_FILE"
    echo "Please run deploy.sh first" | tee -a "$LOG_FILE"
    exit 1
fi

# Extract contract addresses
BASE_USDC=$(jq -r '.base.usdc // empty' deployment.json 2>/dev/null)
ETHERLINK_XTZ=$(jq -r '.etherlink.xtz // empty' deployment.json 2>/dev/null)

if [ -z "$BASE_USDC" ] || [ -z "$ETHERLINK_XTZ" ]; then
    echo -e "${RED}Error: Could not find token addresses in deployment.json${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Default test accounts
ALICE=${ALICE_ADDRESS:-"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"}
BOB=${BOB_ADDRESS:-"0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"}
ALICE_KEY=${ALICE_PRIVATE_KEY:-"0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"}
BOB_KEY=${BOB_PRIVATE_KEY:-"0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"}

# Deployer key (for minting)
DEPLOYER_KEY=${PRIVATE_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}

# Token amounts
USDC_AMOUNT="1000000000" # 1000 USDC (6 decimals)
XTZ_AMOUNT="1000000000000000000000" # 1000 XTZ (18 decimals)

echo "Token addresses:" | tee -a "$LOG_FILE"
echo "  Base USDC:      $BASE_USDC" | tee -a "$LOG_FILE"
echo "  Etherlink XTZ:  $ETHERLINK_XTZ" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Test accounts:" | tee -a "$LOG_FILE"
echo "  Alice: $ALICE" | tee -a "$LOG_FILE"
echo "  Bob:   $BOB" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Confirmation
if [ "$AUTO_APPROVE" = false ]; then
    echo "This will:" | tee -a "$LOG_FILE"
    echo "  - Mint 1000 USDC to Alice and Bob on Base" | tee -a "$LOG_FILE"
    echo "  - Mint 1000 XTZ to Alice and Bob on Etherlink" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Fund Base chain accounts with USDC
echo -e "${YELLOW}Funding Base accounts with USDC...${NC}" | tee -a "$LOG_FILE"

echo "  Minting USDC to Alice..." | tee -a "$LOG_FILE"
cast send $BASE_USDC "mint(address,uint256)" $ALICE $USDC_AMOUNT \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    >> "$LOG_FILE" 2>&1
echo -e "  ${GREEN}✓${NC} Minted 1000 USDC to Alice" | tee -a "$LOG_FILE"

echo "  Minting USDC to Bob..." | tee -a "$LOG_FILE"
cast send $BASE_USDC "mint(address,uint256)" $BOB $USDC_AMOUNT \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8545 \
    >> "$LOG_FILE" 2>&1
echo -e "  ${GREEN}✓${NC} Minted 1000 USDC to Bob" | tee -a "$LOG_FILE"

# Fund Etherlink chain accounts with XTZ
echo "" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Funding Etherlink accounts with XTZ...${NC}" | tee -a "$LOG_FILE"

echo "  Minting XTZ to Alice..." | tee -a "$LOG_FILE"
cast send $ETHERLINK_XTZ "mint(address,uint256)" $ALICE $XTZ_AMOUNT \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8546 \
    >> "$LOG_FILE" 2>&1
echo -e "  ${GREEN}✓${NC} Minted 1000 XTZ to Alice" | tee -a "$LOG_FILE"

echo "  Minting XTZ to Bob..." | tee -a "$LOG_FILE"
cast send $ETHERLINK_XTZ "mint(address,uint256)" $BOB $XTZ_AMOUNT \
    --private-key $DEPLOYER_KEY \
    --rpc-url http://localhost:8546 \
    >> "$LOG_FILE" 2>&1
echo -e "  ${GREEN}✓${NC} Minted 1000 XTZ to Bob" | tee -a "$LOG_FILE"

# Verify balances
echo "" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Verifying balances...${NC}" | tee -a "$LOG_FILE"

# Check USDC balances
ALICE_USDC=$(cast call $BASE_USDC "balanceOf(address)(uint256)" $ALICE --rpc-url http://localhost:8545 2>/dev/null)
BOB_USDC=$(cast call $BASE_USDC "balanceOf(address)(uint256)" $BOB --rpc-url http://localhost:8545 2>/dev/null)

# Check XTZ balances
ALICE_XTZ=$(cast call $ETHERLINK_XTZ "balanceOf(address)(uint256)" $ALICE --rpc-url http://localhost:8546 2>/dev/null)
BOB_XTZ=$(cast call $ETHERLINK_XTZ "balanceOf(address)(uint256)" $BOB --rpc-url http://localhost:8546 2>/dev/null)

echo "" | tee -a "$LOG_FILE"
echo "Final balances:" | tee -a "$LOG_FILE"
echo "  Base USDC:" | tee -a "$LOG_FILE"
echo "    Alice: $(cast to-unit $ALICE_USDC 6) USDC" | tee -a "$LOG_FILE"
echo "    Bob:   $(cast to-unit $BOB_USDC 6) USDC" | tee -a "$LOG_FILE"
echo "  Etherlink XTZ:" | tee -a "$LOG_FILE"
echo "    Alice: $(cast to-unit $ALICE_XTZ ether) XTZ" | tee -a "$LOG_FILE"
echo "    Bob:   $(cast to-unit $BOB_XTZ ether) XTZ" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo -e "${GREEN}=== Funding Complete ===${NC}" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"