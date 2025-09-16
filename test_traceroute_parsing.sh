#!/bin/bash

# Test script to verify traceroute parsing with real example

echo "=== Traceroute Parsing Test ==="

# Source the traceroute collector functions
source ./traceroute_collector.sh

# Mock the example traceroute output you provided
MOCK_OUTPUT="Connected to radio
Sending traceroute request to !bff18ce4 (this could take a while)
Route traced towards destination:
!25048234 --> !ba4bf9d0 (6.0dB) --> !bff18ce4 (-3.5dB)
Route traced back to us:
!bff18ce4 --> !ba4bf9d0 (-2.75dB) --> !25048234 (5.25dB)"

echo "Testing with sample traceroute output:"
echo "$MOCK_OUTPUT"
echo ""

# Enable debug mode for this test
DEBUG=1

# Create temporary routing log for test
ROUTING_LOG="/tmp/test_routing_log.csv"
echo "timestamp,source,destination,direction,route_hops,signal_strengths,hop_count,success,error_reason" > "$ROUTING_LOG"

# Test the parsing function
echo "Running parse_traceroute_output..."
parse_traceroute_output "$MOCK_OUTPUT" "!bff18ce4" "2025-09-16T12:00:00+02:00"

echo ""
echo "=== Parsing Results ==="
echo "Routing log contents:"
cat "$ROUTING_LOG"

echo ""
echo "Expected results:"
echo "Forward route: !25048234→!ba4bf9d0→!bff18ce4"
echo "Forward signals: 6.0dB,-3.5dB"
echo "Return route: !bff18ce4→!ba4bf9d0→!25048234"  
echo "Return signals: -2.75dB,5.25dB"

# Clean up
rm -f "$ROUTING_LOG"

echo ""
echo "✅ Traceroute parsing test complete!"