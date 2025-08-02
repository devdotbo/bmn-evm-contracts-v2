#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
AUTO_APPROVE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -y|--yes) AUTO_APPROVE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Log file
LOG_FILE="logs/cleanup.log"
mkdir -p logs
> "$LOG_FILE"

echo -e "${YELLOW}=== Bridge Me Not V2 - Cleanup ===${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Confirmation
if [ "$AUTO_APPROVE" = false ]; then
    echo "This will:" | tee -a "$LOG_FILE"
    echo "  - Stop all mproc and anvil processes" | tee -a "$LOG_FILE"
    echo "  - Archive current logs" | tee -a "$LOG_FILE"
    echo "  - Clean temporary files" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Kill mproc processes
echo -e "${YELLOW}Stopping mproc...${NC}" | tee -a "$LOG_FILE"
if pgrep -f "mproc.*mproc.yaml" > /dev/null; then
    pkill -f "mproc.*mproc.yaml" || true
    echo -e "${GREEN}✓${NC} Stopped mproc" | tee -a "$LOG_FILE"
else
    echo "  No mproc process found" | tee -a "$LOG_FILE"
fi

# Kill anvil processes
echo -e "${YELLOW}Stopping anvil instances...${NC}" | tee -a "$LOG_FILE"
ANVIL_COUNT=$(pgrep -f "anvil" | wc -l || echo 0)
if [ $ANVIL_COUNT -gt 0 ]; then
    pkill -f "anvil" || true
    echo -e "${GREEN}✓${NC} Stopped $ANVIL_COUNT anvil instance(s)" | tee -a "$LOG_FILE"
else
    echo "  No anvil processes found" | tee -a "$LOG_FILE"
fi

# Archive logs
if [ -d "logs" ] && [ "$(ls -A logs/*.log 2>/dev/null | grep -v cleanup.log)" ]; then
    echo -e "${YELLOW}Archiving logs...${NC}" | tee -a "$LOG_FILE"
    
    # Create archive directory
    mkdir -p logs/archive
    
    # Create timestamp
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_DIR="logs/archive/$TIMESTAMP"
    mkdir -p "$ARCHIVE_DIR"
    
    # Move logs (except cleanup.log)
    for log in logs/*.log; do
        if [ -f "$log" ] && [ "$log" != "$LOG_FILE" ]; then
            mv "$log" "$ARCHIVE_DIR/" || true
        fi
    done
    
    echo -e "${GREEN}✓${NC} Logs archived to: $ARCHIVE_DIR" | tee -a "$LOG_FILE"
    
    # Keep only last 10 archives
    cd logs/archive
    ls -t | tail -n +11 | xargs rm -rf 2>/dev/null || true
    cd ../..
    echo -e "${GREEN}✓${NC} Cleaned old archives (keeping last 10)" | tee -a "$LOG_FILE"
fi

# Clean temporary files
echo -e "${YELLOW}Cleaning temporary files...${NC}" | tee -a "$LOG_FILE"

# Remove PID files if they exist
for pidfile in /tmp/anvil*.pid; do
    if [ -f "$pidfile" ]; then
        rm -f "$pidfile"
        echo -e "${GREEN}✓${NC} Removed $(basename $pidfile)" | tee -a "$LOG_FILE"
    fi
done

# Remove temp logs
for tmplog in /tmp/anvil*.log; do
    if [ -f "$tmplog" ]; then
        rm -f "$tmplog"
        echo -e "${GREEN}✓${NC} Removed $(basename $tmplog)" | tee -a "$LOG_FILE"
    fi
done

# Verify cleanup
echo "" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Verification:${NC}" | tee -a "$LOG_FILE"

# Check processes
if ! pgrep -f "mproc.*mproc.yaml" > /dev/null && ! pgrep -f "anvil" > /dev/null; then
    echo -e "${GREEN}✓${NC} All processes stopped successfully" | tee -a "$LOG_FILE"
else
    echo -e "${RED}✗${NC} Warning: Some processes may still be running" | tee -a "$LOG_FILE"
    echo "  Run 'ps aux | grep -E \"mproc|anvil\"' to check" | tee -a "$LOG_FILE"
fi

# Check ports
for port in 8545 8546; do
    if ! nc -z localhost $port 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Port $port is free" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}✗${NC} Warning: Port $port may still be in use" | tee -a "$LOG_FILE"
    fi
done

echo "" | tee -a "$LOG_FILE"
echo -e "${GREEN}Cleanup complete!${NC}" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"