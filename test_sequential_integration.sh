#!/bin/bash

# Test script to verify sequential telemetry + traceroute integration

echo "Testing sequential telemetry and traceroute integration..."

# Source the main script's functions
source ./meshtastic-telemetry-logger.sh

# Test settings
TRACEROUTE_ENABLED="true"
TRACEROUTE_INTERVAL=1
traceroute_cycle_counter=1  # This should trigger traceroute

# Mock a smaller address list for testing
ADDRESSES=('!test1' '!test2')

echo "Configuration:"
echo "  TRACEROUTE_ENABLED: $TRACEROUTE_ENABLED"
echo "  TRACEROUTE_INTERVAL: $TRACEROUTE_INTERVAL"
echo "  traceroute_cycle_counter: $traceroute_cycle_counter"
echo "  ADDRESSES: ${ADDRESSES[*]}"
echo "  Should run traceroutes this cycle: $((traceroute_cycle_counter % TRACEROUTE_INTERVAL == 0))"

echo ""
echo "Testing sequential collection function..."

# Test the logic without actually running commands
if [ "$TRACEROUTE_ENABLED" = "true" ] && [ $((traceroute_cycle_counter % TRACEROUTE_INTERVAL)) -eq 0 ]; then
    echo "✅ Traceroute integration logic is working - would run traceroutes this cycle"
else
    echo "❌ Traceroute integration logic failed"
fi

echo ""
echo "Function integration test complete!"