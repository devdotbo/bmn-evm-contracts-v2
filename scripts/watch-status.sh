#!/bin/bash
set -e

# Colors
BLUE='\033[0;34m'
NC='\033[0m'

# Log file
LOG_FILE="logs/watch-status.log"
mkdir -p logs

# Default interval
INTERVAL=5

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--interval) INTERVAL="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

echo -e "${BLUE}=== Bridge Me Not V2 - Status Monitor ===${NC}" | tee "$LOG_FILE"
echo "Refreshing every $INTERVAL seconds (Ctrl+C to stop)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run status script in a loop
while true; do
    clear
    echo -e "${BLUE}=== Bridge Me Not V2 - Status Monitor ===${NC}"
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Refreshing every $INTERVAL seconds (Ctrl+C to stop)"
    echo ""
    
    # Run the status script
    ./scripts/status.sh 2>/dev/null || echo "Status check failed"
    
    # Log to file
    echo "[$(date)] Status check completed" >> "$LOG_FILE"
    
    # Wait for interval
    sleep $INTERVAL
done