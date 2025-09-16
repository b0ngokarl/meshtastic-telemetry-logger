#!/bin/bash

# Quick Traceroute Test - Demonstrates the traceroute functionality
# without waiting for full telemetry collection

echo "🗺️  Quick Traceroute Test"
echo "========================"

# Load configuration
if [ -f ".env" ]; then
    source .env
    echo "✅ Configuration loaded from .env file"
else
    echo "❌ No .env file found"
    exit 1
fi

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"
source "$SCRIPT_DIR/html_generator.sh"
source "$SCRIPT_DIR/traceroute_collector.sh"

echo ""
echo "📊 Current traceroute settings:"
echo "   TRACEROUTE_ENABLED: $TRACEROUTE_ENABLED"
echo "   TRACEROUTE_INTERVAL: $TRACEROUTE_INTERVAL"
echo "   TRACEROUTE_TIMEOUT: $TRACEROUTE_TIMEOUT"

if [ "$TRACEROUTE_ENABLED" != "true" ]; then
    echo "❌ Traceroute is disabled. Set TRACEROUTE_ENABLED=true in .env"
    exit 1
fi

echo ""
echo "🗺️  Running traceroutes for monitored nodes..."
echo "   Monitored nodes: ${MONITORED_NODES}"

# Initialize and run traceroutes
run_traceroutes_sequential

echo ""
echo "📊 Checking results..."

if [ -f "routing_log.csv" ]; then
    echo "✅ Routing log created:"
    cat routing_log.csv
else
    echo "❌ No routing log found"
fi

echo ""
if [ -f "node_relationships.csv" ]; then
    echo "✅ Relationships log created:"
    cat node_relationships.csv
else
    echo "❌ No relationships log found"
fi

echo ""
echo "🎨 Generating topology visualization..."
python3 routing_topology_analyzer.py

if [ -f "network_topology.html" ]; then
    echo "✅ Topology visualization created!"
    echo ""
    echo "📊 Preview of topology HTML:"
    echo "----------------------------"
    cat network_topology.html
else
    echo "❌ Failed to generate topology visualization"
fi

echo ""
echo "🎯 Quick test complete!"
echo "   Check the HTML dashboard to see the integrated visualization."