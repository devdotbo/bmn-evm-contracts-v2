#!/bin/bash

echo "🛑 Stopping local Anvil instances..."

# Stop anvil processes if PID files exist
if [ -f /tmp/anvil1.pid ]; then
    PID1=$(cat /tmp/anvil1.pid)
    if kill -0 $PID1 2>/dev/null; then
        kill $PID1
        echo "✅ Stopped Anvil on port 8545 (PID: $PID1)"
    else
        echo "⚠️  Anvil process $PID1 not found"
    fi
    rm /tmp/anvil1.pid
fi

if [ -f /tmp/anvil2.pid ]; then
    PID2=$(cat /tmp/anvil2.pid)
    if kill -0 $PID2 2>/dev/null; then
        kill $PID2
        echo "✅ Stopped Anvil on port 8546 (PID: $PID2)"
    else
        echo "⚠️  Anvil process $PID2 not found"
    fi
    rm /tmp/anvil2.pid
fi

# Clean up log files
if [ -f /tmp/anvil1.log ]; then
    rm /tmp/anvil1.log
    echo "✅ Removed anvil1.log"
fi

if [ -f /tmp/anvil2.log ]; then
    rm /tmp/anvil2.log
    echo "✅ Removed anvil2.log"
fi

echo "🧹 Cleanup complete!"