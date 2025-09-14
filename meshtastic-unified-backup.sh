
# ============================================================================
# HTML DASHBOARD GENERATION
# ============================================================================

# Generate comprehensive HTML statistics dashboard
generate_stats_html() {
    debug_log "Generating HTML dashboard"
    
    # Create HTML file with enhanced styling and functionality
    {
        cat << 'HTML_HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meshtastic Telemetry Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; text-align: center; margin-bottom: 30px; }
        h2 { color: #666; margin-top: 30px; border-bottom: 2px solid #ddd; padding-bottom: 10px; }
        h3 { color: #888; margin-top: 20px; }
        
        .dashboard-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            margin-bottom: 30px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        
        .stat-value {
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }
        
        .stat-label {
            color: #666;
            margin-top: 5px;
        }
        
        table { 
            border-collapse: collapse; 
            width: 100%; 
            margin: 10px 0; 
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        th, td { 
            border: 1px solid #ddd; 
            padding: 12px 8px; 
            text-align: left; 
        }
        
        th { 
            background: linear-gradient(135deg, #f8f9fa, #e9ecef);
            font-weight: bold; 
            position: sticky;
            top: 0;
            cursor: pointer;
            user-select: none;
        }
        
        th:hover { 
            background: linear-gradient(135deg, #e9ecef, #dee2e6);
        }
        
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr:hover { background-color: #fff3cd !important; }
        
        .timestamp { font-family: monospace; font-size: 0.9em; }
        .number { text-align: right; }
        .address { font-weight: bold; }
        
        /* Status color coding */
        .critical { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .warning { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .good { background-color: #e8f5e8; color: #1b5e20; font-weight: bold; }
        .normal { color: #2e7d32; }
        .unknown { color: #666; font-style: italic; }
        
        /* Battery specific styling */
        .battery-critical { background-color: #ffcdd2; color: #c62828; font-weight: bold; }
        .battery-low { background-color: #ffe0b2; color: #ef6c00; }
        .battery-good { color: #2e7d32; }
        
        /* Utilization styling */
        .util-critical { background-color: #ffcdd2; color: #c62828; font-weight: bold; }
        .util-very-high { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .util-high { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .util-medium { background-color: #fff8e1; color: #f57f17; }
        .voltage-low { background-color: #fff3e0; color: #ef6c00; }
        
        /* Prediction styling */
        .prediction { 
            font-family: monospace; 
            font-size: 0.9em; 
            background-color: #f8f9fa;
            padding: 4px;
            border-radius: 4px;
        }
        
        /* Links */
        a { color: #1976d2; text-decoration: none; }
        a:hover { color: #0d47a1; text-decoration: underline; }
        
        /* Filter controls */
        .filter-container { 
            margin: 15px 0; 
            padding: 15px; 
            background: white; 
            border-radius: 8px; 
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        .filter-input { 
            padding: 8px 12px; 
            margin: 5px; 
            border: 1px solid #ddd; 
            border-radius: 4px; 
            font-size: 14px;
            width: 300px;
        }
        
        .filter-input:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 2px rgba(102,126,234,0.25);
        }
        
        .btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            margin: 5px;
            transition: background 0.2s;
        }
        
        .btn:hover {
            background: #5a6fd8;
        }
        
        .btn-secondary {
            background: #6c757d;
        }
        
        .btn-secondary:hover {
            background: #5a6268;
        }
        
        /* Responsive design */
        @media (max-width: 768px) {
            .stats-grid { grid-template-columns: 1fr; }
            .filter-input { width: 100%; max-width: 300px; }
            table { font-size: 0.9em; }
            th, td { padding: 8px 4px; }
        }
        
        /* Navigation */
        .nav-menu {
            background: white;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        .nav-menu a {
            display: inline-block;
            padding: 8px 16px;
            margin: 5px;
            background: #f8f9fa;
            border-radius: 4px;
            text-decoration: none;
            transition: background 0.2s;
        }
        
        .nav-menu a:hover {
            background: #e9ecef;
        }
        
        /* Collapsible sections */
        .collapsible {
            cursor: pointer;
            user-select: none;
        }
        
        .collapsible:hover {
            background: #f8f9fa;
        }
        
        .hidden { display: none; }
    </style>
    <script>
        // Table sorting functionality
        function sortTable(tableId, columnIndex) {
            const table = document.getElementById(tableId);
            const tbody = table.querySelector('tbody') || table;
            const rows = Array.from(tbody.querySelectorAll('tr')).slice(1);
            const header = table.querySelectorAll('th')[columnIndex];
            
            // Remove existing sort indicators
            table.querySelectorAll('th').forEach(th => {
                th.classList.remove('sort-asc', 'sort-desc');
            });
            
            // Determine sort direction
            const isAscending = !header.dataset.sortDirection || header.dataset.sortDirection === 'desc';
            header.dataset.sortDirection = isAscending ? 'asc' : 'desc';
            header.classList.add(isAscending ? 'sort-asc' : 'sort-desc');
            
            // Sort rows
            rows.sort((a, b) => {
                const aText = a.cells[columnIndex]?.textContent.trim() || '';
                const bText = b.cells[columnIndex]?.textContent.trim() || '';
                
                // Handle N/A values
                if (aText === 'N/A' && bText === 'N/A') return 0;
                if (aText === 'N/A') return isAscending ? 1 : -1;
                if (bText === 'N/A') return isAscending ? -1 : 1;
                
                // Try numeric comparison first
                const aNum = parseFloat(aText.replace(/[^\d.-]/g, ''));
                const bNum = parseFloat(bText.replace(/[^\d.-]/g, ''));
                
                if (!isNaN(aNum) && !isNaN(bNum)) {
                    return isAscending ? aNum - bNum : bNum - aNum;
                }
                
                // Fallback to string comparison
                return isAscending ? aText.localeCompare(bText) : bText.localeCompare(aText);
            });
            
            // Reorder DOM
            rows.forEach(row => tbody.appendChild(row));
        }
        
        // Table filtering
        function filterTable(tableId, filterValue) {
            const table = document.getElementById(tableId);
            const rows = table.querySelectorAll('tbody tr, tr:not(:first-child)');
            const searchTerm = filterValue.toLowerCase();
            
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? '' : 'none';
            });
        }
        
        // Toggle section visibility
        function toggleSection(sectionId) {
            const section = document.getElementById(sectionId);
            section.classList.toggle('hidden');
        }
        
        // Initialize page
        document.addEventListener('DOMContentLoaded', function() {
            // Add click handlers to table headers
            document.querySelectorAll('table').forEach((table, tableIndex) => {
                table.id = table.id || 'table-' + tableIndex;
                table.querySelectorAll('th').forEach((header, columnIndex) => {
                    header.addEventListener('click', () => sortTable(table.id, columnIndex));
                    header.title = 'Click to sort by ' + header.textContent.trim();
                });
            });
        });
    </script>
</head>
<body>
HTML_HEADER

        # Dashboard header
        echo "<div class='dashboard-header'>"
        echo "<h1>🌐 Meshtastic Telemetry Dashboard</h1>"
        echo "<p>Last updated: <strong>$(date)</strong></p>"
        echo "</div>"
        
        # Navigation menu
        echo "<div class='nav-menu'>"
        echo "<a href='#overview'>📊 Overview</a>"
        echo "<a href='#monitored-nodes'>🎯 Monitored Nodes</a>"
        echo "<a href='#recent-telemetry'>📈 Recent Data</a>"
        echo "<a href='#node-list'>📡 All Nodes</a>"
        echo "<a href='#predictions'>🔮 Predictions</a>"
        echo "</div>"
        
        # Overview statistics
        echo "<h2 id='overview'>📊 System Overview</h2>"
        echo "<div class='stats-grid'>"
        
        # Calculate overview stats
        local total_nodes=${#ADDRESSES[@]}
        local active_nodes=0
        local total_attempts=0
        local successful_attempts=0
        
        if [ -f "$TELEMETRY_CSV" ]; then
            # Count recent successful telemetry (last 24 hours)
            local cutoff_time=$(date -d '24 hours ago' '+%Y-%m-%d' 2>/dev/null || date -v-24H '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
            active_nodes=$(grep ",$cutoff_time.*,success" "$TELEMETRY_CSV" | cut -d',' -f2 | sort -u | wc -l)
            
            total_attempts=$(tail -n +2 "$TELEMETRY_CSV" | wc -l)
            successful_attempts=$(grep ",success," "$TELEMETRY_CSV" | wc -l)
        fi
        
        local success_rate=0
        if [ "$total_attempts" -gt 0 ]; then
            success_rate=$(echo "scale=1; $successful_attempts * 100 / $total_attempts" | bc -l 2>/dev/null || echo "0")
        fi
        
        echo "<div class='stat-card'>"
        echo "<div class='stat-value'>$total_nodes</div>"
        echo "<div class='stat-label'>Monitored Nodes</div>"
        echo "</div>"
        
        echo "<div class='stat-card'>"
        echo "<div class='stat-value'>$active_nodes</div>"
        echo "<div class='stat-label'>Active (24h)</div>"
        echo "</div>"
        
        echo "<div class='stat-card'>"
        echo "<div class='stat-value'>${success_rate}%</div>"
        echo "<div class='stat-label'>Success Rate</div>"
        echo "</div>"
        
        echo "<div class='stat-card'>"
        echo "<div class='stat-value'>$total_attempts</div>"
        echo "<div class='stat-label'>Total Requests</div>"
        echo "</div>"
        
        echo "</div>"
        
        # Monitored nodes summary
        echo "<h2 id='monitored-nodes'>🎯 Monitored Node Status</h2>"
        echo "<div class='filter-container'>"
        echo "<input type='text' class='filter-input' placeholder='Filter nodes...' onkeyup='filterTable(\"monitored-table\", this.value)'>"
        echo "<button class='btn btn-secondary' onclick='this.previousElementSibling.value=\"\"; filterTable(\"monitored-table\", \"\")'>Clear</button>"
        echo "</div>"
        
        echo "<table id='monitored-table'>"
        echo "<thead><tr>"
        echo "<th>#</th><th>Node Address</th><th>Device Name</th><th>Battery (%)</th><th>Voltage (V)</th>"
        echo "<th>Channel Util (%)</th><th>TX Util (%)</th><th>Uptime</th><th>Last Seen</th>"
        echo "<th>Success Rate</th><th>6h Prediction</th><th>12h Prediction</th><th>24h Prediction</th>"
        echo "</tr></thead><tbody>"
        
        # Process each monitored node
        local index=1
        for addr in "${ADDRESSES[@]}"; do
            # Get latest telemetry data
            local latest_data=""
            if [ -f "$TELEMETRY_CSV" ]; then
                latest_data=$(grep ",$addr,success" "$TELEMETRY_CSV" | tail -1)
            fi
            
            local device_name="Unknown"
            local battery="N/A" voltage="N/A" channel_util="N/A" tx_util="N/A" uptime="N/A"
            local last_seen="Never"
            
            if [ -n "$latest_data" ]; then
                IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime <<< "$latest_data"
                last_seen="$timestamp"
            fi
            
            # Get device name from cache
            device_name="$(get_node_info "$addr")"
            if [ "$device_name" = "$addr" ]; then
                device_name="Unknown"
            fi
            
            # Calculate success rate for this node
            local node_attempts=0
            local node_successes=0
            local success_rate_pct="N/A"
            
            if [ -f "$TELEMETRY_CSV" ]; then
                node_attempts=$(grep ",$addr," "$TELEMETRY_CSV" | wc -l)
                node_successes=$(grep ",$addr,success" "$TELEMETRY_CSV" | wc -l)
                
                if [ "$node_attempts" -gt 0 ]; then
                    success_rate_pct=$(echo "scale=1; $node_successes * 100 / $node_attempts" | bc -l 2>/dev/null || echo "0")
                    success_rate_pct="${success_rate_pct}%"
                fi
            fi
            
            # Get ML predictions
            local pred_6h="N/A" pred_12h="N/A" pred_24h="N/A"
            if [ -f "$PREDICTIONS_LOG" ] && [ -n "$battery" ] && [[ "$battery" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                pred_6h=$(calculate_ml_prediction "$addr" "$battery" "6")
                pred_12h=$(calculate_ml_prediction "$addr" "$battery" "12")
                pred_24h=$(calculate_ml_prediction "$addr" "$battery" "24")
                
                # Format predictions with icons
                if [ "$pred_6h" != "N/A" ]; then
                    pred_6h="${pred_6h}% 🔋"
                    pred_12h="${pred_12h}% 🔋"
                    pred_24h="${pred_24h}% 🔋"
                fi
            fi
            
            # Apply CSS classes
            local battery_class=$(get_value_class "$battery" "battery")
            local voltage_class=$(get_value_class "$voltage" "voltage")
            local channel_util_class=$(get_value_class "$channel_util" "channel_util")
            local tx_util_class=$(get_value_class "$tx_util" "tx_util")
            
            # Convert uptime to readable format
            local uptime_display
            uptime_display=$(convert_uptime_to_hours "$uptime")
            
            echo "<tr>"
            echo "<td class='number'>$index</td>"
            echo "<td class='address'>$addr</td>"
            echo "<td>$device_name</td>"
            echo "<td class='number $battery_class'>$battery</td>"
            echo "<td class='number $voltage_class'>$voltage</td>"
            echo "<td class='number $channel_util_class'>$channel_util</td>"
            echo "<td class='number $tx_util_class'>$tx_util</td>"
            echo "<td class='number'>$uptime_display</td>"
            echo "<td class='timestamp'>$(format_human_time "$last_seen")</td>"
            echo "<td class='number'>$success_rate_pct</td>"
            echo "<td class='prediction'>$pred_6h</td>"
            echo "<td class='prediction'>$pred_12h</td>"
            echo "<td class='prediction'>$pred_24h</td>"
            echo "</tr>"
            
            index=$((index + 1))
        done
        
        echo "</tbody></table>"
        
        # Recent telemetry data
        echo "<h2 id='recent-telemetry'>📈 Recent Telemetry Data</h2>"
        echo "<div class='filter-container'>"
        echo "<input type='text' class='filter-input' placeholder='Filter recent data...' onkeyup='filterTable(\"recent-table\", this.value)'>"
        echo "<button class='btn btn-secondary' onclick='this.previousElementSibling.value=\"\"; filterTable(\"recent-table\", \"\")'>Clear</button>"
        echo "</div>"
        
        echo "<table id='recent-table'>"
        echo "<thead><tr>"
        echo "<th>Timestamp</th><th>Node</th><th>Status</th><th>Battery (%)</th>"
        echo "<th>Voltage (V)</th><th>Channel Util (%)</th><th>TX Util (%)</th><th>Uptime</th>"
        echo "</tr></thead><tbody>"
        
        # Show last 20 telemetry entries
        if [ -f "$TELEMETRY_CSV" ]; then
            tail -n 21 "$TELEMETRY_CSV" | tail -n +2 | tac | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
                local device_name
                device_name="$(get_node_info "$address")"
                if [ "$device_name" = "$address" ]; then
                    device_name="Unknown"
                fi
                
                local status_class="normal"
                case "$status" in
                    "success") status_class="good" ;;
                    "timeout") status_class="warning" ;;
                    "error") status_class="critical" ;;
                esac
                
                local battery_class=$(get_value_class "$battery" "battery")
                local voltage_class=$(get_value_class "$voltage" "voltage")
                local channel_util_class=$(get_value_class "$channel_util" "channel_util")
                local tx_util_class=$(get_value_class "$tx_util" "tx_util")
                
                local uptime_display
                uptime_display=$(convert_uptime_to_hours "$uptime")
                
                echo "<tr>"
                echo "<td class='timestamp'>$(format_human_time "$timestamp")</td>"
                echo "<td class='address'>$address ($device_name)</td>"
                echo "<td class='$status_class'>$status</td>"
                echo "<td class='number $battery_class'>$battery</td>"
                echo "<td class='number $voltage_class'>$voltage</td>"
                echo "<td class='number $channel_util_class'>$channel_util</td>"
                echo "<td class='number $tx_util_class'>$tx_util</td>"
                echo "<td class='number'>$uptime_display</td>"
                echo "</tr>"
            done
        fi
        
        echo "</tbody></table>"
        
        # All discovered nodes
        echo "<h2 id='node-list' class='collapsible' onclick='toggleSection(\"node-list-content\")'>📡 All Discovered Nodes <span style='font-size: 0.8em;'>[click to toggle]</span></h2>"
        echo "<div id='node-list-content'>"
        
        if [ -f "$NODES_CSV" ]; then
            echo "<div class='filter-container'>"
            echo "<input type='text' class='filter-input' placeholder='Filter all nodes...' onkeyup='filterTable(\"all-nodes-table\", this.value)'>"
            echo "<button class='btn btn-secondary' onclick='this.previousElementSibling.value=\"\"; filterTable(\"all-nodes-table\", \"\")'>Clear</button>"
            echo "</div>"
            
            echo "<table id='all-nodes-table'>"
            echo "<thead><tr>"
            echo "<th>#</th><th>User</th><th>ID</th><th>Hardware</th><th>GPS</th><th>Battery</th><th>Last Heard</th>"
            echo "</tr></thead><tbody>"
            
            local node_index=1
            tail -n +2 "$NODES_CSV" | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
                # Remove quotes
                user=$(echo "$user" | sed 's/^"//;s/"$//')
                hardware=$(echo "$hardware" | sed 's/^"//;s/"$//')
                latitude=$(echo "$latitude" | sed 's/^"//;s/"$//')
                longitude=$(echo "$longitude" | sed 's/^"//;s/"$//')
                
                # Create GPS link if coordinates are valid
                local gps_display="N/A"
                if [ -n "$latitude" ] && [ -n "$longitude" ] && \
                   [ "$latitude" != "N/A" ] && [ "$longitude" != "N/A" ] && \
                   [ "$latitude" != "0.0" ] && [ "$longitude" != "0.0" ]; then
                    gps_display="<a href='https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}&zoom=15' target='_blank' title='View on map'>${latitude}, ${longitude}</a>"
                fi
                
                local battery_class=$(get_value_class "$battery" "battery")
                
                echo "<tr>"
                echo "<td class='number'>$node_index</td>"
                echo "<td>${user:-N/A}</td>"
                echo "<td class='address'>$id</td>"
                echo "<td>${hardware:-N/A}</td>"
                echo "<td>$gps_display</td>"
                echo "<td class='number $battery_class'>${battery:-N/A}</td>"
                echo "<td class='timestamp'>$(format_human_time "${lastheard:-N/A}")</td>"
                echo "</tr>"
                
                node_index=$((node_index + 1))
            done
            
            echo "</tbody></table>"
        else
            echo "<p>No node data available yet. Run a collection cycle to discover nodes.</p>"
        fi
        
        echo "</div>"
        
        # ML Predictions section
        echo "<h2 id='predictions'>🔮 Machine Learning Predictions</h2>"
        
        if [ -f "$PREDICTIONS_LOG" ] && [ "$(tail -n +2 "$PREDICTIONS_LOG" | wc -l)" -gt 0 ]; then
            echo "<p>Advanced power predictions based on historical data and weather conditions.</p>"
            
            echo "<table>"
            echo "<thead><tr>"
            echo "<th>Timestamp</th><th>Node</th><th>Current Battery</th><th>6h Prediction</th><th>12h Prediction</th><th>24h Prediction</th><th>Weather</th>"
            echo "</tr></thead><tbody>"
            
            tail -n 11 "$PREDICTIONS_LOG" | tail -n +2 | tac | while IFS=',' read -r timestamp node_id current_battery pred_6h pred_12h pred_24h weather_desc cloud_cover solar_eff; do
                local device_name
                device_name="$(get_node_info "$node_id")"
                if [ "$device_name" = "$node_id" ]; then
                    device_name="Unknown"
                fi
                
                echo "<tr>"
                echo "<td class='timestamp'>$(format_human_time "$timestamp")</td>"
                echo "<td class='address'>$node_id ($device_name)</td>"
                echo "<td class='number'>${current_battery}%</td>"
                echo "<td class='prediction'>${pred_6h}%</td>"
                echo "<td class='prediction'>${pred_12h}%</td>"
                echo "<td class='prediction'>${pred_24h}%</td>"
                echo "<td>$weather_desc</td>"
                echo "</tr>"
            done
            
            echo "</tbody></table>"
        else
            echo "<div class='stat-card'>"
            echo "<p><strong>🤖 ML System Initializing</strong></p>"
            echo "<p>Machine learning predictions will appear here after sufficient data is collected.</p>"
            echo "</div>"
        fi
        
        # Footer
        echo "<div style='margin-top: 40px; padding: 20px; background: white; border-radius: 8px; text-align: center; color: #666;'>"
        echo "<p>Generated by Meshtastic Unified Telemetry Logger</p>"
        echo "<p>Last update: $(date) | Next update in ${POLLING_INTERVAL}s</p>"
        echo "</div>"
        
        echo "</body></html>"
        
    } > "$STATS_HTML"
    
    debug_log "HTML dashboard generated: $STATS_HTML"
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

# Single collection cycle
run_collection_cycle() {
    echo "🔄 Starting telemetry collection cycle at $(iso8601_date)"
    
    # 1. Load/reload node info cache
    load_node_info_cache
    
    # 2. Collect telemetry from all monitored nodes
    echo "📡 Collecting telemetry from ${#ADDRESSES[@]} monitored nodes..."
    run_telemetry_sequential
    
    # 3. Update and parse node discovery data
    echo "🔍 Updating node discovery data..."
    update_nodes_log
    parse_nodes_to_csv "$NODES_LOG" "$NODES_CSV"
    
    # 4. Reload cache with updated node data
    load_node_info_cache
    
    # 5. Generate weather predictions
    echo "🌤️ Generating weather-based predictions..."
    generate_weather_predictions
    
    # 6. Run ML analysis if enabled
    if [ "$ML_ENABLED" = "true" ]; then
        echo "🤖 Running ML power prediction analysis..."
        run_ml_analysis
    fi
    
    # 7. Generate HTML dashboard
    echo "📊 Generating HTML dashboard..."
    generate_stats_html
    
    echo "✅ Collection cycle completed successfully"
    echo "📈 Dashboard available at: $STATS_HTML"
}

# Configuration manager
run_config_manager() {
    echo "⚙️ Meshtastic Telemetry Logger Configuration"
    echo
    
    if [ ! -f ".env" ]; then
        echo "Creating default configuration file..."
        cat > .env << 'CONFIG_EOF'
# Meshtastic Telemetry Logger Configuration

# Basic Settings
POLLING_INTERVAL=300          # Time between collection cycles (seconds)
DEBUG_MODE=false              # Enable debug output (true/false)

# Timeouts (seconds)
TELEMETRY_TIMEOUT=120         # Timeout for individual telemetry requests
NODES_TIMEOUT=60              # Timeout for node discovery
WEATHER_TIMEOUT=30            # Timeout for weather API calls
ML_TIMEOUT=60                 # Timeout for ML processing

# Node Monitoring - Replace with your actual node IDs
MONITORED_NODES="!9eed0410,!2c9e092b,!849c4818"

# Weather & Location (optional)
WEATHER_API_KEY=              # OpenWeatherMap API key (leave empty for mock data)
DEFAULT_LATITUDE=50.1109      # Your location latitude
DEFAULT_LONGITUDE=8.6821      # Your location longitude

# Machine Learning Features
ML_ENABLED=true               # Enable ML power predictions
ML_MIN_DATA_POINTS=5          # Minimum data points for predictions

# File Paths (usually don't need to change)
TELEMETRY_CSV=telemetry_log.csv
NODES_CSV=nodes_log.csv
HTML_OUTPUT=stats.html
CONFIG_EOF
        echo "✅ Created default .env configuration file"
    fi
    
    echo "Current configuration:"
    echo "====================="
    cat .env
    echo
    echo "To modify configuration:"
    echo "1. Edit the .env file with your preferred text editor"
    echo "2. Update MONITORED_NODES with your actual node addresses"
    echo "3. Add your OpenWeatherMap API key for real weather data (optional)"
    echo "4. Adjust timeouts and intervals as needed"
    echo
    echo "Example: nano .env"
}

# Usage information
show_usage() {
    cat << 'USAGE_EOF'
🌐 Meshtastic Unified Telemetry Logger

USAGE: ./meshtastic-unified.sh [COMMAND] [OPTIONS]

COMMANDS:
    run           Run continuous telemetry collection (default)
    once          Run single collection cycle
    html          Generate HTML dashboard only (from existing data)
    config        Configure the logger (create/edit .env file)
    help          Show this help message

OPTIONS:
    --debug       Enable debug output
    --no-ml       Disable ML features for this run
    --interval N  Override polling interval (seconds)

EXAMPLES:
    ./meshtastic-unified.sh                    # Run continuous collection
    ./meshtastic-unified.sh once               # Single collection cycle
    ./meshtastic-unified.sh html               # Generate dashboard only
    ./meshtastic-unified.sh config             # Configure settings
    ./meshtastic-unified.sh --debug run        # Run with debug output
    ./meshtastic-unified.sh --interval 600 once # Single cycle with custom interval

CONFIGURATION:
    Configuration is managed through the .env file.
    Run './meshtastic-unified.sh config' to set up or modify configuration.

FEATURES:
    ✅ Telemetry collection from Meshtastic nodes
    ✅ Weather-based solar energy predictions
    ✅ Machine learning battery life predictions
    ✅ Interactive HTML dashboard with filtering and sorting
    ✅ Node discovery and GPS integration
    ✅ Historical data analysis and trends
    ✅ Real-time health monitoring with color-coded alerts

FILES CREATED:
    - telemetry_log.csv     : Historical telemetry data
    - nodes_log.csv         : Discovered nodes database
    - stats.html           : Interactive dashboard
    - power_predictions.csv : ML predictions log
    - prediction_accuracy.csv : ML accuracy tracking
    - weather_cache/       : Weather data cache

For more information, visit: https://github.com/meshtastic/telemetry-logger
USAGE_EOF
}

# Parse command line arguments
COMMAND="run"
OVERRIDE_INTERVAL=""
OVERRIDE_ML=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG=1
            DEBUG_MODE=true
            shift
            ;;
        --no-ml)
            OVERRIDE_ML="false"
            shift
            ;;
        --interval)
            OVERRIDE_INTERVAL="$2"
            shift 2
            ;;
        run|once|html|config|help)
            COMMAND="$1"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Apply command line overrides
if [ -n "$OVERRIDE_INTERVAL" ]; then
    POLLING_INTERVAL="$OVERRIDE_INTERVAL"
fi
if [ -n "$OVERRIDE_ML" ]; then
    ML_ENABLED="$OVERRIDE_ML"
fi

# Validate configuration for run commands
if [ "$COMMAND" = "run" ] || [ "$COMMAND" = "once" ]; then
    if [ ${#ADDRESSES[@]} -eq 0 ]; then
        echo "❌ Error: No valid node addresses configured."
        echo "Please run './meshtastic-unified.sh config' to configure node monitoring."
        exit 1
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
fi

# Initialize files
init_telemetry_files

# Execute the requested command
case "$COMMAND" in
    run)
        echo "🚀 Starting continuous telemetry collection..."
        echo "📊 Monitoring ${#ADDRESSES[@]} nodes with ${POLLING_INTERVAL}s interval"
        echo "🛑 Press Ctrl+C to stop"
        echo
        
        # Trap Ctrl+C for graceful shutdown
        trap 'echo "🛑 Shutting down gracefully..."; exit 0' INT
        
        while true; do
            run_collection_cycle
            echo
            echo "😴 Sleeping for ${POLLING_INTERVAL} seconds..."
            echo "📅 Next collection at: $(date -d "+${POLLING_INTERVAL} seconds" 2>/dev/null || date -v+${POLLING_INTERVAL}S 2>/dev/null || echo "in ${POLLING_INTERVAL} seconds")"
            sleep "$POLLING_INTERVAL"
        done
        ;;
        
    once)
        echo "🎯 Running single collection cycle..."
        run_collection_cycle
        echo
        echo "✅ Single cycle completed!"
        echo "📊 Dashboard: $STATS_HTML"
        ;;
        
    html)
        echo "🎨 Generating HTML dashboard from existing data..."
        if [ ! -f "$TELEMETRY_CSV" ] || [ "$(tail -n +2 "$TELEMETRY_CSV" | wc -l)" -eq 0 ]; then
            echo "❌ Error: No telemetry data found. Run a collection cycle first."
            exit 1
        fi
        load_node_info_cache
        generate_stats_html
        echo "✅ Dashboard generated: $STATS_HTML"
        ;;
        
    config)
        run_config_manager
        ;;
        
    help)
        show_usage
        ;;
        
    *)
        echo "❌ Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

# End of unified script
