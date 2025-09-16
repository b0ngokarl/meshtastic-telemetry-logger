#!/bin/bash

# Create sample routing data for demonstration
cd /home/jo/meshtastic-telemetry-logger

echo "🎨 Creating sample routing data for visualization demo..."

# Create sample routing data with both successful and failed routes
cat > routing_log.csv << 'EOF'
timestamp,source,destination,direction,route_hops,signal_strengths,hop_count,success,error_reason
2025-09-16T19:30:00+02:00,!849944ac,!2df67288,forward,"!849944ac→!2df67288","3.5dB",1,true,
2025-09-16T19:30:00+02:00,!2df67288,!849944ac,return,"!2df67288→!849944ac","8.0dB",1,true,
2025-09-16T19:30:00+02:00,!849944ac,!9eed0410,forward,"!849944ac→!ba656304→!9eed0410","5.2dB,3.1dB",2,true,
2025-09-16T19:30:00+02:00,!9eed0410,!849944ac,return,"!9eed0410→!fd17c0ed→!849944ac","4.8dB,6.0dB",2,true,
2025-09-16T19:30:00+02:00,!849944ac,!a0cc8008,forward,"!849944ac→!277db5ca→!a0cc8008","4.2dB,2.9dB",2,true,
2025-09-16T19:30:00+02:00,!a0cc8008,!849944ac,return,"!a0cc8008→!277db5ca→!849944ac","3.1dB,4.5dB",2,true,
2025-09-16T19:31:00+02:00,!849944ac,!2c9e092b,forward,,,0,false,timeout
2025-09-16T19:15:00+02:00,!849944ac,!9eed0410,forward,"!849944ac→!277db5ca→!9eed0410","4.8dB,2.1dB",2,true,
EOF

# Create sample relationship data
cat > node_relationships.csv << 'EOF'
timestamp,node_a,node_b,signal_strength,relationship_type,last_heard
2025-09-16T19:30:00+02:00,!849944ac,!2df67288,3.5dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!2df67288,!849944ac,8.0dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!849944ac,!ba656304,5.2dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!ba656304,!9eed0410,3.1dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!9eed0410,!fd17c0ed,4.8dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!fd17c0ed,!849944ac,6.0dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!849944ac,!277db5ca,4.2dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:30:00+02:00,!277db5ca,!a0cc8008,2.9dB,direct_route,2025-09-16T19:30:00+02:00
2025-09-16T19:15:00+02:00,!849944ac,!277db5ca,4.8dB,direct_route,2025-09-16T19:15:00+02:00
2025-09-16T19:15:00+02:00,!277db5ca,!9eed0410,2.1dB,direct_route,2025-09-16T19:15:00+02:00
EOF

echo "✅ Sample data created!"

# Generate the visualization
echo "🎨 Generating topology visualization with sample data..."
python3 routing_topology_analyzer.py

echo "📊 Visualization generated! Let's see what it looks like:"
echo ""
cat network_topology.html

echo ""
echo "🎯 Demo complete! This shows what the traceroute visualization will look like"
echo "   when real routing data is collected."