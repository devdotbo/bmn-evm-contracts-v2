#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
AUTO_APPROVE=false
VERBOSE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -y|--yes) AUTO_APPROVE=true ;;
        -v|--verbose) VERBOSE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

echo -e "${GREEN}=== Bridge Me Not V2 - Chain Launcher ===${NC}"
echo ""

# Check if mproc is installed
if ! command -v mproc &> /dev/null; then
    echo -e "${RED}❌ mproc not found. Please install it first:${NC}"
    echo "   npm install -g mproc"
    exit 1
fi

# Check if anvil is installed
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}❌ anvil not found. Please install Foundry first:${NC}"
    echo "   curl -L https://foundry.paradigm.xyz | bash"
    exit 1
fi

# Create logs directory
mkdir -p logs
echo -e "${GREEN}✓${NC} Created logs directory"

# Clear previous logs
> logs/chains.log
> logs/base-chain.log
> logs/etherlink-chain.log
echo -e "${GREEN}✓${NC} Cleared previous logs"

# Make anvil scripts executable
chmod +x scripts/anvil-base.sh
chmod +x scripts/anvil-etherlink.sh
echo -e "${GREEN}✓${NC} Made anvil scripts executable"

# Confirmation
if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    echo -e "${YELLOW}This will start:${NC}"
    echo "  - Base chain on port 8545 (Chain ID: 8453)"
    echo "  - Etherlink chain on port 8546 (Chain ID: 42793)"
    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Start chains with mproc
echo ""
echo -e "${GREEN}Starting chains with mproc...${NC}"
echo ""

# Run mproc with the configuration
cd scripts && mproc -c mproc.yaml 2>&1 | tee -a ../logs/chains.log