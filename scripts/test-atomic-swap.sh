#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log setup
LOG_FILE="logs/test-atomic-swap.log"
mkdir -p logs
> "$LOG_FILE"

echo -e "${BLUE}=== Bridge Me Not V2 - Atomic Swap Test ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check if Deno is installed
if ! command -v deno &> /dev/null; then
    echo -e "${RED}Error: Deno is not installed!${NC}" | tee -a "$LOG_FILE"
    echo "Please install Deno: https://deno.land/manual/getting_started/installation" | tee -a "$LOG_FILE"
    exit 1
fi

# Check if test directory exists
TEST_DIR="test-atomic-swap"
if [ ! -d "$TEST_DIR" ]; then
    echo -e "${RED}Error: Test directory '$TEST_DIR' not found!${NC}" | tee -a "$LOG_FILE"
    echo "Please ensure the Deno test suite is set up" | tee -a "$LOG_FILE"
    exit 1
fi

# Check if deployment exists
if [ ! -f "deployment.json" ]; then
    echo -e "${RED}Error: deployment.json not found!${NC}" | tee -a "$LOG_FILE"
    echo "Please run deploy.sh first" | tee -a "$LOG_FILE"
    exit 1
fi

# Check chains are running
echo -e "${YELLOW}Checking chain connectivity...${NC}" | tee -a "$LOG_FILE"
if ! nc -z localhost 8545 2>/dev/null; then
    echo -e "${RED}Error: Base chain (port 8545) is not running!${NC}" | tee -a "$LOG_FILE"
    exit 1
fi
if ! nc -z localhost 8546 2>/dev/null; then
    echo -e "${RED}Error: Etherlink chain (port 8546) is not running!${NC}" | tee -a "$LOG_FILE"
    exit 1
fi
echo -e "${GREEN}✓${NC} Both chains are accessible" | tee -a "$LOG_FILE"

# Set environment variables for the test
export BASE_RPC_URL="http://localhost:8545"
export ETHERLINK_RPC_URL="http://localhost:8546"
export DEPLOYMENT_FILE="deployment.json"

# Load test accounts from .env if available
if [ -f ".env" ]; then
    source .env
fi

# Run the Deno test
echo "" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Running atomic swap test...${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

cd "$TEST_DIR"

# Check if verbose mode is enabled
if [ "$VERBOSE" = "true" ]; then
    echo "Running in verbose mode..." | tee -a "../$LOG_FILE"
    deno run --allow-net --allow-read --allow-env test-atomic-swap.ts 2>&1 | tee -a "../$LOG_FILE"
else
    deno run --allow-net --allow-read --allow-env test-atomic-swap.ts >> "../$LOG_FILE" 2>&1
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ Atomic swap test completed successfully!${NC}" | tee -a "../$LOG_FILE"
    else
        echo -e "${RED}✗ Atomic swap test failed!${NC}" | tee -a "../$LOG_FILE"
        echo "Check the log file for details: $LOG_FILE"
        exit $EXIT_CODE
    fi
fi

cd ..

echo "" | tee -a "$LOG_FILE"
echo "Test log saved to: $LOG_FILE"