#!/bin/bash

# Complete test of corrected traceroute parsing and visualization

echo "=== Complete Traceroute Integration Test ==="

# Source functions
source ./traceroute_collector.sh

# Create clean test files
ROUTING_LOG="routing_log.csv"
RELATIONSHIPS_LOG="node_relationships.csv"

echo "timestamp,source,destination,direction,route_hops,signal_strengths,hop_count,success,error_reason" > "$ROUTING_LOG"
echo "timestamp,node_a,node_b,signal_strength,relationship_type,last_heard" > "$RELATIONSHIPS_LOG"

# Enable debug
DEBUG=1

# Test with your real example
MOCK_OUTPUT="Connected to radio
Sending traceroute request to !bff18ce4 (this could take a while)
Route traced towards destination:
!25048234 --> !ba4bf9d0 (6.0dB) --> !bff18ce4 (-3.5dB)
Route traced back to us:
!bff18ce4 --> !ba4bf9d0 (-2.75dB) --> !25048234 (5.25dB)"

echo "1. Testing traceroute parsing..."
parse_traceroute_output "$MOCK_OUTPUT" "!bff18ce4" "2025-09-16T12:00:00+02:00"

# Add another route for more interesting topology
MOCK_OUTPUT2="Connected to radio
Sending traceroute request to !ab123456 (this could take a while)
Route traced towards destination:
!25048234 --> !ab123456 (8.2dB)
Route traced back to us:
!ab123456 --> !25048234 (7.5dB)"

parse_traceroute_output "$MOCK_OUTPUT2" "!ab123456" "2025-09-16T12:30:00+02:00"

echo ""
echo "2. Generated routing data:"
echo "--- Routing Log ---"
cat "$ROUTING_LOG"
echo ""
echo "--- Relationships Log ---"
cat "$RELATIONSHIPS_LOG"

echo ""
echo "3. Generating topology visualization..."
python3 routing_topology_analyzer.py

if [ -f "network_topology.html" ]; then
    echo "✅ Topology visualization generated successfully!"
    echo "   File: network_topology.html"
    echo "   Size: $(wc -c < network_topology.html) bytes"
else
    echo "❌ Topology visualization failed!"
fi

echo ""
echo "=== Integration test complete! ==="