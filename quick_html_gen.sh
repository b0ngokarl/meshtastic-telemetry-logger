#!/bin/bash

# Quick HTML generator to test the All Nodes Ever Heard section
# This bypasses the problematic telemetry collection

HTML_FILE="stats.html"
NODES_CSV="nodes_log.csv"

# HTML header
cat > "$HTML_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meshtastic Telemetry Stats</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        h2 { color: #666; margin-top: 30px; }
        h3 { color: #888; margin-top: 20px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; position: relative; cursor: pointer; }
        th:hover { background-color: #e8e8e8; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .timestamp { font-family: monospace; }
        .number { text-align: right; }
        .address { font-weight: bold; }
        
        /* Color coding for values */
        .critical { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .warning { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .good { background-color: #e8f5e8; color: #1b5e20; font-weight: bold; }
        .unknown { color: #666; font-style: italic; }
        
        /* Navigation styles */
        .nav-container {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .nav-title {
            color: white;
            font-size: 1.2em;
            font-weight: bold;
            margin-bottom: 15px;
            text-align: center;
        }
        .nav-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
        }
        .nav-link {
            text-decoration: none;
            padding: 8px 12px;
            border-radius: 4px;
            color: white;
            transition: all 0.3s ease;
            text-align: center;
            display: block;
        }
        .nav-link:hover {
            transform: translateY(-2px);
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
        }
    </style>
    <script>
        function toggleSection(sectionId) {
            const section = document.getElementById(sectionId);
            const toggle = document.getElementById(sectionId + '-toggle');
            
            if (section.style.display === 'none') {
                section.style.display = 'block';
                toggle.textContent = '[click to collapse]';
            } else {
                section.style.display = 'none';
                toggle.textContent = '[click to expand]';
            }
        }
    </script>
</head>
<body>
EOF

# Main content
cat >> "$HTML_FILE" << 'EOF'
<h1>📡 Meshtastic Telemetry Dashboard</h1>
<p><em>Generated: 2025-09-12T19:00:00+02:00</em></p>

<!-- Navigation Index -->
<div class="nav-container">
    <div class="nav-title">📍 Navigation Index</div>
    <div class="nav-grid">
        <a href='#all-nodes-header' class='nav-link' style='background: #ede7f6; color: #5e35b1;'>📡 All Nodes Ever Heard</a>
        <a href='#summary' class='nav-link' style='background: #e3f2fd; color: #1976d2;'>📊 Summary Statistics</a>
        <a href='#telemetry' class='nav-link' style='background: #e8f5e8; color: #388e3c;'>📈 Telemetry History</a>
    </div>
</div>

EOF

# Add All Nodes Ever Heard Section
cat >> "$HTML_FILE" << 'EOF'
<h2 id='all-nodes-header' onclick="toggleSection('all-nodes-content')" style="cursor: pointer; user-select: none;">
📡 All Nodes Ever Heard <span id="all-nodes-content-toggle" style="font-size: 0.8em; color: #666;">[click to expand]</span>
</h2>
<div id="all-nodes-content" style="display: none;">
<p><em>Comprehensive list of all nodes that have ever been detected on the mesh network, sorted by first appearance</em></p>
<table>
<tr><th>#</th><th>User</th><th>ID</th><th>Hardware</th><th>Role</th><th>GPS</th><th>First Heard</th><th>Last Heard</th><th>Status</th></tr>
EOF

# Generate the All Nodes Ever Heard table
if [ -f "$NODES_CSV" ]; then
    index=1
    tail -n +2 "$NODES_CSV" 2>/dev/null | awk -F',' '!seen[$2]++ {print}' | sort -t',' -k17,17 | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
        # Remove quotes if present
        user=$(echo "$user" | sed 's/^"//;s/"$//')
        hardware=$(echo "$hardware" | sed 's/^"//;s/"$//')
        latitude=$(echo "$latitude" | sed 's/^"//;s/"$//')
        longitude=$(echo "$longitude" | sed 's/^"//;s/"$//')
        
        # Check if GPS coordinates are valid
        if [ -n "$latitude" ] && [ -n "$longitude" ] && \
           [ "$latitude" != "N/A" ] && [ "$longitude" != "N/A" ] && \
           [ "$latitude" != "0.0" ] && [ "$longitude" != "0.0" ] && \
           [ "$latitude" != "0" ] && [ "$longitude" != "0" ]; then
            gps_display="<a href=\"https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}&zoom=15\" target=\"_blank\" title=\"View on map\">${latitude}, ${longitude}</a>"
        else
            gps_display="N/A"
        fi
        
        # Determine node status based on last heard time
        status="Unknown"
        status_class="unknown"
        if [ -n "$lastheard" ] && [ "$lastheard" != "N/A" ]; then
            current_time=$(date +%s)
            last_heard_time=$(date -d "$lastheard" +%s 2>/dev/null)
            if [ -n "$last_heard_time" ]; then
                time_diff=$((current_time - last_heard_time))
                hours_ago=$((time_diff / 3600))
                
                if [ $hours_ago -lt 1 ]; then
                    status="🟢 Active"
                    status_class="good"
                elif [ $hours_ago -lt 24 ]; then
                    status="🟡 Recent"
                    status_class="warning"
                elif [ $hours_ago -lt 168 ]; then  # 1 week
                    status="🟠 Inactive"
                    status_class="critical"
                else
                    status="🔴 Offline"
                    status_class="critical"
                fi
            fi
        fi
        
        # Format first heard time
        first_heard="${since:-N/A}"
        if [ "$first_heard" != "N/A" ] && [ -n "$first_heard" ]; then
            first_heard=$(date -d "$first_heard" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$first_heard")
        fi
        
        # Format last heard time
        last_heard="${lastheard:-N/A}"
        if [ "$last_heard" != "N/A" ] && [ -n "$last_heard" ]; then
            last_heard=$(date -d "$last_heard" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_heard")
        fi
        
        echo "<tr>"
        echo "<td class=\"number\">$index</td>"
        echo "<td>${user:-N/A}</td>"
        echo "<td class=\"address\">$id</td>"
        echo "<td>${hardware:-N/A}</td>"
        echo "<td>${role:-N/A}</td>"
        echo "<td>$gps_display</td>"
        echo "<td class=\"timestamp\">$first_heard</td>"
        echo "<td class=\"timestamp\">$last_heard</td>"
        echo "<td class=\"$status_class\">$status</td>"
        echo "</tr>"
        index=$((index + 1))
    done >> "$HTML_FILE"
fi

# Close the table and section
cat >> "$HTML_FILE" << 'EOF'
</table>
</div>

<h2 id="summary">📊 Summary Statistics</h2>
<p><em>This is a simplified version showing the "All Nodes Ever Heard" section. Full telemetry data collection is temporarily disabled due to encoding issues.</em></p>

<h2 id="telemetry">📈 Telemetry History</h2>
<p><em>Telemetry collection will be restored once the character encoding issues are resolved.</em></p>

</body>
</html>
EOF

echo "Simplified HTML generated: $HTML_FILE"
