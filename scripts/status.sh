#!/bin/bash
# Combined status and balance script for BMN V2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log output
LOG_FILE="logs/status.log"
mkdir -p logs
> "$LOG_FILE"

echo -e "${BLUE}=== Bridge Me Not V2 - System Status ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to check if port is open
check_port() {
    local port=$1
    nc -z localhost $port 2>/dev/null
    return $?
}

# Function to get chain ID
get_chain_id() {
    local port=$1
    local chain_id=$(cast chain-id --rpc-url http://localhost:$port 2>/dev/null)
    echo $chain_id
}

# Function to get latest block
get_block_number() {
    local port=$1
    local block=$(cast block-number --rpc-url http://localhost:$port 2>/dev/null)
    echo $block
}

# Function to get balance
get_balance() {
    local address=$1
    local port=$2
    local balance=$(cast balance $address --rpc-url http://localhost:$port 2>/dev/null)
    if [ ! -z "$balance" ]; then
        echo $(cast to-unit $balance ether) "ETH"
    else
        echo "N/A"
    fi
}

# Check chain status
echo -e "${YELLOW}Chain Status:${NC}" | tee -a "$LOG_FILE"
echo "─────────────" | tee -a "$LOG_FILE"

# Base chain
if check_port 8545; then
    CHAIN_ID=$(get_chain_id 8545)
    BLOCK=$(get_block_number 8545)
    echo -e "Base (8545):      ${GREEN}✓ RUNNING${NC}" | tee -a "$LOG_FILE"
    echo "  Chain ID:       $CHAIN_ID" | tee -a "$LOG_FILE"
    echo "  Latest Block:   $BLOCK" | tee -a "$LOG_FILE"
else
    echo -e "Base (8545):      ${RED}✗ NOT RUNNING${NC}" | tee -a "$LOG_FILE"
fi

# Etherlink chain
if check_port 8546; then
    CHAIN_ID=$(get_chain_id 8546)
    BLOCK=$(get_block_number 8546)
    echo -e "Etherlink (8546): ${GREEN}✓ RUNNING${NC}" | tee -a "$LOG_FILE"
    echo "  Chain ID:       $CHAIN_ID" | tee -a "$LOG_FILE"
    echo "  Latest Block:   $BLOCK" | tee -a "$LOG_FILE"
else
    echo -e "Etherlink (8546): ${RED}✗ NOT RUNNING${NC}" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"

# Check deployments
if [ -f "deployment.json" ]; then
    echo -e "${YELLOW}Deployment Status:${NC}" | tee -a "$LOG_FILE"
    echo "──────────────────" | tee -a "$LOG_FILE"
    
    # Parse deployment file
    if command -v jq &> /dev/null; then
        echo "Contracts deployed ✓" | tee -a "$LOG_FILE"
        
        # Extract addresses (simplified - adjust based on actual structure)
        BASE_FACTORY=$(jq -r '.base.factory // empty' deployment.json 2>/dev/null)
        ETHERLINK_FACTORY=$(jq -r '.etherlink.factory // empty' deployment.json 2>/dev/null)
        
        if [ ! -z "$BASE_FACTORY" ]; then
            echo "  Base Factory:      $BASE_FACTORY" | tee -a "$LOG_FILE"
        fi
        if [ ! -z "$ETHERLINK_FACTORY" ]; then
            echo "  Etherlink Factory: $ETHERLINK_FACTORY" | tee -a "$LOG_FILE"
        fi
    else
        echo "Deployment file exists (install jq for details)" | tee -a "$LOG_FILE"
    fi
else
    echo -e "${YELLOW}Deployment Status:${NC} ${RED}Not deployed${NC}" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"

# Account balances
echo -e "${YELLOW}Account Balances:${NC}" | tee -a "$LOG_FILE"
echo "─────────────────" | tee -a "$LOG_FILE"

# Load addresses from .env
if [ -f ".env" ]; then
    source .env
    
    # Alice
    ALICE_ADDR=$(cast wallet address --private-key ${ALICE_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80} 2>/dev/null)
    if [ ! -z "$ALICE_ADDR" ]; then
        echo "Alice ($ALICE_ADDR):" | tee -a "$LOG_FILE"
        if check_port 8545; then
            echo "  Base:      $(get_balance $ALICE_ADDR 8545)" | tee -a "$LOG_FILE"
        fi
        if check_port 8546; then
            echo "  Etherlink: $(get_balance $ALICE_ADDR 8546)" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Bob
    BOB_ADDR=$(cast wallet address --private-key ${BOB_PRIVATE_KEY:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d} 2>/dev/null)
    if [ ! -z "$BOB_ADDR" ]; then
        echo "Bob ($BOB_ADDR):" | tee -a "$LOG_FILE"
        if check_port 8545; then
            echo "  Base:      $(get_balance $BOB_ADDR 8545)" | tee -a "$LOG_FILE"
        fi
        if check_port 8546; then
            echo "  Etherlink: $(get_balance $BOB_ADDR 8546)" | tee -a "$LOG_FILE"
        fi
    fi
fi

echo "" | tee -a "$LOG_FILE"

# Process status
echo -e "${YELLOW}Process Status:${NC}" | tee -a "$LOG_FILE"
echo "───────────────" | tee -a "$LOG_FILE"

# Check for mproc
if pgrep -f "mproc.*mproc.yaml" > /dev/null; then
    echo -e "mproc:     ${GREEN}✓ RUNNING${NC}" | tee -a "$LOG_FILE"
else
    echo -e "mproc:     ${RED}✗ NOT RUNNING${NC}" | tee -a "$LOG_FILE"
fi

# Check for anvil processes
ANVIL_COUNT=$(pgrep -f "anvil" | wc -l)
if [ $ANVIL_COUNT -gt 0 ]; then
    echo -e "anvil:     ${GREEN}✓ $ANVIL_COUNT instance(s) running${NC}" | tee -a "$LOG_FILE"
else
    echo -e "anvil:     ${RED}✗ NOT RUNNING${NC}" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"

# Log files status
echo -e "${YELLOW}Log Files:${NC}" | tee -a "$LOG_FILE"
echo "──────────" | tee -a "$LOG_FILE"

if [ -d "logs" ]; then
    for log in logs/*.log; do
        if [ -f "$log" ]; then
            SIZE=$(du -h "$log" | cut -f1)
            echo "  $(basename $log): $SIZE" | tee -a "$LOG_FILE"
        fi
    done
else
    echo "  No log directory found" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo -e "${GREEN}Status check complete. Full log saved to: $LOG_FILE${NC}"