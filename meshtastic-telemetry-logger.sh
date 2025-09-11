#!/bin/bash

# ---- CONFIGURATION ----
DEBUG=1  # Set to 1 to enable debug output
# ---- FUNCTIONS ----

# Debug log function (prints only if DEBUG=1)
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        printf '[DEBUG] %s\n' "$*" >&2
    fi
}
ADDRESSES=('!9eed0410' '!2c9e092b' '!849c4818' '!fd17c0ed' '!a0cc8008' '!ba656304' '!2df67288' '!277db5ca' '!75e98c18' '!b03d9844') # Add/change as needed
INTERVAL=300                        # Polling interval in seconds
TELEMETRY_CSV="telemetry_log.csv"
NODES_LOG="nodes_log.txt"
NODES_CSV="nodes_log.csv"
STATS_HTML="stats.html"
ERROR_LOG="error.log"

# ---- INIT ----
if [ ! -f "$TELEMETRY_CSV" ]; then
    echo "timestamp,address,status,battery,voltage,channel_util,tx_util,uptime" > "$TELEMETRY_CSV"
fi


# ---- FUNCTIONS ----

# Portable ISO 8601 date function (supports macOS and Linux)
iso8601_date() {
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        date --iso-8601=seconds
    else
        # BSD date (macOS)
        date "+%Y-%m-%dT%H:%M:%S%z"
    fi
}

get_node_info() {
    local node_id="$1"
    if [ -f "$NODES_CSV" ]; then
        # Look up node information from CSV (User, Hardware)
        awk -F, -v id="$node_id" '$2 == id {
            user = $1; gsub(/^"|"$/, "", user)  # Remove quotes if present
            hardware = $4; gsub(/^"|"$/, "", hardware)  # Remove quotes if present
            if (user != "" && hardware != "") {
                print user " " hardware
            } else if (user != "") {
                print user
            } else {
                print id
            }
            exit
        }' "$NODES_CSV"
    else
        echo "$node_id"
    fi
}

# Function to get CSS class for value-based color coding
get_value_class() {
    local value="$1"
    local type="$2"
    
    if [ -z "$value" ] || [ "$value" = "N/A" ] || [ "$value" = "" ]; then
        echo "unknown"
        return
    fi
    
    case "$type" in
        "battery")
            if (( $(echo "$value <= 10" | bc -l 2>/dev/null) )); then
                echo "battery-critical"
            elif (( $(echo "$value <= 25" | bc -l 2>/dev/null) )); then
                echo "battery-low"
            else
                echo "battery-good"
            fi
            ;;
        "voltage")
            # Typical LoRa device voltage ranges: 3.0V+ good, 2.8-3.0V warning, <2.8V critical
            if (( $(echo "$value < 2.8" | bc -l 2>/dev/null) )); then
                echo "critical"
            elif (( $(echo "$value < 3.0" | bc -l 2>/dev/null) )); then
                echo "voltage-low"
            else
                echo "normal"
            fi
            ;;
        "channel_util")
            if (( $(echo "$value >= 80" | bc -l 2>/dev/null) )); then
                echo "util-very-high"
            elif (( $(echo "$value >= 50" | bc -l 2>/dev/null) )); then
                echo "util-high"
            elif (( $(echo "$value >= 25" | bc -l 2>/dev/null) )); then
                echo "warning"
            else
                echo "normal"
            fi
            ;;
        "tx_util")
            # 10% per hour airtime limitation - be much more strict
            if (( $(echo "$value >= 8" | bc -l 2>/dev/null) )); then
                echo "util-very-high"  # Critical - approaching 10% limit
            elif (( $(echo "$value >= 5" | bc -l 2>/dev/null) )); then
                echo "util-high"       # High - getting close to limit
            elif (( $(echo "$value >= 2" | bc -l 2>/dev/null) )); then
                echo "warning"         # Warning - moderate usage
            else
                echo "normal"          # Normal - low usage
            fi
            ;;
        "time_left")
            if [[ "$value" == "Stable/Charging" ]]; then
                echo "good"
            elif [[ "$value" == *"fast drain"* ]]; then
                echo "critical"
            elif [[ "$value" == *"?"* ]]; then
                echo "unknown"
            elif [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                # Numeric value - check hours
                if (( $(echo "$value < 6" | bc -l 2>/dev/null) )); then
                    echo "time-critical"
                elif (( $(echo "$value < 24" | bc -l 2>/dev/null) )); then
                    echo "time-warning"
                else
                    echo "normal"
                fi
            else
                echo "normal"
            fi
            ;;
        *)
            echo "normal"
            ;;
    esac
}

# Get weather predictions for a specific node
get_weather_predictions() {
    local node_id="$1"
    local predictions_file="weather_predictions.json"
    
    # Default values if predictions not available
    local pred_6h="N/A"
    local pred_12h="N/A" 
    local pred_24h="N/A"
    
    if [ -f "$predictions_file" ]; then
        # Extract prediction for this node ID
        local prediction_text=$(jq -r --arg id "$node_id" '.predictions[] | select(.node_id == $id) | .prediction' "$predictions_file" 2>/dev/null)
        
        if [ -n "$prediction_text" ] && [ "$prediction_text" != "null" ] && [ "$prediction_text" != "Unknown battery level" ]; then
            # Parse prediction text like "+3h: 93% 🔋 (Clear, 5% clouds) | +6h: 87% 🔋 (Clear, 92% clouds) | +9h: 81% 🔋 (Clear, 66% clouds)"
            # Extract 6h prediction (which is actually +6h in the format)
            pred_6h=$(echo "$prediction_text" | sed -n 's/.*+6h: \([0-9]\+%[^|]*\).*/\1/p' | sed 's/^ *//')
            
            # For 12h and 24h, we'll extrapolate based on the trend
            local current_battery=$(jq -r --arg id "$node_id" '.predictions[] | select(.node_id == $id) | .current_battery' "$predictions_file" 2>/dev/null)
            local h6_battery=$(echo "$pred_6h" | sed 's/%.*$//')
            
            if [ -n "$current_battery" ] && [ "$current_battery" != "Unknown" ] && [ -n "$h6_battery" ] && [ "$h6_battery" != "" ]; then
                # Calculate battery change rate per hour
                local battery_change=$(echo "scale=2; ($h6_battery - ${current_battery%.*}) / 6" | bc 2>/dev/null)
                
                if [ -n "$battery_change" ]; then
                    # Project 12h and 24h assuming linear trend (simplified)
                    local h12_battery=$(echo "scale=0; ${current_battery%.*} + $battery_change * 12" | bc 2>/dev/null)
                    local h24_battery=$(echo "scale=0; ${current_battery%.*} + $battery_change * 24" | bc 2>/dev/null)
                    
                    # Clamp values between 0 and 100
                    h12_battery=$(echo "$h12_battery" | awk '{print ($1 < 0) ? 0 : ($1 > 100) ? 100 : int($1)}')
                    h24_battery=$(echo "$h24_battery" | awk '{print ($1 < 0) ? 0 : ($1 > 100) ? 100 : int($1)}')
                    
                    # Determine status icons based on battery level and trend
                    local h12_icon="🔋"
                    local h24_icon="🔋"
                    
                    if (( $(echo "$battery_change > 0.5" | bc -l 2>/dev/null) )); then
                        h12_icon="⚡"; h24_icon="⚡"  # Charging
                    elif (( $(echo "$battery_change < -1" | bc -l 2>/dev/null) )); then
                        h12_icon="📉"; h24_icon="📉"  # Fast drain
                    fi
                    
                    pred_12h="${h12_battery}% ${h12_icon}"
                    pred_24h="${h24_battery}% ${h24_icon}"
                fi
            fi
        fi
    fi
    
    echo "$pred_6h|$pred_12h|$pred_24h"
}

run_telemetry() {
    local addr="$1"
    local ts
    ts=$(iso8601_date)
    local out
    debug_log "Requesting telemetry for $addr at $ts"
    out=$(meshtastic --request-telemetry --dest "$addr" 2>&1)
    debug_log "Telemetry output: $out"
    local status="unknown"
    local battery="" voltage="" channel_util="" tx_util="" uptime=""

    if echo "$out" | grep -q "Telemetry received:"; then
        status="success"
        battery=$(echo "$out" | grep "Battery level:" | awk -F: '{print $2}' | tr -d ' %')
        voltage=$(echo "$out" | grep "Voltage:" | awk -F: '{print $2}' | tr -d ' V')
        channel_util=$(echo "$out" | grep "Total channel utilization:" | awk -F: '{print $2}' | tr -d ' %')
        tx_util=$(echo "$out" | grep "Transmit air utilization:" | awk -F: '{print $2}' | tr -d ' %')
        uptime=$(echo "$out" | grep "Uptime:" | awk -F: '{print $2}' | tr -d ' s')
        debug_log "Telemetry success: battery=$battery, voltage=$voltage, channel_util=$channel_util, tx_util=$tx_util, uptime=$uptime"
    elif echo "$out" | grep -q "Timed out waiting for telemetry"; then
        status="timeout"
        debug_log "Telemetry timeout for $addr"
    else
        status="error"
        debug_log "Telemetry error for $addr: $out"
        echo "$ts [$addr] ERROR: $out" >> "$ERROR_LOG"
    fi

    echo "$ts,$addr,$status,$battery,$voltage,$channel_util,$tx_util,$uptime" >> "$TELEMETRY_CSV"
}

update_nodes_log() {
    local ts
    ts=$(iso8601_date)
    debug_log "Updating nodes log at $ts"
    local out
    out=$(meshtastic --nodes 2>&1)
    debug_log "Nodes output: $out"
    echo "===== $ts =====" >> "$NODES_LOG"
    echo "$out" >> "$NODES_LOG"
}

parse_nodes_to_csv() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        echo "Error: Input file $input_file not found"
        return 1
    fi
    
    # Create temporary files
    local temp_csv="/tmp/nodes_unsorted.csv"
    local temp_data="/tmp/data_rows.txt"
    local temp_merged="/tmp/nodes_merged.csv"

    # Extract data rows (skip header row with "N │ User" and separator rows)
    grep "│.*│" "$input_file" | grep -v "│   N │ User" | grep -v "├─" | grep -v "╞═" | grep -v "╘═" | grep -v "╒═" > "$temp_data"

    # Check if we have any data rows
    if [ ! -s "$temp_data" ]; then
        echo "No data rows found in $input_file"
        rm -f "$temp_data"
        return 1
    fi

    # Write CSV header (skip first column N)
    echo "User,ID,AKA,Hardware,Pubkey,Role,Latitude,Longitude,Altitude,Battery,Channel_util,Tx_air_util,SNR,Hops,Channel,LastHeard,Since" > "$temp_csv"

    # Process each data row
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Split by │ and trim whitespace, skip first field (N)
            echo "$line" | awk -F'│' '{
                user = $3; gsub(/^[ ]+|[ ]+$/, "", user)
                id = $4; gsub(/^[ ]+|[ ]+$/, "", id)
                aka = $5; gsub(/^[ ]+|[ ]+$/, "", aka)
                hardware = $6; gsub(/^[ ]+|[ ]+$/, "", hardware)
                pubkey = $7; gsub(/^[ ]+|[ ]+$/, "", pubkey)
                role = $8; gsub(/^[ ]+|[ ]+$/, "", role)
                latitude = $9; gsub(/^[ ]+|[ ]+$/, "", latitude)
                longitude = $10; gsub(/^[ ]+|[ ]+$/, "", longitude)
                altitude = $11; gsub(/^[ ]+|[ ]+$/, "", altitude)
                battery = $12; gsub(/^[ ]+|[ ]+$/, "", battery)
                channel_util = $13; gsub(/^[ ]+|[ ]+$/, "", channel_util)
                tx_util = $14; gsub(/^[ ]+|[ ]+$/, "", tx_util)
                snr = $15; gsub(/^[ ]+|[ ]+$/, "", snr)
                hops = $16; gsub(/^[ ]+|[ ]+$/, "", hops)
                channel = $17; gsub(/^[ ]+|[ ]+$/, "", channel)
                lastheard = $18; gsub(/^[ ]+|[ ]+$/, "", lastheard)
                since = $19; gsub(/^[ ]+|[ ]+$/, "", since)

                # Escape commas in fields by wrapping in quotes if they contain commas
                if (match(user, /,/)) user = "\"" user "\""
                if (match(id, /,/)) id = "\"" id "\""
                if (match(aka, /,/)) aka = "\"" aka "\""
                if (match(hardware, /,/)) hardware = "\"" hardware "\""
                if (match(pubkey, /,/)) pubkey = "\"" pubkey "\""
                if (match(role, /,/)) role = "\"" role "\""
                if (match(latitude, /,/)) latitude = "\"" latitude "\""
                if (match(longitude, /,/)) longitude = "\"" longitude "\""
                if (match(altitude, /,/)) altitude = "\"" altitude "\""
                if (match(battery, /,/)) battery = "\"" battery "\""
                if (match(channel_util, /,/)) channel_util = "\"" channel_util "\""
                if (match(tx_util, /,/)) tx_util = "\"" tx_util "\""
                if (match(snr, /,/)) snr = "\"" snr "\""
                if (match(hops, /,/)) hops = "\"" hops "\""
                if (match(channel, /,/)) channel = "\"" channel "\""
                if (match(lastheard, /,/)) lastheard = "\"" lastheard "\""
                if (match(since, /,/)) since = "\"" since "\""

                print user","id","aka","hardware","pubkey","role","latitude","longitude","altitude","battery","channel_util","tx_util","snr","hops","channel","lastheard","since
            }' >> "$temp_csv"
        fi
    done < "$temp_data"

    # Merge with existing nodes_log.csv (except header) using awk for portability
    local header
    header=$(head -n 1 "$temp_csv")
    echo "$header" > "$temp_merged"

    # Combine old and new data (skip headers)
    { tail -n +2 "$NODES_CSV" 2>/dev/null; tail -n +2 "$temp_csv"; } > /tmp/nodes_all.csv

    # Use awk to keep only the latest info for each node ID (never delete old nodes)
    awk -F',' '{
        if (!($2 in seen) || $16 > seen[$2]) {
            row[$2]=$0; seen[$2]=$16
        }
    } END {
        for (i in row) print row[i]
    }' /tmp/nodes_all.csv | sort -t, -k16,16r >> "$temp_merged"

    # Write merged and sorted node list to output
    mv "$temp_merged" "$output_file"

    # Clean up temporary files
    rm -f "$temp_csv" "$temp_data" /tmp/nodes_all.csv
}

generate_stats_html() {
    # Generate HTML stats file
    {
        # HTML Header with basic styling
        cat << 'EOF'
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
        .high { background-color: #fff8e1; color: #f57f17; }
        .normal { color: #2e7d32; }
        .good { background-color: #e8f5e8; color: #1b5e20; font-weight: bold; }
        .unknown { color: #666; font-style: italic; }
        
        /* Specific value styling */
        .battery-critical { background-color: #ffcdd2; color: #c62828; font-weight: bold; }
        .battery-low { background-color: #ffe0b2; color: #ef6c00; }
        .battery-good { color: #2e7d32; }
        .util-high { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .util-very-high { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .voltage-low { background-color: #fff3e0; color: #ef6c00; }
        .time-critical { background-color: #ffcdd2; color: #c62828; font-weight: bold; }
        
        /* Weather prediction styling */
        .prediction { 
            font-family: monospace; 
            font-size: 0.9em; 
            background-color: #f8f9fa;
            padding: 4px;
        }
        .time-warning { background-color: #ffe0b2; color: #ef6c00; }
        
        /* Sortable table styles */
        .sort-indicator { float: right; font-size: 12px; margin-left: 5px; }
        .sort-asc::after { content: ' ▲'; }
        .sort-desc::after { content: ' ▼'; }
        
        /* Filter styles */
        .filter-container { margin: 10px 0; }
        .filter-input { 
            padding: 5px; 
            margin: 5px; 
            border: 1px solid #ddd; 
            border-radius: 3px; 
            font-size: 14px;
        }
        .filter-label { 
            font-weight: bold; 
            margin-right: 5px; 
        }
        .clear-filters { 
            background: #f44336; 
            color: white; 
            border: none; 
            padding: 5px 10px; 
            border-radius: 3px; 
            cursor: pointer; 
            margin-left: 10px;
        }
        .clear-filters:hover { background: #d32f2f; }
        
        /* Hide rows when filtering */
        .hidden-row { display: none !important; }
        
        /* GPS link styling */
        a { color: #1976d2; text-decoration: none; }
        a:hover { color: #0d47a1; text-decoration: underline; }
        a[title]:hover { cursor: help; }
    </style>
    <script>
        function makeSortable(tableId) {
            const table = document.getElementById(tableId);
            if (!table) return;
            
            const headers = table.querySelectorAll('th');
            
            headers.forEach((header, index) => {
                header.addEventListener('click', () => sortTable(tableId, index));
                header.style.cursor = 'pointer';
            });
        }
        
        function sortTable(tableId, columnIndex) {
            const table = document.getElementById(tableId);
            const tbody = table.querySelector('tbody') || table;
            const rows = Array.from(tbody.querySelectorAll('tr')).slice(1); // Skip header row
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
                
                // Handle numeric values
                const aNum = parseFloat(aText.replace(/[^\d.-]/g, ''));
                const bNum = parseFloat(bText.replace(/[^\d.-]/g, ''));
                
                let comparison = 0;
                if (!isNaN(aNum) && !isNaN(bNum)) {
                    comparison = aNum - bNum;
                } else {
                    comparison = aText.localeCompare(bText);
                }
                
                return isAscending ? comparison : -comparison;
            });
            
            // Reorder DOM
            rows.forEach(row => tbody.appendChild(row));
        }
        
        function addTableFilter(tableId, placeholder = 'Filter table...') {
            const table = document.getElementById(tableId);
            if (!table) return;
            
            // Create filter container
            const filterContainer = document.createElement('div');
            filterContainer.className = 'filter-container';
            
            // Create filter input
            const filterInput = document.createElement('input');
            filterInput.type = 'text';
            filterInput.className = 'filter-input';
            filterInput.placeholder = placeholder;
            filterInput.addEventListener('input', () => filterTable(tableId, filterInput.value));
            
            // Create clear button
            const clearButton = document.createElement('button');
            clearButton.className = 'clear-filters';
            clearButton.textContent = 'Clear';
            clearButton.addEventListener('click', () => {
                filterInput.value = '';
                filterTable(tableId, '');
            });
            
            filterContainer.appendChild(document.createTextNode('Filter: '));
            filterContainer.appendChild(filterInput);
            filterContainer.appendChild(clearButton);
            
            // Insert before table
            table.parentNode.insertBefore(filterContainer, table);
        }
        
        function filterTable(tableId, filterValue) {
            const table = document.getElementById(tableId);
            const tbody = table.querySelector('tbody') || table;
            const rows = tbody.querySelectorAll('tr');
            const searchTerm = filterValue.toLowerCase();
            
            rows.forEach((row, index) => {
                if (index === 0) return; // Skip header row
                
                const text = row.textContent.toLowerCase();
                if (text.includes(searchTerm)) {
                    row.classList.remove('hidden-row');
                } else {
                    row.classList.add('hidden-row');
                }
            });
        }
        
        // Initialize sortable tables when page loads
        document.addEventListener('DOMContentLoaded', function() {
            // Add unique IDs to tables and make them sortable/filterable
            const tables = document.querySelectorAll('table');
            tables.forEach((table, index) => {
                if (!table.id) {
                    table.id = 'table-' + index;
                }
                makeSortable(table.id);
                
                // Add appropriate filter placeholder based on table content
                let placeholder = 'Filter table...';
                if (table.querySelector('th')?.textContent.includes('Address')) {
                    placeholder = 'Filter by address, device name, status...';
                } else if (table.querySelector('th')?.textContent.includes('Timestamp')) {
                    placeholder = 'Filter by timestamp, values...';
                }
                
                addTableFilter(table.id, placeholder);
            });
        });
    </script>
</head>
<body>
EOF
        
        echo "<h1>Meshtastic Telemetry Statistics</h1>"
        echo "<p>Generated: $(iso8601_date)</p>"
        
        # Display monitored addresses with resolved names
        echo "<h3>Monitored Addresses</h3>"
        echo "<table>"
        echo "<tr><th>#</th><th>Address</th><th>Device Name</th></tr>"
        index=1
        for addr in "${ADDRESSES[@]}"; do
            device_name="$(get_node_info "$addr")"
            if [ -n "$device_name" ] && [ "$device_name" != "$addr" ]; then
                resolved_name="$device_name"
            else
                resolved_name="Unknown"
            fi
            
            # Check if this address has GPS coordinates in the nodes CSV
            if [ -f "$NODES_CSV" ]; then
                gps_coords=$(awk -F, -v id="$addr" '$2 == id {
                    lat = $7; gsub(/^"|"$/, "", lat)
                    lon = $8; gsub(/^"|"$/, "", lon)
                    if (lat != "" && lon != "" && lat != "N/A" && lon != "N/A" && 
                        lat != "0.0" && lon != "0.0" && lat != "0" && lon != "0") {
                        print lat "," lon
                    }
                    exit
                }' "$NODES_CSV")
                
                if [ -n "$gps_coords" ]; then
                    lat=$(echo "$gps_coords" | cut -d',' -f1)
                    lon=$(echo "$gps_coords" | cut -d',' -f2)
                    device_name_display="<a href=\"https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}&zoom=15\" target=\"_blank\" title=\"View ${resolved_name} on OpenStreetMap (${lat}, ${lon})\">${resolved_name}</a>"
                else
                    device_name_display="$resolved_name"
                fi
            else
                device_name_display="$resolved_name"
            fi
            
            echo "<tr>"
            echo "<td class=\"number\">$index</td>"
            echo "<td class=\"address\">$addr</td>"
            echo "<td>$device_name_display</td>"
            echo "</tr>"
            index=$((index + 1))
        done
        echo "</table>"

        # Gather all successful telemetry for per-node stats
        awk -F',' '$3=="success"' "$TELEMETRY_CSV" > /tmp/all_success.csv
        
        # Per-Node Statistics Summary
        echo "<h2>Node Summary Statistics</h2>"
        echo "<table>"
        echo "<tr><th>Address</th><th>Last Seen</th><th>Success</th><th>Failures</th><th>Success Rate</th><th>Battery (%)</th><th>Voltage (V)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (s)</th><th>Min Battery</th><th>Max Battery</th><th>Max Channel Util</th><th>Max Tx Util</th><th>Est. Time Left (h)</th><th>Power in 6h</th><th>Power in 12h</th><th>Power in 24h</th></tr>"
        
        cut -d',' -f2 /tmp/all_success.csv | sort | uniq | while read address; do
            if [ -z "$address" ]; then continue; fi
            
            # Get all records for this address (both success and failures) for counting
            all_attempts=$(grep ",$address," "$TELEMETRY_CSV" | sort -t',' -k1,1)
            total_attempts=$(echo "$all_attempts" | wc -l)
            
            # Count success and failures
            success_count=$(echo "$all_attempts" | awk -F',' '$3=="success"' | wc -l)
            failure_count=$(echo "$all_attempts" | awk -F',' '$3!="success" && $3!=""' | wc -l)
            
            # Calculate success rate
            if [ "$total_attempts" -gt 0 ]; then
                success_rate=$(echo "scale=1; $success_count * 100 / $total_attempts" | bc 2>/dev/null)
                success_rate="${success_rate}%"
            else
                success_rate="N/A"
            fi
            
            # Get all successful records for this address sorted by timestamp
            node_data=$(grep ",$address," /tmp/all_success.csv | sort -t',' -k1,1)
            
            # Get latest record for current values
            latest=$(echo "$node_data" | tail -1)
            IFS=',' read -r latest_timestamp latest_address latest_status latest_battery latest_voltage latest_channel_util latest_tx_util latest_uptime <<< "$latest"
            
            # Calculate min/max battery values
            min_battery=$(echo "$node_data" | awk -F',' '{if($4 != "") print $4}' | sort -n | head -1)
            max_battery=$(echo "$node_data" | awk -F',' '{if($4 != "") print $4}' | sort -nr | head -1)
            
            # Calculate max channel util and tx util values
            max_channel_util=$(echo "$node_data" | awk -F',' '{if($6 != "") print $6}' | sort -nr | head -1)
            max_tx_util=$(echo "$node_data" | awk -F',' '{if($7 != "") print $7}' | sort -nr | head -1)
            
            # Advanced battery life estimation with improved accuracy
            est_hours_left="N/A"
            record_count=$(echo "$node_data" | wc -l)
            
            if [ "$record_count" -ge 2 ] && [ -n "$latest_battery" ] && [ "$latest_battery" != "" ]; then
                # Filter out records with missing battery data
                filtered_data=$(echo "$node_data" | awk -F',' '$4 != "" && $4 > 0')
                filtered_count=$(echo "$filtered_data" | wc -l)
                
                if [ "$filtered_count" -ge 2 ]; then
                    # Use different sample sizes based on available data
                    if [ "$filtered_count" -ge 10 ]; then
                        sample_size=8  # Use last 8 records for better trend analysis
                    elif [ "$filtered_count" -ge 5 ]; then
                        sample_size=5
                    else
                        sample_size=$filtered_count
                    fi
                    
                    # Get sample data (last N records with valid battery)
                    sample_data=$(echo "$filtered_data" | tail -$sample_size)
                    
                    # Calculate multiple trend estimates and average them
                    total_trend=0
                    valid_trends=0
                    
                    # Method 1: First vs Last in sample
                    first_record=$(echo "$sample_data" | head -1)
                    last_record=$(echo "$sample_data" | tail -1)
                    
                    IFS=',' read -r first_ts first_addr first_status first_batt first_volt first_ch first_tx first_up <<< "$first_record"
                    IFS=',' read -r last_ts last_addr last_status last_batt last_volt last_ch last_tx last_up <<< "$last_record"
                    
                    if [ -n "$first_batt" ] && [ -n "$last_batt" ] && [ "$first_batt" != "" ] && [ "$last_batt" != "" ]; then
                        first_epoch=$(date -d "$first_ts" +%s 2>/dev/null)
                        last_epoch=$(date -d "$last_ts" +%s 2>/dev/null)
                        
                        if [ -n "$first_epoch" ] && [ -n "$last_epoch" ] && [ "$last_epoch" -gt "$first_epoch" ]; then
                            time_diff_hours=$(echo "scale=4; ($last_epoch - $first_epoch) / 3600" | bc 2>/dev/null)
                            battery_diff=$(echo "$first_batt - $last_batt" | bc 2>/dev/null)
                            
                            if [ -n "$time_diff_hours" ] && [ -n "$battery_diff" ] && (( $(echo "$time_diff_hours > 0.5" | bc -l 2>/dev/null) )); then
                                trend1=$(echo "scale=6; $battery_diff / $time_diff_hours" | bc 2>/dev/null)
                                if [ -n "$trend1" ]; then
                                    total_trend=$(echo "$total_trend + $trend1" | bc 2>/dev/null)
                                    valid_trends=$((valid_trends + 1))
                                fi
                            fi
                        fi
                    fi
                    
                    # Method 2: Linear regression-like approach using multiple points
                    if [ "$sample_size" -ge 3 ]; then
                        # Calculate average trend from consecutive pairs
                        echo "$sample_data" | while IFS=',' read -r ts addr status batt volt ch tx up; do
                            echo "$ts,$batt"
                        done > /tmp/battery_trend_$$.csv
                        
                        trend_sum=0
                        trend_count=0
                        prev_epoch=""
                        prev_batt=""
                        
                        while IFS=',' read -r ts batt; do
                            if [ -n "$prev_epoch" ] && [ -n "$prev_batt" ] && [ -n "$batt" ] && [ "$batt" != "" ]; then
                                curr_epoch=$(date -d "$ts" +%s 2>/dev/null)
                                if [ -n "$curr_epoch" ] && [ "$curr_epoch" -gt "$prev_epoch" ]; then
                                    time_diff_h=$(echo "scale=4; ($curr_epoch - $prev_epoch) / 3600" | bc 2>/dev/null)
                                    batt_diff=$(echo "$prev_batt - $batt" | bc 2>/dev/null)
                                    
                                    if [ -n "$time_diff_h" ] && [ -n "$batt_diff" ] && (( $(echo "$time_diff_h > 0.1" | bc -l 2>/dev/null) )); then
                                        pair_trend=$(echo "scale=6; $batt_diff / $time_diff_h" | bc 2>/dev/null)
                                        if [ -n "$pair_trend" ]; then
                                            trend_sum=$(echo "$trend_sum + $pair_trend" | bc 2>/dev/null)
                                            trend_count=$((trend_count + 1))
                                        fi
                                    fi
                                fi
                            fi
                            prev_epoch=$(date -d "$ts" +%s 2>/dev/null)
                            prev_batt="$batt"
                        done < /tmp/battery_trend_$$.csv
                        
                        if [ "$trend_count" -gt 0 ]; then
                            avg_trend=$(echo "scale=6; $trend_sum / $trend_count" | bc 2>/dev/null)
                            if [ -n "$avg_trend" ]; then
                                total_trend=$(echo "$total_trend + $avg_trend" | bc 2>/dev/null)
                                valid_trends=$((valid_trends + 1))
                            fi
                        fi
                        
                        rm -f /tmp/battery_trend_$$.csv
                    fi
                    
                    # Calculate final estimate
                    if [ "$valid_trends" -gt 0 ]; then
                        avg_drop_per_hour=$(echo "scale=6; $total_trend / $valid_trends" | bc 2>/dev/null)
                        
                        if [ -n "$avg_drop_per_hour" ]; then
                            # Check for different scenarios
                            if (( $(echo "$avg_drop_per_hour <= 0" | bc -l 2>/dev/null) )); then
                                est_hours_left="Stable/Charging"
                            elif (( $(echo "$avg_drop_per_hour < 0.1" | bc -l 2>/dev/null) )); then
                                # Very slow drain - calculate but cap at reasonable max
                                raw_estimate=$(echo "scale=1; $latest_battery / $avg_drop_per_hour" | bc 2>/dev/null)
                                if [ -n "$raw_estimate" ] && (( $(echo "$raw_estimate > 2160" | bc -l 2>/dev/null) )); then
                                    est_hours_left=">3mo"
                                elif [ -n "$raw_estimate" ] && (( $(echo "$raw_estimate > 720" | bc -l 2>/dev/null) )); then
                                    est_hours_left=">1mo"
                                else
                                    est_hours_left="$raw_estimate"
                                fi
                            elif (( $(echo "$avg_drop_per_hour > 10" | bc -l 2>/dev/null) )); then
                                # Very fast drain - likely abnormal
                                raw_estimate=$(echo "scale=1; $latest_battery / $avg_drop_per_hour" | bc 2>/dev/null)
                                if [ -n "$raw_estimate" ]; then
                                    est_hours_left="$raw_estimate (fast drain)"
                                fi
                            else
                                # Normal drain rate
                                est_hours_left=$(echo "scale=1; $latest_battery / $avg_drop_per_hour" | bc 2>/dev/null)
                                
                                # Add confidence indicator based on data quality
                                if [ "$sample_size" -ge 6 ] && [ "$filtered_count" -ge 8 ]; then
                                    # High confidence - sufficient data
                                    est_hours_left="$est_hours_left"
                                elif [ "$sample_size" -ge 3 ]; then
                                    # Medium confidence
                                    est_hours_left="~$est_hours_left"
                                else
                                    # Low confidence
                                    est_hours_left="~$est_hours_left?"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
            
            # Get device name
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            
            # Format timestamp for display (remove seconds for brevity)
            display_timestamp=$(echo "$latest_timestamp" | sed 's/:[0-9][0-9]+[0-9:+-]*$//')
            
            # Get CSS classes for color coding
            battery_class=$(get_value_class "$latest_battery" "battery")
            voltage_class=$(get_value_class "$latest_voltage" "voltage")
            channel_util_class=$(get_value_class "$latest_channel_util" "channel_util")
            tx_util_class=$(get_value_class "$latest_tx_util" "tx_util")
            min_battery_class=$(get_value_class "$min_battery" "battery")
            max_battery_class=$(get_value_class "$max_battery" "battery")
            max_channel_util_class=$(get_value_class "$max_channel_util" "channel_util")
            max_tx_util_class=$(get_value_class "$max_tx_util" "tx_util")
            time_left_class=$(get_value_class "$est_hours_left" "time_left")
            
            # Color code success rate
            if [ "$total_attempts" -gt 0 ]; then
                success_rate_num=$(echo "$success_rate" | sed 's/%//')
                if (( $(echo "$success_rate_num >= 90" | bc -l 2>/dev/null) )); then
                    success_rate_class="good"
                elif (( $(echo "$success_rate_num >= 70" | bc -l 2>/dev/null) )); then
                    success_rate_class="normal"
                elif (( $(echo "$success_rate_num >= 50" | bc -l 2>/dev/null) )); then
                    success_rate_class="warning"
                else
                    success_rate_class="critical"
                fi
            else
                success_rate_class="unknown"
            fi
            
            echo "<tr>"
            echo "<td class=\"address\">$address_display</td>"
            echo "<td class=\"timestamp\">$display_timestamp</td>"
            echo "<td class=\"number good\">$success_count</td>"
            echo "<td class=\"number critical\">$failure_count</td>"
            echo "<td class=\"number $success_rate_class\">$success_rate</td>"
            echo "<td class=\"number $battery_class\">${latest_battery:-N/A}</td>"
            echo "<td class=\"number $voltage_class\">${latest_voltage:-N/A}</td>"
            echo "<td class=\"number $channel_util_class\">${latest_channel_util:-N/A}</td>"
            echo "<td class=\"number $tx_util_class\">${latest_tx_util:-N/A}</td>"
            echo "<td class=\"number\">${latest_uptime:-N/A}</td>"
            echo "<td class=\"number $min_battery_class\">${min_battery:-N/A}</td>"
            echo "<td class=\"number $max_battery_class\">${max_battery:-N/A}</td>"
            echo "<td class=\"number $max_channel_util_class\">${max_channel_util:-N/A}</td>"
            echo "<td class=\"number $max_tx_util_class\">${max_tx_util:-N/A}</td>"
            echo "<td class=\"number $time_left_class\">$est_hours_left</td>"
            
            # Get weather predictions for this node
            weather_predictions=$(get_weather_predictions "$address")
            IFS='|' read -r pred_6h pred_12h pred_24h <<< "$weather_predictions"
            
            echo "<td class=\"prediction\">${pred_6h}</td>"
            echo "<td class=\"prediction\">${pred_12h}</td>"
            echo "<td class=\"prediction\">${pred_24h}</td>"
            echo "</tr>"
        done
        echo "</table>"

        # Recent Telemetry Data
        echo "<h2>Recent Telemetry Data (Last 20 Records)</h2>"
        echo "<table>"
        echo "<tr><th>Timestamp</th><th>Address</th><th>Battery (%)</th><th>Voltage (V)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (s)</th></tr>"
        
        awk -F',' '$3=="success"' "$TELEMETRY_CSV" | sort -t',' -k1,1r | head -20 | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            
            # Get CSS classes for color coding
            battery_class=$(get_value_class "$battery" "battery")
            voltage_class=$(get_value_class "$voltage" "voltage")
            channel_util_class=$(get_value_class "$channel_util" "channel_util")
            tx_util_class=$(get_value_class "$tx_util" "tx_util")
            
            echo "<tr>"
            echo "<td class=\"timestamp\">$timestamp</td>"
            echo "<td class=\"address\">$address_display</td>"
            echo "<td class=\"number $battery_class\">${battery:-N/A}</td>"
            echo "<td class=\"number $voltage_class\">${voltage:-N/A}</td>"
            echo "<td class=\"number $channel_util_class\">${channel_util:-N/A}</td>"
            echo "<td class=\"number $tx_util_class\">${tx_util:-N/A}</td>"
            echo "<td class=\"number\">${uptime:-N/A}</td>"
            echo "</tr>"
        done
        echo "</table>"

        # Per-Node History
        echo "<h2>Telemetry History by Node</h2>"
        last_address=""
        awk -F',' '$3=="success"' "$TELEMETRY_CSV" | sort -t',' -k2,2 -k1,1r | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            
            # Start new section for each address
            if [ "$last_address" != "$address" ]; then
                if [ -n "$last_address" ]; then 
                    echo "</table>"
                fi
                echo "<h3>$address_display</h3>"
                echo "<table>"
                echo "<tr><th>Timestamp</th><th>Battery (%)</th><th>Voltage (V)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (s)</th></tr>"
                last_address="$address"
            fi
            
            # Get CSS classes for color coding
            battery_class=$(get_value_class "$battery" "battery")
            voltage_class=$(get_value_class "$voltage" "voltage")
            channel_util_class=$(get_value_class "$channel_util" "channel_util")
            tx_util_class=$(get_value_class "$tx_util" "tx_util")
            
            echo "<tr>"
            echo "<td class=\"timestamp\">$timestamp</td>"
            echo "<td class=\"number $battery_class\">${battery:-N/A}</td>"
            echo "<td class=\"number $voltage_class\">${voltage:-N/A}</td>"
            echo "<td class=\"number $channel_util_class\">${channel_util:-N/A}</td>"
            echo "<td class=\"number $tx_util_class\">${tx_util:-N/A}</td>"
            echo "<td class=\"number\">${uptime:-N/A}</td>"
            echo "</tr>"
        done
        if [ -n "$last_address" ]; then 
            echo "</table>"
        fi

        # Current Node List
        if [ -f "$NODES_CSV" ]; then
            echo "<h2>Current Node List</h2>"
            echo "<table>"
            echo "<tr><th>#</th><th>User</th><th>ID</th><th>Hardware</th><th>Battery (%)</th><th>Channel Util (%)</th><th>Last Heard</th></tr>"
            
            # Sort with nodes having valid Last Heard first, then N/A entries at bottom
            index=1
            tail -n +2 "$NODES_CSV" 2>/dev/null | awk -F',' '{
                # Check if Last Heard field (column 16) is empty or N/A
                if ($16 == "" || $16 == "N/A") {
                    print "1," $0  # Add prefix "1" for N/A entries (sort last)
                } else {
                    print "0," $0  # Add prefix "0" for valid entries (sort first)
                }
            }' | sort -t',' -k1,1n -k17,17r | cut -d',' -f2- | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
                # Remove quotes if present
                user=$(echo "$user" | sed 's/^"//;s/"$//')
                hardware=$(echo "$hardware" | sed 's/^"//;s/"$//')
                latitude=$(echo "$latitude" | sed 's/^"//;s/"$//')
                longitude=$(echo "$longitude" | sed 's/^"//;s/"$//')
                
                # Check if GPS coordinates are valid (not empty, not 0.0, not "N/A")
                if [ -n "$latitude" ] && [ -n "$longitude" ] && \
                   [ "$latitude" != "N/A" ] && [ "$longitude" != "N/A" ] && \
                   [ "$latitude" != "0.0" ] && [ "$longitude" != "0.0" ] && \
                   [ "$latitude" != "0" ] && [ "$longitude" != "0" ]; then
                    # Create clickable link to OpenStreetMap
                    user_display="<a href=\"https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}&zoom=15\" target=\"_blank\" title=\"View ${user:-Unknown} on OpenStreetMap (${latitude}, ${longitude})\">${user:-N/A}</a>"
                else
                    user_display="${user:-N/A}"
                fi
                
                # Get CSS classes for color coding
                battery_class=$(get_value_class "$battery" "battery")
                channel_util_class=$(get_value_class "$channel_util" "channel_util")
                
                echo "<tr>"
                echo "<td class=\"number\">$index</td>"
                echo "<td>$user_display</td>"
                echo "<td class=\"address\">$id</td>"
                echo "<td>${hardware:-N/A}</td>"
                echo "<td class=\"number $battery_class\">${battery:-N/A}</td>"
                echo "<td class=\"number $channel_util_class\">${channel_util:-N/A}</td>"
                echo "<td class=\"timestamp\">${lastheard:-N/A}</td>"
                echo "</tr>"
                index=$((index + 1))
            done
            echo "</table>"
        fi
        
        # Weather-based Energy Predictions Section
        if [[ -f "weather_predictions.json" ]]; then
            echo "<h2>☀️ Weather-Based Energy Predictions</h2>"
            echo "<p><em>Solar energy predictions based on weather forecast and current battery levels</em></p>"
            echo "<table>"
            echo "<tr>"
            echo "<th>#</th>"
            echo "<th>Node</th>"
            echo "<th>Location</th>"
            echo "<th>Current Battery</th>"
            echo "<th>Weather Prediction</th>"
            echo "</tr>"
            
            # Parse JSON predictions and display
            local weather_index=1
            if command -v jq &> /dev/null; then
                jq -r '.predictions[] | "\(.node_id)|\(.user)|\(.location.latitude),\(.location.longitude)|\(.current_battery)|\(.prediction)"' weather_predictions.json 2>/dev/null | while IFS='|' read -r node_id user location current_battery prediction; do
                    echo "<tr>"
                    echo "<td>$weather_index</td>"
                    echo "<td>$(echo "$user" | sed 's/</\&lt;/g; s/>/\&gt;/g')</td>"
                    echo "<td>$location</td>"
                    echo "<td>$current_battery</td>"
                    echo "<td class=\"prediction\">$prediction</td>"
                    echo "</tr>"
                    weather_index=$((weather_index + 1))
                done
            else
                echo "<tr><td colspan=\"5\">Weather predictions require 'jq' tool. Install with: sudo apt install jq</td></tr>"
            fi
            
            echo "</table>"
            echo "<p><em>Legend: ⚡ Charging | 📉 Slow drain | 🔋 Fast drain | 📊 Stable</em></p>"
            echo "<p><em>Note: Predictions are estimates based on weather data and typical solar panel performance</em></p>"
        else
            echo "<h2>☀️ Weather-Based Energy Predictions</h2>"
            echo "<p><em>Weather predictions will appear here after the next data collection cycle</em></p>"
        fi
        
        echo "</body></html>"
    } > "$STATS_HTML"
    
    # Clean up temporary files
    rm -f /tmp/all_success.csv /tmp/last_success.csv
}

# ---- MAIN LOOP ----
while true; do
    for addr in "${ADDRESSES[@]}"; do
        # Lookup node info from nodes_log.csv every round
        node_info="$(get_node_info "$addr")"
        debug_log "Node info for $addr: $node_info"
        run_telemetry "$addr"
    done
    update_nodes_log
    parse_nodes_to_csv "$NODES_LOG" "$NODES_CSV"
    generate_stats_html
    
    # Generate weather predictions for solar nodes
    if [[ -f "weather_integration.sh" ]]; then
        echo "Generating weather-based energy predictions..."
        ./weather_integration.sh nodes_log.csv telemetry_log.csv weather_predictions.json
    fi
    
    sleep "$INTERVAL"
done
