#!/bin/bash

# ---- CONFIGURATION LOADING ----
# Load configuration from .env file if it exists
if [ -f ".env" ]; then
    source .env
    echo "Configuration loaded from .env file"
else
    echo "No .env file found, using default values"
fi

# Source common utilities and new optimized dashboard generator
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"
source "$SCRIPT_DIR/dashboard_optimizer.sh"
source "$SCRIPT_DIR/traceroute_collector.sh"

# Set default values if not defined in .env
TELEMETRY_TIMEOUT=${TELEMETRY_TIMEOUT:-300}
NODES_TIMEOUT=${NODES_TIMEOUT:-300}
WEATHER_TIMEOUT=${WEATHER_TIMEOUT:-300}
ML_TIMEOUT=${ML_TIMEOUT:-300}
POLLING_INTERVAL=${POLLING_INTERVAL:-300}
DEBUG_MODE=${DEBUG_MODE:-false}
ML_ENABLED=${ML_ENABLED:-true}

# Traceroute defaults
TRACEROUTE_ENABLED=${TRACEROUTE_ENABLED:-true}
TRACEROUTE_INTERVAL=${TRACEROUTE_INTERVAL:-4}
TRACEROUTE_TIMEOUT=${TRACEROUTE_TIMEOUT:-120}

# Meshtastic connection defaults
MESHTASTIC_CONNECTION_TYPE=${MESHTASTIC_CONNECTION_TYPE:-serial}
MESHTASTIC_SERIAL_PORT=${MESHTASTIC_SERIAL_PORT:-auto}
MESHTASTIC_TCP_HOST=${MESHTASTIC_TCP_HOST:-192.168.1.100}
MESHTASTIC_TCP_PORT=${MESHTASTIC_TCP_PORT:-4403}

# Convert string to boolean for DEBUG
if [ "$DEBUG_MODE" = "true" ]; then
    DEBUG=1
else
    DEBUG=0
fi

# Parse monitored nodes from comma-separated string to array
if [ -n "$MONITORED_NODES" ]; then
    # Remove quotes and split by comma, then trim whitespace
    IFS=',' read -ra TEMP_ADDRESSES <<< "$MONITORED_NODES"
    ADDRESSES=()
    for addr in "${TEMP_ADDRESSES[@]}"; do
        # Remove leading/trailing whitespace and quotes
        addr=$(echo "$addr" | sed 's/^[[:space:]]*"*//; s/"*[[:space:]]*$//')
        if [ -n "$addr" ]; then
            ADDRESSES+=("$addr")
        fi
    done
else
    # Default monitored nodes if not configured
    ADDRESSES=('!9eed0410' '!2c9e092b' '!849c4818' '!fd17c0ed' '!a0cc8008' '!ba656304' '!2df67288' '!277db5ca')
fi

# File paths with defaults
TELEMETRY_CSV=${TELEMETRY_CSV:-"telemetry_log.csv"}
NODES_LOG=${NODES_LOG:-"nodes_log.txt"}
NODES_CSV=${NODES_CSV:-"nodes_log.csv"}
STATS_HTML=${HTML_OUTPUT:-"stats.html"}
ERROR_LOG=${ERROR_LOG:-"error.log"}

# Maintain backward compatibility for INTERVAL
INTERVAL=$POLLING_INTERVAL

# ---- FUNCTIONS ----

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
        debug_log "Reloading node info cache from $NODES_CSV (file: $file_timestamp, cache: $NODE_INFO_CACHE_TIMESTAMP)"
        NODE_INFO_CACHE=()
        while IFS=, read -r user id aka hardware _; do
            # Remove quotes if present
            user=$(echo "$user" | sed 's/^"//; s/"$//')
            aka=$(echo "$aka" | sed 's/^"//; s/"$//')
            hardware=$(echo "$hardware" | sed 's/^"//; s/"$//')
            id=$(echo "$id" | sed 's/^"//; s/"$//')
            
            # Choose the best friendly name with priority:
            # 1. AKA if available and not default values
            # 2. User if available and not generic
            # 3. Fall back to node ID
            local friendly_name=""
            
            # Check AKA first (often the best short name)
            if [ -n "$aka" ] && [ "$aka" != "N/A" ] && [ "$aka" != "" ] && [ "$aka" != "$id" ] && [ "$aka" != "${id#!}" ]; then
                friendly_name="$aka"
            # Check User name (avoid generic names)
            elif [ -n "$user" ] && [ "$user" != "N/A" ] && [ "$user" != "" ] && [ "$user" != "Meshtastic ${id#!}" ] && [ "$user" != "Meshtastic ${aka}" ]; then
                friendly_name="$user"
            # Add hardware info only if it's meaningful
                if [ -n "$hardware" ] && [ "$hardware" != "N/A" ] && [ "$hardware" != "UNSET" ] && [ "$hardware" != "" ]; then
                    friendly_name="$friendly_name ($hardware)"
                fi
            else
                # Fall back to node ID
                friendly_name="$id"
            fi
            
            if [ -n "$friendly_name" ]; then
                NODE_INFO_CACHE["$id"]="$friendly_name"
                debug_log "Cached node: $id -> '$friendly_name'"
            fi
        done < "$NODES_CSV"
        NODE_INFO_CACHE_TIMESTAMP="$file_timestamp"
        debug_log "Node info cache loaded with ${#NODE_INFO_CACHE[@]} entries"
    else
        debug_log "Node info cache is up to date (file: $file_timestamp, cache: $NODE_INFO_CACHE_TIMESTAMP)"
    fi
}

# ---- INIT ----
if [ ! -f "$TELEMETRY_CSV" ]; then
    echo "timestamp,address,status,battery,voltage,channel_util,tx_util,uptime" > "$TELEMETRY_CSV"
fi

# Load initial node info cache
load_node_info_cache


# ---- FUNCTIONS ----

# Efficient CSV statistics computation
compute_telemetry_stats() {
    if [ ! -f "$TELEMETRY_CSV" ]; then
        return
    fi
    
    local temp_stats="/tmp/telemetry_stats_$$"
    
    # Single awk pass to compute all statistics we need
    awk -F',' 'NR>1 && $2 != "" {
        addr = $2
        status = $3
        timestamp = $1
        battery = $4
        voltage = $5
        
        # Count attempts and successes
        total_attempts[addr]++
        if (status == "success") {
            success_count[addr]++
            latest_success[addr] = timestamp
            if (battery != "" && battery != "N/A") {
                if (min_battery[addr] == "" || battery < min_battery[addr]) 
                    min_battery[addr] = battery
                if (max_battery[addr] == "" || battery > max_battery[addr]) 
                    max_battery[addr] = battery
                current_battery[addr] = battery
            }
            if (voltage != "" && voltage != "N/A") {
                current_voltage[addr] = voltage
            }
        }
        latest_timestamp[addr] = timestamp
    } END {
        for (addr in total_attempts) {
            success = (success_count[addr] ? success_count[addr] : 0)
            failures = total_attempts[addr] - success
            rate = (total_attempts[addr] > 0 ? (success * 100.0 / total_attempts[addr]) : 0)
            
            print addr "|" total_attempts[addr] "|" success "|" failures "|" rate "|" \
                  (latest_timestamp[addr] ? latest_timestamp[addr] : "Never") "|" \
                  (latest_success[addr] ? latest_success[addr] : "Never") "|" \
                  (current_battery[addr] ? current_battery[addr] : "N/A") "|" \
                  (current_voltage[addr] ? current_voltage[addr] : "N/A") "|" \
                  (min_battery[addr] ? min_battery[addr] : "N/A") "|" \
                  (max_battery[addr] ? max_battery[addr] : "N/A")
        }
    }' "$TELEMETRY_CSV" > "$temp_stats"
    
    echo "$temp_stats"
}

# Get ML-enhanced power predictions for a specific node
# Batch telemetry collection using JSON output for efficiency
run_telemetry_batch() {
    local ts
    ts=$(iso8601_date)
    debug_log "Starting batch telemetry collection for all nodes at $ts"

    local out
    out=$(exec_meshtastic_command "$TELEMETRY_TIMEOUT" --info --json)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        debug_log "Batch telemetry command failed with exit code $exit_code"
        echo "$ts,ERROR,batch_command_failed,0,0,0,0,0" >> "$ERROR_LOG"
        return 1
    fi

    if ! echo "$out" | jq -e . >/dev/null 2>&1; then
        debug_log "Batch telemetry output is not valid JSON."
        echo "$ts,ERROR,invalid_json_output,0,0,0,0,0" >> "$ERROR_LOG"
        return 1
    fi

    # Process each node from the JSON output
    echo "$out" | jq -c '.nodes[]' | while read -r node_json; do
        local node_id status battery voltage channel_util tx_util uptime
        node_id=$(echo "$node_json" | jq -r '.user.id')
        
        # Check if telemetry data is present
        if echo "$node_json" | jq -e '.deviceMetrics' >/dev/null; then
            status="success"
            battery=$(echo "$node_json" | jq -r '.deviceMetrics.batteryLevel // "N/A"')
            voltage=$(echo "$node_json" | jq -r '.deviceMetrics.voltage // "N/A"')
            channel_util=$(echo "$node_json" | jq -r '.deviceMetrics.channelUtilization // "N/A"')
            tx_util=$(echo "$node_json" | jq -r '.deviceMetrics.airUtilTx // "N/A"')
            uptime=$(echo "$node_json" | jq -r '.deviceMetrics.uptimeSeconds // "N/A"')
        else
            status="no_telemetry"
            battery="N/A"
            voltage="N/A"
            channel_util="N/A"
            tx_util="N/A"
            uptime="N/A"
        fi

        # Append to CSV
        echo "$ts,$node_id,$status,$battery,$voltage,$channel_util,$tx_util,$uptime" >> "$TELEMETRY_CSV"
        debug_log "Logged batch telemetry for $node_id"
    done
    
    debug_log "Batch telemetry collection completed."
}

# Sequential traceroute collection (separated from telemetry)
run_traceroute_sequential() {
    # Determine if we should run traceroutes this cycle
    if [ "$TRACEROUTE_ENABLED" != "true" ] || [ $((traceroute_cycle_counter % TRACEROUTE_INTERVAL)) -ne 0 ]; then
        return
    fi

    echo "🗺️  Running network traceroute collection (cycle $traceroute_cycle_counter)..."
    
    # Initialize routing logs if traceroutes are enabled
    if command -v init_routing_logs >/dev/null 2>&1; then
        init_routing_logs
    fi
    
    local traceroute_successful=0
    local traceroute_failed=0
    
    # Process each address sequentially
    for addr in "${ADDRESSES[@]}"; do
        echo "   Tracing route to $addr..."
        if command -v run_traceroute >/dev/null 2>&1 && run_traceroute "$addr"; then
            traceroute_successful=$((traceroute_successful + 1))
            echo "    ✅ Traceroute completed"
        else
            traceroute_failed=$((traceroute_failed + 1))
            echo "    ❌ Traceroute failed or unavailable"
        fi
        sleep 1 # Small delay between nodes
    done
    
    echo "🗺️  Traceroute collection completed: $traceroute_successful successful, $traceroute_failed failed"
}

update_nodes_from_json() {
    local ts
    ts=$(iso8601_date)
    debug_log "Updating nodes from JSON at $ts"
    
    local out
    out=$(exec_meshtastic_command "$NODES_TIMEOUT" --nodes --json)
    
    if ! echo "$out" | jq -e . >/dev/null 2>&1; then
        debug_log "Nodes output is not valid JSON."
        echo "$ts,ERROR,invalid_json_for_nodes,0,0,0,0,0" >> "$ERROR_LOG"
        return 1
    fi

    local temp_csv="/tmp/nodes_new.csv"
    
    # Write header
    echo "User,ID,AKA,Hardware,Role,Latitude,Longitude,Altitude,Battery,LastHeard,Since" > "$temp_csv"

    # Use jq to transform the JSON array directly into CSV rows
    echo "$out" | jq -r '
        .[] | 
        [
            .user.longName,
            .user.id,
            .user.shortName,
            .user.hwModel,
            .role,
            (.position.latitude // "N/A"),
            (.position.longitude // "N/A"),
            (.position.altitude // "N/A"),
            (.deviceMetrics.batteryLevel // "N/A"),
            (.lastHeard | tostring // "N/A"),
            (.lastHeard | tostring | strftime("%Y-%m-%d %H:%M:%S") // "N/A")
        ] | @csv' >> "$temp_csv"

    # Merge new data with existing, keeping the latest entry for each node ID
    local temp_merged="/tmp/nodes_merged.csv"
    {
        head -n 1 "$NODES_CSV" 2>/dev/null || echo "User,ID,AKA,Hardware,Role,Latitude,Longitude,Altitude,Battery,LastHeard,Since"
        tail -n +2 "$NODES_CSV" 2>/dev/null
        tail -n +2 "$temp_csv"
    } | awk -F, '!seen[$2]++' > "$temp_merged"

    mv "$temp_merged" "$NODES_CSV"
    rm -f "$temp_csv"
    
    debug_log "Nodes CSV updated successfully from JSON."
}


generate_stats_html() {
    # Use the new performance-optimized dashboard generator
    debug_log "Switching to optimized dashboard generation"
    generate_dashboard_optimized "modern"
}

# ---- WEB DEPLOYMENT FUNCTION ----
deploy_to_web() {
    # Check if web deployment is enabled
    if [ "$WEB_DEPLOY_ENABLED" != "true" ]; then
        return 0
    fi
    
    # Check if target directory is configured
    if [ -z "$WEB_DEPLOY_PATH" ]; then
        echo "  Warning: WEB_DEPLOY_PATH not configured in .env file"
        return 1
    fi
    
    echo "  🌐 Deploying to web server: $WEB_DEPLOY_PATH"
    
    # Create target directory if it doesn't exist
    if ! sudo mkdir -p "$WEB_DEPLOY_PATH" 2>/dev/null; then
        echo "  ❌ Failed to create web deployment directory: $WEB_DEPLOY_PATH"
        return 1
    fi
    
    # Copy main HTML file as index.html
    if [ -f "$HTML_OUTPUT" ]; then
        if sudo cp "$HTML_OUTPUT" "$WEB_DEPLOY_PATH/index.html" 2>/dev/null; then
            echo "    ✅ Copied $HTML_OUTPUT → $WEB_DEPLOY_PATH/index.html"
        else
            echo "    ❌ Failed to copy $HTML_OUTPUT"
            return 1
        fi
    fi
    
    # Copy all PNG chart files
    local png_count=0
    for png_file in *.png; do
        if [ -f "$png_file" ]; then
            if sudo cp "$png_file" "$WEB_DEPLOY_PATH/" 2>/dev/null; then
                echo "    📊 Copied $png_file"
                png_count=$((png_count + 1))
            else
                echo "    ❌ Failed to copy $png_file"
            fi
        fi
    done
    
    # Copy all SVG chart files
    local svg_count=0
    for svg_file in *.svg; do
        if [ -f "$svg_file" ]; then
            if sudo cp "$svg_file" "$WEB_DEPLOY_PATH/" 2>/dev/null; then
                echo "    🖼️ Copied $svg_file"
                svg_count=$((svg_count + 1))
            else
                echo "    ❌ Failed to copy $svg_file"
            fi
        fi
    done
    
    # Set proper permissions for web server
    if [ -n "$WEB_DEPLOY_OWNER" ]; then
        if sudo chown -R "$WEB_DEPLOY_OWNER:$WEB_DEPLOY_OWNER" "$WEB_DEPLOY_PATH" 2>/dev/null; then
            echo "    🔧 Set ownership to $WEB_DEPLOY_OWNER"
        else
            echo "    ⚠️ Warning: Failed to set ownership to $WEB_DEPLOY_OWNER"
        fi
    fi
    
    if sudo chmod -R 644 "$WEB_DEPLOY_PATH"/* 2>/dev/null; then
        echo "    🔧 Set file permissions to 644"
    else
        echo "    ⚠️ Warning: Failed to set file permissions"
    fi
    
    echo "  ✅ Web deployment complete: $png_count PNG, $svg_count SVG files + HTML"
    return 0
}

# ---- MAIN LOOP ----
# Initialize cycle counter for traceroute interval
traceroute_cycle_counter=0

while true; do
    echo "Starting telemetry collection cycle at $(date)"
    
    # Increment cycle counter
    traceroute_cycle_counter=$((traceroute_cycle_counter + 1))
    
    # Load/reload node info cache if nodes file has been updated
    load_node_info_cache
    
    # Use batch telemetry collection for speed and efficiency
    run_telemetry_batch
    
    # Run traceroutes sequentially after telemetry
    run_traceroute_sequential
    
    # Update nodes using the more reliable JSON method
    echo "Updating node list from JSON..."
    update_nodes_from_json
    
    # Reload cache after updating nodes data
    echo "Refreshing node name cache..."
    load_node_info_cache
    
    generate_stats_html
    
    # Deploy to web server if configured
    deploy_to_web
    
    # Generate weather predictions for solar nodes
    if [[ -f "weather_integration.sh" ]]; then
        echo "Generating weather-based energy predictions..."
        WEATHER_API_KEY="$WEATHER_API_KEY" DEFAULT_LATITUDE="$DEFAULT_LATITUDE" DEFAULT_LONGITUDE="$DEFAULT_LONGITUDE" timeout $WEATHER_TIMEOUT ./weather_integration.sh nodes_log.csv telemetry_log.csv weather_predictions.json
    fi
    
    # Run ML power predictor to learn and improve predictions
    # This feature is currently disabled after cleanup. Re-enable if needed.
    # if [[ "$ML_ENABLED" = "true" && -f "ml_power_predictor.sh" ]]; then
    #     echo "Running ML power prediction analysis..."
    #     ML_MIN_DATA_POINTS="$ML_MIN_DATA_POINTS" ML_LEARNING_RATE="$ML_LEARNING_RATE" timeout $ML_TIMEOUT ./ml_power_predictor.sh run
    # fi
    
    # AUTO-GENERATE CHARTS AND HTML AFTER EACH TELEMETRY COLLECTION
    echo "Auto-generating telemetry charts..."
    
    # Generate comprehensive telemetry chart (PNG)
    if [[ -f "generate_full_telemetry_chart.py" ]]; then
        echo "  -> Generating multi-node telemetry chart..."
        python3 generate_full_telemetry_chart.py 2>/dev/null || echo "  Warning: Failed to generate telemetry chart"
    fi
    
    # Generate utilization chart (PNG)
    if [[ -f "generate_node_chart.py" ]]; then
        echo "  -> Generating multi-node utilization chart..."
        python3 generate_node_chart.py 2>/dev/null || echo "  Warning: Failed to generate utilization chart"
    fi
    
    # Re-generate HTML dashboard with latest data
    echo "  -> Updating HTML dashboard..."
    generate_stats_html
    
    # Embed charts in HTML dashboard
    echo "  -> Embedding charts in HTML dashboard..."
    if [[ -f "auto_chart_embedder.py" ]]; then
        python3 auto_chart_embedder.py 2>/dev/null || echo "  Warning: Failed to embed charts in HTML"
    fi
    
    # Generate and embed network news
    echo "  -> Generating network activity news..."
    if [[ -f "network_news_analyzer.py" ]]; then
        python3 network_news_analyzer.py 2>/dev/null || echo "  Warning: Failed to generate network news"
        if [[ -f "network_news_embedder.py" && -f "network_news.html" ]]; then
            python3 network_news_embedder.py 2>/dev/null || echo "  Warning: Failed to embed network news"
        fi
    fi
    
    # Deploy to web server if configured
    deploy_to_web
    
    echo "Auto-generation complete. Charts and HTML updated."
    
    sleep "$INTERVAL"
done
