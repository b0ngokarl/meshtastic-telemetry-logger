#!/bin/bash

# Test the corrected traceroute detection

echo "=== Testing Corrected Traceroute Detection ==="

# Source functions  
source ./traceroute_collector.sh

# Set debug mode
DEBUG=1

# Create test routing log
ROUTING_LOG="/tmp/test_routing_corrected.csv"
echo "timestamp,source,destination,direction,route_hops,signal_strengths,hop_count,success,error_reason" > "$ROUTING_LOG"

# Simulate the actual output you showed me
TEST_OUTPUT="ERROR file:mesh_interface.py _handleFromRadio line:1264 Error while parsing FromRadio bytes:b'\"\\xfe\\x08\\xac\\x89\\xe5\\xa4\\x08\\x12R\\n\\t!849944ac\\x12\\x0fMeshtastic 44ac\\x1a\\x0444ac\"\\x06x!\\x84\\x99D\\xac(\\x058\\x01B \\xac\\xea\\x0e\\x0fF!\\xbd\\xe4\\x84\\xe4Y5ePu\\xee\\xee,\\x92\\xa9X\\xc8\\xaf\\xa9\\xefe!\\x15\\x19|\\x19PH\\x00\\x1a\\x05%\\xb3\\xad\\xc9h-\\xb3\\xad\\xc9h2\\x14\\x08e\\x15o\\x12\\x83\\xba\\x1d\\xab\\xaaVA%B\\x86\\x02?(\\xe2\\x12P\\x01' Error parsing message with type 'meshtastic.protobuf.FromRadio'
Connected to radio
Sending traceroute request to !2df67288 on channelIndex:0 (this could take a while)
Route traced towards destination:
849944ac --> 9ee70e28 (-13.25dB) --> 2df67288 (-13.75dB)
Route traced back to us:
2df67288 --> 849944ac (9.5dB)"

echo "Testing with real traceroute output (includes errors but has route data)..."
echo ""

# Test the parsing function directly
if echo "$TEST_OUTPUT" | grep -q "Route traced"; then
    echo "✅ Detection logic works: Found 'Route traced' in output"
    
    # Test the actual parsing
    echo "Testing parse_traceroute_output..."
    parse_traceroute_output "$TEST_OUTPUT" "!2df67288" "2025-09-16T13:00:00+02:00"
    
    echo ""
    echo "Results:"
    cat "$ROUTING_LOG"
else
    echo "❌ Detection failed: Could not find 'Route traced' in output"
fi

# Clean up
rm -f "$ROUTING_LOG"

echo ""
echo "=== Test complete ==="