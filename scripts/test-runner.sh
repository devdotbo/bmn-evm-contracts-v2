#!/bin/bash

# Test Runner for Atomic Swap Tests
# This script integrates with mprocs to run Deno tests

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"

# Function to log messages
log() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if chains are running
check_chains() {
    log "Checking if chains are running..."
    
    # Check Base chain
    if ! curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 > /dev/null 2>&1; then
        log_error "Base chain not running on port 8545"
        return 1
    fi
    
    # Check Etherlink chain
    if ! curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8546 > /dev/null 2>&1; then
        log_error "Etherlink chain not running on port 8546"
        return 1
    fi
    
    log "Both chains are running ✓"
    return 0
}

# Check if contracts are deployed
check_deployment() {
    log "Checking deployment status..."
    
    if [ ! -f "$PROJECT_ROOT/deployment.json" ]; then
        log_error "deployment.json not found. Please run deployment script first."
        return 1
    fi
    
    # Validate JSON
    if ! jq . "$PROJECT_ROOT/deployment.json" > /dev/null 2>&1; then
        log_error "deployment.json is invalid JSON"
        return 1
    fi
    
    log "Deployment found ✓"
    return 0
}

# Run Deno tests
run_tests() {
    log "Running atomic swap tests..."
    
    cd "$SCRIPT_DIR"
    
    # Copy ABIs if needed
    if [ ! -d "abis" ] || [ ! -f "abis/index.ts" ]; then
        log "Extracting contract ABIs..."
        ./copy-abis.sh
    fi
    
    # Run the test
    if deno run --allow-all test-atomic-swap.ts; then
        log "Tests completed successfully ✓"
        return 0
    else
        log_error "Tests failed"
        return 1
    fi
}

# Main function
main() {
    log "Starting test runner..."
    
    # Create logs directory
    mkdir -p "$LOG_DIR"
    
    # Pre-flight checks
    if ! check_chains; then
        log_error "Please start chains first with: mprocs -c mproc.yaml"
        exit 1
    fi
    
    if ! check_deployment; then
        log_error "Please deploy contracts first with: ./scripts/deploy.sh"
        exit 1
    fi
    
    # Run tests
    if run_tests; then
        log "All tests passed! ✨"
        exit 0
    else
        log_error "Test run failed"
        exit 1
    fi
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi