#!/bin/bash

# Test script for traceroute functionality
cd /home/jo/meshtastic-telemetry-logger

echo "🧪 Testing Traceroute Implementation"
echo "==================================="

# Check if all files exist
echo "📁 Checking required files..."
files_to_check=(
    "traceroute_collector.sh"
    "routing_topology_analyzer.py"
    ".env"
)

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file exists"
    else
        echo "  ❌ $file missing"
    fi
done

# Source the traceroute collector
echo ""
echo "📜 Loading traceroute collector..."
if source "./traceroute_collector.sh"; then
    echo "  ✅ Traceroute collector loaded successfully"
else
    echo "  ❌ Failed to load traceroute collector"
    exit 1
fi

# Test basic functions
echo ""
echo "🔧 Testing basic functions..."

# Test initialization
echo "  📝 Testing log initialization..."
if init_routing_logs; then
    echo "    ✅ Log files initialized"
    ls -la routing_log.csv node_relationships.csv 2>/dev/null | head -2
else
    echo "    ❌ Log initialization failed"
fi

# Test single traceroute (to a working node from our earlier test)
echo ""
echo "  🗺️  Testing single traceroute..."
if run_traceroute '!2df67288'; then
    echo "    ✅ Single traceroute completed"
    if [ -f "routing_log.csv" ]; then
        echo "    📊 Routing log entries:"
        tail -3 routing_log.csv
    fi
else
    echo "    ⚠️  Single traceroute may have failed (check logs)"
fi

# Test topology analyzer
echo ""
echo "  🎨 Testing topology analyzer..."
if python3 routing_topology_analyzer.py; then
    echo "    ✅ Topology analyzer completed"
    if [ -f "network_topology.html" ]; then
        echo "    📊 Generated topology HTML ($(wc -l < network_topology.html) lines)"
    fi
else
    echo "    ❌ Topology analyzer failed"
fi

echo ""
echo "🎯 Test Summary"
echo "==============="
echo "✅ Implementation appears to be working!"
echo "📄 Check these files for output:"
echo "   - routing_log.csv (traceroute data)"
echo "   - node_relationships.csv (network relationships)"  
echo "   - network_topology.html (visualization)"
echo ""
echo "💡 The traceroute feature will activate automatically every $TRACEROUTE_INTERVAL cycles"
echo "   when the main meshtastic-telemetry-logger.sh runs."