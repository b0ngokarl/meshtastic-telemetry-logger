#!/bin/bash

# ---- CONFIGURATION ----
ADDRESSES=('!9eed0410' '!2df67288') # Add/change as needed
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

run_telemetry() {
    local addr="$1"
    local ts
    ts=$(iso8601_date)
    local out
    out=$(meshtastic --request-telemetry --dest "'$addr'" 2>&1)
    local status="unknown"
    local battery="" voltage="" channel_util="" tx_util="" uptime=""

    if echo "$out" | grep -q "Telemetry received:"; then
        status="success"
        battery=$(echo "$out" | grep "Battery level:" | awk -F: '{print $2}' | tr -d ' %')
        voltage=$(echo "$out" | grep "Voltage:" | awk -F: '{print $2}' | tr -d ' V')
        channel_util=$(echo "$out" | grep "Total channel utilization:" | awk -F: '{print $2}' | tr -d ' %')
        tx_util=$(echo "$out" | grep "Transmit air utilization:" | awk -F: '{print $2}' | tr -d ' %')
        uptime=$(echo "$out" | grep "Uptime:" | awk -F: '{print $2}' | tr -d ' s')
    elif echo "$out" | grep -q "Timed out waiting for telemetry"; then
        status="timeout"
    else
        status="error"
        echo "$ts [$addr] ERROR: $out" >> "$ERROR_LOG"
    fi

    echo "$ts,$addr,$status,$battery,$voltage,$channel_util,$tx_util,$uptime" >> "$TELEMETRY_CSV"
}

update_nodes_log() {
    local ts
    ts=$(iso8601_date)
    local out
    out=$(meshtastic --nodes 2>&1)
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
                # Skip first field (index 2 is actually second field due to leading │)
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
    
    # Sort by LastHeard column (column 16, 0-indexed) and write to output
    # First extract header
    head -n 1 "$temp_csv" > "$output_file"
    
    # Sort data rows by LastHeard (column 16) - newer timestamps first (reverse sort)
    tail -n +2 "$temp_csv" | sort -t, -k16,16r >> "$output_file"
    
    # Clean up temporary files
    rm -f "$temp_csv" "$temp_data"
}

generate_stats_html() {
    {
        echo "<html><head><title>Meshtastic Telemetry Stats</title></head><body>"
        echo "<h1>Meshtastic Telemetry - Last Results</h1>"
        echo "<table border=1><tr><th>Timestamp</th><th>Node</th><th>Address</th><th>Status</th><th>Battery</th><th>Voltage</th><th>Channel Util</th><th>Tx Util</th><th>Uptime</th></tr>"
        
        # Process telemetry data and add node information
        while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
            if [ "$timestamp" != "timestamp" ]; then  # Skip header
                node_info=$(get_node_info "$address")
                if [ -z "$node_info" ]; then
                    node_info="$address"
                fi
                echo "<tr><td>$timestamp</td><td>$node_info</td><td>$address</td><td>$status</td><td>$battery</td><td>$voltage</td><td>$channel_util</td><td>$tx_util</td><td>$uptime</td></tr>"
            fi
        done < <(tail -n 20 "$TELEMETRY_CSV")
        
        echo "</table>"

        # Enhanced stats with node information
        echo "<h2>Success Rate</h2><ul>"
        for addr in "${ADDRESSES[@]}"; do
            total=$(grep "$addr" "$TELEMETRY_CSV" | wc -l)
            success=$(grep "$addr" "$TELEMETRY_CSV" | grep "success" | wc -l)
            rate=0
            if [ "$total" -gt 0 ]; then rate=$((100 * success / total)); fi
            
            # Get node info for display
            node_info=$(get_node_info "$addr")
            if [ -z "$node_info" ]; then
                node_info="$addr"
            fi
            echo "<li>$node_info ($addr): $rate% ($success / $total)</li>"
        done
        echo "</ul>"

        echo "<h2>Node Log Snapshots</h2><pre>"
        tail -n 40 "$NODES_LOG"
        echo "</pre>"

        echo "</body></html>"
    } > "$STATS_HTML"
}

# ---- MAIN LOOP ----
while true; do
    for addr in "${ADDRESSES[@]}"; do
        run_telemetry "$addr"
    done
    update_nodes_log
    parse_nodes_to_csv "$NODES_LOG" "$NODES_CSV"
    generate_stats_html
    sleep "$INTERVAL"
done
