#!/bin/bash
# Raw script for running Base chain - called by mproc

# Ensure logs directory exists
mkdir -p logs

# Log file with timestamp
LOG_FILE="logs/base-chain.log"

# Clear log file
> "$LOG_FILE"

echo "[$(date)] Starting Base chain on port 8545..." | tee -a "$LOG_FILE"

# Run anvil with Base chain ID
exec anvil \
  --port 8545 \
  --chain-id 8453 \
  --accounts 10 \
  --balance 10000 \
  --block-time 1 \
  --gas-limit 30000000 \
  --steps-tracing \
  2>&1 | tee -a "$LOG_FILE"