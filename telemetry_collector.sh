#!/bin/bash

# Telemetry Collection Module for Meshtastic Telemetry Logger
# This module handles the core telemetry collection functionality

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"

# Global cache for node information
declare -A NODE_INFO_CACHE
NODE_INFO_CACHE_TIMESTAMP=0

# Load node information into cache
load_node_info_cache() {
    if [ ! -f "$NODES_CSV" ]; then
        return
    fi
    
    local file_timestamp
    file_timestamp=$(stat -c %Y "$NODES_CSV" 2>/dev/null || stat -f %m "$NODES_CSV" 2>/dev/null || echo 0)
    
    # Only reload if file is newer than cache
    if [ "$file_timestamp" -gt "$NODE_INFO_CACHE_TIMESTAMP" ]; then
        debug_log "Reloading node info cache from $NODES_CSV"
        NODE_INFO_CACHE=()
        while IFS=, read -r user id _ hardware _; do
            # Remove quotes if present
            user=$(echo "$user" | sed 's/^"//; s/"$//')
            hardware=$(echo "$hardware" | sed 's/^"//; s/"$//')
            id=$(echo "$id" | sed 's/^"//; s/"$//')
            
            if [ -n "$user" ] && [ -n "$hardware" ]; then
                NODE_INFO_CACHE["$id"]="$user $hardware"
            elif [ -n "$user" ]; then
                NODE_INFO_CACHE["$id"]="$user"
            fi
        done < "$NODES_CSV"
        NODE_INFO_CACHE_TIMESTAMP="$file_timestamp"
        debug_log "Node info cache loaded with ${#NODE_INFO_CACHE[@]} entries"
    fi
}

# Get node information from cache
get_node_info() {
    local node_id="$1"
    
    # Check cache first
    if [ -n "${NODE_INFO_CACHE[$node_id]}" ]; then
        echo "${NODE_INFO_CACHE[$node_id]}"
    else
        echo "$node_id"
    fi
}

# Run telemetry request for a single node
run_telemetry() {
    local addr="$1"
    local ts="$2"  # Accept timestamp as parameter to avoid multiple calls
    local out
    
    debug_log "Requesting telemetry for $addr at $ts"
    
    # Use timeout command to prevent hanging
    out=$(timeout "$TELEMETRY_TIMEOUT" meshtastic --request-telemetry --dest "$addr" 2>&1)
    local exit_code=$?
    
    debug_log "Telemetry output: $out"
    local status="unknown"
    local battery="" voltage="" channel_util="" tx_util="" uptime=""

    if [ $exit_code -eq 124 ]; then
        # timeout command returned 124 for timeout
        status="timeout"
        debug_log "Telemetry timeout for $addr"
    elif echo "$out" | grep -q "Telemetry received:"; then
        status="success"
        # Optimize parsing with single awk call instead of multiple grep/awk operations
        eval "$(echo "$out" | awk '
        /Battery level:/ { gsub(/[^0-9.]/, "", $3); print "battery=" $3 }
        /Voltage:/ { gsub(/[^0-9.]/, "", $2); print "voltage=" $2 }
        /Total channel utilization:/ { gsub(/[^0-9.]/, "", $4); print "channel_util=" $4 }
        /Transmit air utilization:/ { gsub(/[^0-9.]/, "", $4); print "tx_util=" $4 }
        /Uptime:/ { gsub(/[^0-9.]/, "", $2); print "uptime=" $2 }
        ')"
        debug_log "Telemetry success: battery=$battery, voltage=$voltage, channel_util=$channel_util, tx_util=$tx_util, uptime=$uptime"
    elif echo "$out" | grep -q "Timed out waiting for telemetry"; then
        status="timeout"
        debug_log "Telemetry timeout for $addr"
    else
        status="error"
        debug_log "Telemetry error for $addr: $out"
        log_error "[$addr] $out"
    fi

    # Return CSV line instead of directly writing to file (for parallel processing)
    echo "$ts,$addr,$status,$battery,$voltage,$channel_util,$tx_util,$uptime"
}

# Sequential telemetry collection function
run_telemetry_sequential() {
    local ts
    ts=$(iso8601_date)
    
    debug_log "Starting sequential telemetry collection for ${#ADDRESSES[@]} nodes at $ts"
    
    # Process each address sequentially (serial port can only be used by one process)
    for addr in "${ADDRESSES[@]}"; do
        if is_valid_node_id "$addr"; then
            result=$(run_telemetry "$addr" "$ts")
            echo "$result" >> "$TELEMETRY_CSV"
        else
            log_error "Invalid node ID format: $addr"
        fi
    done
    
    debug_log "Sequential telemetry collection completed"
}

# Update nodes list from meshtastic CLI
update_nodes_log() {
    local ts
    ts=$(iso8601_date)
    debug_log "Updating nodes log at $ts"
    
    local out
    # Use timeout command to give nodes request time to complete
    out=$(timeout "$NODES_TIMEOUT" meshtastic --nodes 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        log_error "Nodes list request timed out"
        return 1
    fi
    
    debug_log "Nodes output received"
    echo "===== $ts =====" >> "$NODES_LOG"
    echo "$out" >> "$NODES_LOG"
}

# Parse nodes log to CSV format
parse_nodes_to_csv() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        log_error "Input file $input_file not found"
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
        debug_log "No data rows found in $input_file"
        rm -f "$temp_data"
        return 1
    fi

    # Write CSV header (skip first column N)
    echo "User,ID,AKA,Hardware,Pubkey,Role,Latitude,Longitude,Altitude,Battery,Channel_util,Tx_air_util,SNR,Hops,Channel,LastHeard,Since" > "$temp_csv"

    # Process each data row with improved parsing
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

                print user","id","aka","hardware","pubkey","role","latitude","longitude","altitude","battery","channel_util","tx_util","snr","hops","channel","lastheard","since
            }' >> "$temp_csv"
        fi
    done < "$temp_data"

    # Merge with existing nodes_log.csv (keep only latest info for each node ID)
    local header
    header=$(head -n 1 "$temp_csv")
    echo "$header" > "$temp_merged"

    # Combine old and new data (skip headers)
    { tail -n +2 "$NODES_CSV" 2>/dev/null; tail -n +2 "$temp_csv"; } > /tmp/nodes_all.csv

    # Use awk to keep only the latest info for each node ID
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
    
    debug_log "Nodes parsed to CSV: $output_file"
}

# Initialize CSV files with headers if they don't exist
init_telemetry_files() {
    init_csv_file "$TELEMETRY_CSV" "timestamp,address,status,battery,voltage,channel_util,tx_util,uptime"
    debug_log "Telemetry CSV initialized: $TELEMETRY_CSV"
}