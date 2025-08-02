#!/bin/bash

# Bridge Me Not V2 Multi-Chain Deployment Script
# Deploys to Base (localhost:8545) and Etherlink (localhost:8546)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/deploy.log"
DEPLOYMENT_FILE="$PROJECT_ROOT/deployment.json"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# Default values
BASE_RPC="${BASE_RPC:-http://localhost:8545}"
ETHERLINK_RPC="${ETHERLINK_RPC:-http://localhost:8546}"
PRIVATE_KEY="${PRIVATE_KEY}"
NON_INTERACTIVE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-y|--yes]"
            exit 1
            ;;
    esac
done

# Function to log messages
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} $message"
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Function to log errors
log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[$timestamp] ERROR:${NC} $message"
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
}

# Function to log success
log_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp] SUCCESS:${NC} $message"
    echo "[$timestamp] SUCCESS: $message" >> "$LOG_FILE"
}

# Function to check if RPC endpoint is available
check_rpc() {
    local rpc_url="$1"
    local chain_name="$2"
    
    log "Checking $chain_name RPC at $rpc_url..."
    
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$rpc_url" > /dev/null 2>&1; then
        log_success "$chain_name RPC is available"
        return 0
    else
        log_error "$chain_name RPC at $rpc_url is not available"
        return 1
    fi
}

# Function to deploy contract
deploy_contract() {
    local script_name="$1"
    local rpc_url="$2"
    local chain_name="$3"
    local extra_args="${4:-}"
    
    log "Deploying $script_name to $chain_name..."
    
    local cmd="forge script $script_name --rpc-url $rpc_url --private-key $PRIVATE_KEY --broadcast -vvv"
    
    if [ ! -z "$extra_args" ]; then
        cmd="$cmd $extra_args"
    fi
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log_success "Deployed $script_name to $chain_name"
        return 0
    else
        log_error "Failed to deploy $script_name to $chain_name"
        return 1
    fi
}

# Function to extract deployed address from broadcast files
extract_address() {
    local chain_id="$1"
    local contract_name="$2"
    local broadcast_dir="$PROJECT_ROOT/broadcast"
    
    # Find the most recent broadcast file for the chain
    local broadcast_file=$(find "$broadcast_dir" -name "run-latest.json" -path "*/$chain_id/*" 2>/dev/null | head -1)
    
    if [ -f "$broadcast_file" ]; then
        # Extract address for the contract
        local address=$(jq -r ".transactions[] | select(.contractName == \"$contract_name\") | .contractAddress" "$broadcast_file" 2>/dev/null | head -1)
        
        if [ ! -z "$address" ] && [ "$address" != "null" ]; then
            echo "$address"
            return 0
        fi
    fi
    
    echo ""
    return 1
}

# Initialize deployment
initialize() {
    log "Initializing Bridge Me Not V2 deployment..."
    
    # Create logs directory
    mkdir -p "$LOG_DIR"
    
    # Reset log file
    echo "Bridge Me Not V2 Deployment Log - $(date)" > "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    
    # Check if private key is set
    if [ -z "$PRIVATE_KEY" ]; then
        log_error "PRIVATE_KEY not set in environment"
        exit 1
    fi
    
    # Confirmation prompt
    if [ "$NON_INTERACTIVE" = false ]; then
        echo -e "${YELLOW}You are about to deploy Bridge Me Not V2 contracts to:${NC}"
        echo "  - Base: $BASE_RPC"
        echo "  - Etherlink: $ETHERLINK_RPC"
        echo ""
        read -p "Continue? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Main deployment function
main() {
    initialize
    
    # Check RPC endpoints
    log "Checking RPC endpoints..."
    if ! check_rpc "$BASE_RPC" "Base"; then
        exit 1
    fi
    if ! check_rpc "$ETHERLINK_RPC" "Etherlink"; then
        exit 1
    fi
    
    # Compile contracts
    log "Compiling contracts..."
    if forge build >> "$LOG_FILE" 2>&1; then
        log_success "Contracts compiled successfully"
    else
        log_error "Failed to compile contracts"
        exit 1
    fi
    
    # Initialize deployment JSON
    echo "{
  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"chains\": {}" > "$DEPLOYMENT_FILE"
    
    # Deploy to Base
    log ""
    log "=== DEPLOYING TO BASE ==="
    
    # Deploy Mock USDC
    if deploy_contract "script/deploy/DeployMockUSDC.s.sol" "$BASE_RPC" "Base"; then
        USDC_ADDRESS=$(extract_address "31337" "MockUSDC")
        if [ ! -z "$USDC_ADDRESS" ]; then
            log "Mock USDC deployed at: $USDC_ADDRESS"
        fi
    fi
    
    # Deploy SimpleEscrowFactory
    if deploy_contract "script/deploy/DeploySimpleEscrowFactory.s.sol" "$BASE_RPC" "Base"; then
        FACTORY_BASE_ADDRESS=$(extract_address "31337" "SimpleEscrowFactory")
        if [ ! -z "$FACTORY_BASE_ADDRESS" ]; then
            log "SimpleEscrowFactory deployed at: $FACTORY_BASE_ADDRESS"
        fi
    fi
    
    # Deploy OneInchAdapter (if script exists)
    if [ -f "$PROJECT_ROOT/script/deploy/DeployOneInchAdapter.s.sol" ]; then
        if deploy_contract "script/deploy/DeployOneInchAdapter.s.sol" "$BASE_RPC" "Base"; then
            ONEINCH_ADDRESS=$(extract_address "31337" "OneInchAdapter")
            if [ ! -z "$ONEINCH_ADDRESS" ]; then
                log "OneInchAdapter deployed at: $ONEINCH_ADDRESS"
            fi
        fi
    fi
    
    # Update deployment.json for Base
    jq --arg usdc "$USDC_ADDRESS" \
       --arg factory "$FACTORY_BASE_ADDRESS" \
       --arg oneinch "$ONEINCH_ADDRESS" \
       '.chains.base = {
          "chainId": 31337,
          "rpcUrl": "'$BASE_RPC'",
          "contracts": {
            "MockUSDC": $usdc,
            "SimpleEscrowFactory": $factory,
            "OneInchAdapter": $oneinch
          }
        }' "$DEPLOYMENT_FILE" > "$DEPLOYMENT_FILE.tmp" && mv "$DEPLOYMENT_FILE.tmp" "$DEPLOYMENT_FILE"
    
    # Deploy to Etherlink
    log ""
    log "=== DEPLOYING TO ETHERLINK ==="
    
    # Deploy Mock XTZ
    if deploy_contract "script/deploy/DeployMockXTZ.s.sol" "$ETHERLINK_RPC" "Etherlink"; then
        XTZ_ADDRESS=$(extract_address "31338" "MockXTZ")
        if [ ! -z "$XTZ_ADDRESS" ]; then
            log "Mock XTZ deployed at: $XTZ_ADDRESS"
        fi
    fi
    
    # Deploy SimpleEscrowFactory
    if deploy_contract "script/deploy/DeploySimpleEscrowFactory.s.sol" "$ETHERLINK_RPC" "Etherlink"; then
        FACTORY_ETHERLINK_ADDRESS=$(extract_address "31338" "SimpleEscrowFactory")
        if [ ! -z "$FACTORY_ETHERLINK_ADDRESS" ]; then
            log "SimpleEscrowFactory deployed at: $FACTORY_ETHERLINK_ADDRESS"
        fi
    fi
    
    # Deploy LightningBridge (if script exists)
    if [ -f "$PROJECT_ROOT/script/deploy/DeployLightningBridge.s.sol" ]; then
        if deploy_contract "script/deploy/DeployLightningBridge.s.sol" "$ETHERLINK_RPC" "Etherlink"; then
            LIGHTNING_ADDRESS=$(extract_address "31338" "LightningBridge")
            if [ ! -z "$LIGHTNING_ADDRESS" ]; then
                log "LightningBridge deployed at: $LIGHTNING_ADDRESS"
            fi
        fi
    fi
    
    # Update deployment.json for Etherlink
    jq --arg xtz "$XTZ_ADDRESS" \
       --arg factory "$FACTORY_ETHERLINK_ADDRESS" \
       --arg lightning "$LIGHTNING_ADDRESS" \
       '.chains.etherlink = {
          "chainId": 31338,
          "rpcUrl": "'$ETHERLINK_RPC'",
          "contracts": {
            "MockXTZ": $xtz,
            "SimpleEscrowFactory": $factory,
            "LightningBridge": $lightning
          }
        }' "$DEPLOYMENT_FILE" > "$DEPLOYMENT_FILE.tmp" && mv "$DEPLOYMENT_FILE.tmp" "$DEPLOYMENT_FILE"
    
    # Summary
    log ""
    log "=== DEPLOYMENT SUMMARY ==="
    log_success "All contracts deployed successfully!"
    log ""
    log "Base Contracts:"
    log "  - Mock USDC: ${USDC_ADDRESS:-Not deployed}"
    log "  - SimpleEscrowFactory: ${FACTORY_BASE_ADDRESS:-Not deployed}"
    log "  - OneInchAdapter: ${ONEINCH_ADDRESS:-Not deployed}"
    log ""
    log "Etherlink Contracts:"
    log "  - Mock XTZ: ${XTZ_ADDRESS:-Not deployed}"
    log "  - SimpleEscrowFactory: ${FACTORY_ETHERLINK_ADDRESS:-Not deployed}"
    log "  - LightningBridge: ${LIGHTNING_ADDRESS:-Not deployed}"
    log ""
    log "Deployment addresses saved to: $DEPLOYMENT_FILE"
    log "Full deployment log: $LOG_FILE"
}

# Run main function
main