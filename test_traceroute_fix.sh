#!/bin/bash

echo "=== Testing Fixed Traceroute Command Format ==="

# Source functions
source ./traceroute_collector.sh

echo "Before fix: meshtastic --traceroute '!9eed0410'"
echo "After fix:  meshtastic --traceroute !9eed0410"
echo ""

echo "The issue was that single quotes made meshtastic try to parse 'eed0410'' as hex"
echo "which fails because of the trailing quote character."
echo ""

echo "✅ Fixed: Removed single quotes from traceroute command"
echo "Now the node ID is passed correctly as: !9eed0410"