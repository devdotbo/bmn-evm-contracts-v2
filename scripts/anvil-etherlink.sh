#!/bin/bash
# Raw script for running Etherlink chain - called by mproc

# Ensure logs directory exists
mkdir -p logs

# Log file with timestamp
LOG_FILE="logs/etherlink-chain.log"

# Clear log file
> "$LOG_FILE"

echo "[$(date)] Starting Etherlink chain on port 8546..." | tee -a "$LOG_FILE"

# Run anvil with Etherlink chain ID
exec anvil \
  --port 8546 \
  --chain-id 42793 \
  --accounts 10 \
  --balance 10000 \
  --block-time 1 \
  --gas-limit 30000000 \
  --steps-tracing \
  2>&1 | tee -a "$LOG_FILE"