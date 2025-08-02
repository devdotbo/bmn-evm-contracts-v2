#!/bin/bash
set -e

# Script to copy compiled contract ABIs to scripts/abis directory

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
ABI_DIR="$SCRIPT_DIR/abis"

echo "Copying ABIs from compiled contracts..."

# Create abis directory if it doesn't exist
mkdir -p "$ABI_DIR"

# Copy required contract ABIs
contracts=(
    "SimpleEscrow"
    "SimpleEscrowFactory"
    "MockERC20"
)

for contract in "${contracts[@]}"; do
    source_file="$PROJECT_ROOT/out/${contract}.sol/${contract}.json"
    if [ -f "$source_file" ]; then
        # Extract just the ABI from the compiled JSON
        jq '.abi' "$source_file" > "$ABI_DIR/${contract}.abi.json"
        echo "✓ Copied ${contract} ABI"
    else
        echo "⚠️  ${contract} ABI not found at $source_file"
    fi
done

echo "ABIs copied to $ABI_DIR"