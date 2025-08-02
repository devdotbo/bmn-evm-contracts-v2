#!/bin/bash
set -e

# Bridge Me Not V2 - Start Chains Script
# Launches two anvil chains using mproc for parallel execution

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parse command line arguments
AUTO_APPROVE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_APPROVE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-y|--yes] [-v|--verbose]"
            echo "  -y, --yes      Auto-approve all prompts"
            echo "  -v, --verbose  Enable verbose output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Bridge Me Not V2 - Chain Management${NC}"
echo "===================================="

# Check if mproc is installed
if ! command -v mproc &> /dev/null; then
    echo -e "${RED}Error: mproc is not installed${NC}"
    echo "Please install mproc: npm install -g mproc"
    exit 1
fi

# Check if anvil is installed
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}Error: anvil is not installed${NC}"
    echo "Please install Foundry: curl -L https://foundry.paradigm.xyz | bash"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Check if chains are already running
if pgrep -f "anvil.*8545" > /dev/null || pgrep -f "anvil.*8546" > /dev/null; then
    echo -e "${YELLOW}Warning: Anvil processes are already running${NC}"
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Do you want to stop them and start fresh? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting..."
            exit 0
        fi
    fi
    echo "Stopping existing anvil processes..."
    pkill -f "anvil" || true
    sleep 2
fi

# Reset log file
> logs/chains.log

echo -e "${GREEN}Starting chains...${NC}"
echo "Base chain: http://localhost:8545 (Chain ID: 8453)"
echo "Etherlink chain: http://localhost:8546 (Chain ID: 42793)"
echo ""

# Build anvil command with optional verbose flag
ANVIL_FLAGS=""
if [ "$VERBOSE" = true ]; then
    ANVIL_FLAGS="--steps-tracing"
fi

# Start chains using mproc
echo -e "${GREEN}Launching chains with mproc...${NC}"

# Create mproc configuration
cat > /tmp/bmn-chains.yml << EOF
procs:
  base:
    cmd: anvil --port 8545 --chain-id 8453 $ANVIL_FLAGS
    color: cyan
  etherlink:
    cmd: anvil --port 8546 --chain-id 42793 $ANVIL_FLAGS
    color: magenta
EOF

# Start mproc with the configuration
mproc -c /tmp/bmn-chains.yml 2>&1 | tee -a logs/chains.log &

# Store the mproc PID
MPROC_PID=$!
echo $MPROC_PID > /tmp/bmn-mproc.pid

# Wait for chains to be ready
echo -e "${YELLOW}Waiting for chains to start...${NC}"
sleep 3

# Check if chains are accessible
check_chain() {
    local port=$1
    local name=$2
    if curl -s -X POST "http://localhost:$port" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $name chain is running on port $port${NC}"
        return 0
    else
        echo -e "${RED}✗ $name chain failed to start on port $port${NC}"
        return 1
    fi
}

# Verify both chains are running
CHAINS_OK=true
if ! check_chain 8545 "Base"; then
    CHAINS_OK=false
fi
if ! check_chain 8546 "Etherlink"; then
    CHAINS_OK=false
fi

if [ "$CHAINS_OK" = false ]; then
    echo -e "${RED}Error: One or more chains failed to start${NC}"
    echo "Check logs/chains.log for details"
    # Kill mproc if chains failed
    kill $MPROC_PID 2>/dev/null || true
    exit 1
fi

echo ""
echo -e "${GREEN}Chains started successfully!${NC}"
echo "------------------------------"
echo "Base RPC: http://localhost:8545"
echo "Etherlink RPC: http://localhost:8546"
echo ""
echo "Logs: logs/chains.log"
echo "PID file: /tmp/bmn-mproc.pid"
echo ""
echo "To stop chains, run: ./scripts/cleanup.sh"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop watching logs (chains will continue running)${NC}"

# Keep the script running to show logs
wait $MPROC_PID