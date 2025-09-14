#!/bin/bash

# Comprehensive Traceroute System Demonstration
# Shows all the components working together

echo "🌐 MESHTASTIC TRACEROUTE SYSTEM DEMONSTRATION"
echo "=============================================="
echo ""

echo "📊 1. CURRENT TRACEROUTE DATA:"
echo "------------------------------"
if [ -f "traceroute_log.csv" ]; then
    echo "Traceroute log entries: $(tail -n +2 traceroute_log.csv | wc -l)"
    echo ""
    echo "Recent traceroute entries:"
    echo "Timestamp                  | Target     | Status  | Hops | Route"
    echo "---------------------------|------------|---------|------|--------------------------------"
    tail -3 traceroute_log.csv | while IFS=',' read -r timestamp target success total_hops hops; do
        # Remove quotes from hops
        hops_clean=$(echo "$hops" | sed 's/^"//; s/"$//')
        route_display=$(echo "$hops_clean" | sed 's/,/ → /g')
        printf "%-26s | %-10s | %-7s | %4s | %s\n" "$timestamp" "$target" "$success" "$total_hops" "$route_display"
    done
    echo ""
else
    echo "❌ No traceroute data found"
fi

echo "🔍 2. NETWORK TOPOLOGY ANALYSIS:"
echo "--------------------------------"
if [ -f "generate_simple_traceroute_analysis.py" ]; then
    echo "Running network topology analysis..."
    python3 generate_simple_traceroute_analysis.py --stats --output demo_topology
    echo ""
    
    if [ -f "demo_topology.txt" ]; then
        echo "📄 Generated analysis summary:"
        head -15 demo_topology.txt
        echo "... (see demo_topology.txt for full analysis)"
        echo ""
    fi
    
    if [ -f "demo_topology_stats.json" ]; then
        echo "📈 Network statistics:"
        python3 -c "
import json
with open('demo_topology_stats.json', 'r') as f:
    stats = json.load(f)
    print(f\"  • Total Nodes: {stats['network_stats']['total_nodes']}\")
    print(f\"  • Active Routes: {stats['network_stats']['total_routes']}\")
    print(f\"  • Success Rate: {stats['network_stats']['analyzed_routes']} routes analyzed\")
    print(f\"  • Hub Nodes: {', '.join(stats['topology_analysis']['hub_nodes'])}\")
"
        echo ""
    fi
    
    if [ -f "demo_topology.svg" ]; then
        echo "🎨 Generated SVG network diagram: demo_topology.svg"
        echo "   (Open in browser to view the interactive network topology)"
        echo ""
    fi
else
    echo "❌ Network analysis script not found"
fi

echo "🌐 3. HTML DASHBOARD INTEGRATION:"
echo "--------------------------------"
echo "Testing HTML topology section generation..."

# Generate a demo HTML page with traceroute section
cat > demo_dashboard.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meshtastic Traceroute Demo</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; margin-bottom: 30px; }
        .network-topology { background: white; border-radius: 12px; padding: 25px; margin-bottom: 30px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 15px 0; }
        .stat-item { background: linear-gradient(135deg, #f8f9fa, #e9ecef); padding: 15px; border-radius: 8px; display: flex; justify-content: space-between; align-items: center; }
        .stat-label { font-weight: 500; color: #6c757d; }
        .stat-value { font-weight: 700; color: #2c3e50; font-size: 1.1rem; }
        .topology-chart { max-width: 100%; height: auto; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
        .modern-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .modern-table th { background: #2c3e50; color: white; padding: 12px; text-align: left; }
        .modern-table td { padding: 10px; border-bottom: 1px solid #e9ecef; }
        .modern-table tr:hover { background: #f8f9fa; }
        .success { color: #27ae60; font-weight: bold; }
        .danger { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-project-diagram"></i> Meshtastic Traceroute Demo</h1>
            <p>Network Topology Analysis & Route Visualization</p>
        </div>
        
        <div class="network-topology">
            <h3><i class="fas fa-chart-line"></i> Network Topology Analysis</h3>
HTMLEOF

# Add the topology section using our test script
./test_topology_section.sh >> demo_dashboard.html

cat >> demo_dashboard.html << 'HTMLEOF'
        </div>
        
        <div style="text-align: center; margin-top: 40px; padding: 20px; background: white; border-radius: 8px;">
            <p><strong>🎯 Demo Complete!</strong></p>
            <p>This demonstrates the full traceroute functionality integrated into the Meshtastic telemetry logger.</p>
            <p><em>In production, this runs automatically every hour and integrates seamlessly with the main dashboard.</em></p>
        </div>
    </div>
</body>
</html>
HTMLEOF

echo "✅ Generated demo dashboard: demo_dashboard.html"
echo "   (Open in browser to see the complete integrated system)"
echo ""

echo "🔧 4. CONFIGURATION EXAMPLE:"
echo "----------------------------"
echo "Traceroute configuration options in .env file:"
echo ""
echo "# Traceroute Settings"
echo "TRACEROUTE_ENABLED=true        # Enable traceroute collection"
echo "TRACEROUTE_TIMEOUT=120         # Timeout for traceroute requests"
echo "TRACEROUTE_INTERVAL=3600       # How often to run traceroute (1 hour)"
echo "TRACEROUTE_VISUALIZATION=true  # Enable network topology visualization"
echo ""

echo "⚙️  5. SYSTEM INTEGRATION:"
echo "-------------------------"
echo "The traceroute system integrates with the main telemetry logger as follows:"
echo ""
echo "1. 📡 Telemetry Collection (every 5 minutes)"
echo "   └── Battery, voltage, channel utilization data"
echo ""
echo "2. 🌐 Traceroute Collection (every hour)"
echo "   └── Network topology and routing analysis"
echo ""
echo "3. 📊 Visualization Generation"
echo "   ├── SVG network diagrams"
echo "   ├── Route statistics"
echo "   └── Network topology analysis"
echo ""
echo "4. 📱 Dashboard Integration"
echo "   └── Combined view with telemetry + network topology"
echo ""

echo "🎉 DEMONSTRATION COMPLETE!"
echo "=========================="
echo ""
echo "The traceroute functionality has been successfully implemented with:"
echo "  ✅ Automatic route tracing to monitored nodes"
echo "  ✅ Multi-hop route analysis and visualization"  
echo "  ✅ Network topology identification (hubs, relays, endpoints)"
echo "  ✅ SVG-based network diagrams"
echo "  ✅ Integration with existing HTML dashboard"
echo "  ✅ Configurable collection intervals"
echo ""
echo "Files generated:"
if [ -f "demo_topology.txt" ]; then echo "  📄 demo_topology.txt - Network analysis report"; fi
if [ -f "demo_topology.svg" ]; then echo "  🎨 demo_topology.svg - Interactive network diagram"; fi
if [ -f "demo_topology_stats.json" ]; then echo "  📊 demo_topology_stats.json - Network statistics"; fi
echo "  🌐 demo_dashboard.html - Complete integrated dashboard"
echo ""
echo "Open demo_dashboard.html in your browser to see the full system in action!"

