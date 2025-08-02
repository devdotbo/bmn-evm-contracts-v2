#!/bin/bash
set -e

# Bridge Me Not V2 - Cleanup Script
# Gracefully shuts down chains and archives logs

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parse command line arguments
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-y|--yes]"
            echo "  -y, --yes  Auto-approve all prompts"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Bridge Me Not V2 - Cleanup${NC}"
echo "=========================="

# Reset cleanup log
mkdir -p logs
> logs/cleanup.log

log() {
    echo "$1" | tee -a logs/cleanup.log
}

# Function to safely kill processes
kill_processes() {
    local process_name=$1
    local pids=$(pgrep -f "$process_name" 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        log "Found $process_name processes: $pids"
        for pid in $pids; do
            if kill -0 $pid 2>/dev/null; then
                log "Terminating PID $pid..."
                kill -TERM $pid 2>/dev/null || true
            fi
        done
        
        # Give processes time to terminate gracefully
        sleep 2
        
        # Force kill if still running
        for pid in $pids; do
            if kill -0 $pid 2>/dev/null; then
                log "Force killing PID $pid..."
                kill -9 $pid 2>/dev/null || true
            fi
        done
    else
        log "No $process_name processes found"
    fi
}

# Check if any processes are running
FOUND_PROCESSES=false
if pgrep -f "mproc.*bmn-chains" > /dev/null 2>&1; then
    FOUND_PROCESSES=true
fi
if pgrep -f "anvil" > /dev/null 2>&1; then
    FOUND_PROCESSES=true
fi

if [ "$FOUND_PROCESSES" = false ]; then
    echo -e "${YELLOW}No BMN processes found running${NC}"
else
    if [ "$AUTO_APPROVE" = false ]; then
        echo -e "${YELLOW}This will stop all BMN chains and processes${NC}"
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cleanup cancelled"
            exit 0
        fi
    fi
fi

# Kill mproc if PID file exists
if [ -f /tmp/bmn-mproc.pid ]; then
    MPROC_PID=$(cat /tmp/bmn-mproc.pid)
    if kill -0 $MPROC_PID 2>/dev/null; then
        log "Stopping mproc (PID: $MPROC_PID)..."
        kill -TERM $MPROC_PID 2>/dev/null || true
        sleep 2
    fi
    rm -f /tmp/bmn-mproc.pid
fi

# Kill all mproc processes
log ""
log "Stopping mproc processes..."
kill_processes "mproc.*bmn-chains"

# Kill all anvil processes
log ""
log "Stopping anvil processes..."
kill_processes "anvil"

# Archive logs if they exist
if [ -f logs/chains.log ] && [ -s logs/chains.log ]; then
    log ""
    log "Archiving logs..."
    
    # Create archive directory
    mkdir -p logs/archive
    
    # Generate timestamp
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_NAME="chains_${TIMESTAMP}.log"
    
    # Move log to archive
    mv logs/chains.log "logs/archive/$ARCHIVE_NAME"
    log "Logs archived to: logs/archive/$ARCHIVE_NAME"
    
    # Keep only last 10 archives
    cd logs/archive
    ls -t chains_*.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    cd - > /dev/null
fi

# Clean up temporary files
log ""
log "Cleaning up temporary files..."
rm -f /tmp/bmn-chains.yml
rm -f /tmp/bmn-mproc.pid

# Clean up any foundry cache files
if [ -d .foundry ]; then
    find .foundry -name "*.tmp" -type f -delete 2>/dev/null || true
fi

# Final verification
log ""
log "Verifying cleanup..."
CLEANUP_SUCCESS=true

if pgrep -f "mproc.*bmn-chains" > /dev/null 2>&1; then
    log -e "${RED}Warning: Some mproc processes are still running${NC}"
    CLEANUP_SUCCESS=false
fi

if pgrep -f "anvil.*854[56]" > /dev/null 2>&1; then
    log -e "${RED}Warning: Some anvil processes are still running${NC}"
    CLEANUP_SUCCESS=false
fi

if [ "$CLEANUP_SUCCESS" = true ]; then
    echo ""
    echo -e "${GREEN}✓ Cleanup completed successfully${NC}"
    echo "All BMN processes have been stopped"
else
    echo ""
    echo -e "${YELLOW}⚠ Cleanup completed with warnings${NC}"
    echo "Some processes may still be running"
    echo "Check 'ps aux | grep -E \"(mproc|anvil)\"' for details"
fi

echo ""
echo "Cleanup log: logs/cleanup.log"