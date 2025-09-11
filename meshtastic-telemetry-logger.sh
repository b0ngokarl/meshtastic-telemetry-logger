#!/bin/bash

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
ADDRESSES=('!9eed0410' '!2c9e092b' '!849c4818' '!fd17c0ed' '!a0cc8008' '!ba656304' '!2df67288' '!277db5ca' '!75e98c18' '!9eed0410') # Add/change as needed
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
    {
        echo "<html><head><title>Meshtastic Telemetry Stats</title></head><body>"
    echo "<h1>Meshtastic Telemetry - Last Results (Success Only)</h1>"
    echo "<table border=1><tr><th>Timestamp</th><th>Address</th><th>Battery</th><th>Voltage</th><th>Channel Util</th><th>Tx Util</th><th>Uptime</th></tr>"
        # Show only the latest success for each address, sorted by timestamp descending
        awk -F',' '$3=="success" {a[$2]=$0} END {for (i in a) print a[i]}' "$TELEMETRY_CSV" | sort -t',' -k1,1r | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            echo "<tr><td>$timestamp</td><td>$address_display</td><td>$battery</td><td>$voltage</td><td>$channel_util</td><td>$tx_util</td><td>$uptime</td></tr>"
        done
        echo "</table>"

    echo "<h2>Telemetry Success History</h2>"
        for addr in "${ADDRESSES[@]}"; do
            device_name="$(get_node_info "$addr")"
            if [ -n "$device_name" ] && [ "$device_name" != "$addr" ]; then
                addr_display="$addr ($device_name)"
            else
                addr_display="$addr"
            fi
            echo "<h3>$addr_display</h3>"
            echo "<table border=1><tr><th>Timestamp</th><th>Battery</th><th>Voltage</th><th>Channel Util</th><th>Tx Util</th><th>Uptime</th></tr>"
            grep "$addr,success" "$TELEMETRY_CSV" | tail -n 10 | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
                echo "<tr><td>$timestamp</td><td>$battery</td><td>$voltage</td><td>$channel_util</td><td>$tx_util</td><td>$uptime</td></tr>"
            done
            echo "</table>"
        done

    echo "<h2>Current Node List</h2>"
        echo "<table border=1><tr><th>User</th><th>ID</th><th>AKA</th><th>Hardware</th><th>Pubkey</th><th>Role</th><th>Latitude</th><th>Longitude</th><th>Altitude</th><th>Battery</th><th>Channel Util</th><th>Tx Air Util</th><th>SNR</th><th>Hops</th><th>Channel</th><th>LastHeard</th><th>Since</th></tr>"
        tail -n +2 "$NODES_CSV" | sort -t, -k16,16r | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
            echo "<tr><td>$user</td><td>$id</td><td>$aka</td><td>$hardware</td><td>$pubkey</td><td>$role</td><td>$latitude</td><td>$longitude</td><td>$altitude</td><td>$battery</td><td>$channel_util</td><td>$tx_util</td><td>$snr</td><td>$hops</td><td>$channel</td><td>$lastheard</td><td>$since</td></tr>"
        done
        echo "</table>"
        echo "</body></html>"
    } > "$STATS_HTML"
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
    sleep "$INTERVAL"
done
