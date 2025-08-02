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
    "OneInchAdapter"
    "LightningBridge"
)

for contract in "${contracts[@]}"; do
    source_file="$PROJECT_ROOT/out/${contract}.sol/${contract}.json"
    if [ -f "$source_file" ]; then
        # Extract just the ABI from the compiled JSON
        jq '.abi' "$source_file" > "$ABI_DIR/${contract}.json"
        echo "✓ Copied ${contract} ABI"
    else
        echo "⚠️  ${contract} ABI not found at $source_file"
    fi
done

echo ""
echo "ABIs copied to $ABI_DIR"

# Create TypeScript index file for easy imports
cat > "$ABI_DIR/index.ts" << 'EOF'
// Auto-generated ABI exports
import SimpleEscrowABI from "./SimpleEscrow.json" assert { type: "json" };
import SimpleEscrowFactoryABI from "./SimpleEscrowFactory.json" assert { type: "json" };
import MockERC20ABI from "./MockERC20.json" assert { type: "json" };
import OneInchAdapterABI from "./OneInchAdapter.json" assert { type: "json" };
import LightningBridgeABI from "./LightningBridge.json" assert { type: "json" };

export {
  SimpleEscrowABI,
  SimpleEscrowFactoryABI,
  MockERC20ABI,
  OneInchAdapterABI,
  LightningBridgeABI,
};

// Convenience exports
export const ERC20_ABI = MockERC20ABI;
export const FACTORY_ABI = SimpleEscrowFactoryABI;
export const ESCROW_ABI = SimpleEscrowABI;
EOF

echo "✓ Created TypeScript index file"