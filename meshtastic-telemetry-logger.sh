#!/bin/bash

# ---- CONFIGURATION LOADING ----
# Load configuration from .env file if it exists
if [ -f ".env" ]; then
    source .env
    echo "Configuration loaded from .env file"
else
    echo "No .env file found, using default values"
fi

# Source common utilities and HTML generator
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"
source "$SCRIPT_DIR/html_generator.sh"

# Set default values if not defined in .env
TELEMETRY_TIMEOUT=${TELEMETRY_TIMEOUT:-300}
NODES_TIMEOUT=${NODES_TIMEOUT:-300}
WEATHER_TIMEOUT=${WEATHER_TIMEOUT:-300}
ML_TIMEOUT=${ML_TIMEOUT:-300}
POLLING_INTERVAL=${POLLING_INTERVAL:-300}
DEBUG_MODE=${DEBUG_MODE:-false}
ML_ENABLED=${ML_ENABLED:-true}

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

# Debug log function (prints only if DEBUG=1)
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        printf '[DEBUG] %s\n' "$*" >&2
    fi
}

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
    
    # Check cache first
    if [ -n "${NODE_INFO_CACHE[$node_id]}" ]; then
        echo "${NODE_INFO_CACHE[$node_id]}"
    else
        echo "$node_id"
    fi
}

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

# Function to convert seconds to hours with appropriate formatting
convert_uptime_to_hours() {
    local uptime_seconds="$1"
    
    # Return N/A if empty or not a number
    if [ -z "$uptime_seconds" ] || [ "$uptime_seconds" = "N/A" ] || ! [[ "$uptime_seconds" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "N/A"
        return
    fi
    
    # Convert seconds to different units based on magnitude
    if (( $(echo "$uptime_seconds < 60" | bc -l 2>/dev/null) )); then
        # Less than 1 minute - show seconds
        echo "${uptime_seconds}s"
    elif (( $(echo "$uptime_seconds < 3600" | bc -l 2>/dev/null) )); then
        # Less than 1 hour - show minutes
        local minutes=$(echo "scale=0; $uptime_seconds / 60" | bc -l 2>/dev/null)
        echo "${minutes}m"
    elif (( $(echo "$uptime_seconds < 86400" | bc -l 2>/dev/null) )); then
        # Less than 24 hours - show hours and minutes
        local hours=$(echo "scale=0; $uptime_seconds / 3600" | bc -l 2>/dev/null)
        local remaining_minutes=$(echo "scale=0; ($uptime_seconds % 3600) / 60" | bc -l 2>/dev/null)
        if [ "$remaining_minutes" -gt 0 ]; then
            echo "${hours}h${remaining_minutes}m"
        else
            echo "${hours}h"
        fi
    else
        # 24 hours or more - show days and hours
        local days=$(echo "scale=0; $uptime_seconds / 86400" | bc -l 2>/dev/null)
        local remaining_hours=$(echo "scale=0; ($uptime_seconds % 86400) / 3600" | bc -l 2>/dev/null)
        if [ "$remaining_hours" -gt 0 ]; then
            echo "${days}d${remaining_hours}h"
        else
            echo "${days}d"
        fi
    fi
}

# Function to format timestamps for human readability
format_human_time() {
    local timestamp="$1"
    
    if [ -z "$timestamp" ] || [ "$timestamp" = "Never" ] || [ "$timestamp" = "N/A" ]; then
        echo "$timestamp"
        return
    fi
    
    # Try to parse the timestamp and format it nicely
    local parsed_date
    if parsed_date=$(date -d "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null); then
        echo "$parsed_date"
    else
        # Fallback: just remove seconds and timezone info for shorter display
        echo "$timestamp" | sed 's/:[0-9][0-9]+[0-9:+-]*$//' | sed 's/T/ /'
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
            # Channel utilization: 25% starts queuing packets, higher values indicate network congestion
            if (( $(echo "$value >= 80" | bc -l 2>/dev/null) )); then
                echo "util-very-high"   # Very high - severe congestion
            elif (( $(echo "$value >= 50" | bc -l 2>/dev/null) )); then
                echo "util-high"        # High - significant congestion  
            elif (( $(echo "$value >= 25" | bc -l 2>/dev/null) )); then
                echo "util-medium"      # Medium - packets start queuing
            elif (( $(echo "$value >= 15" | bc -l 2>/dev/null) )); then
                echo "warning"          # Warning - elevated usage
            else
                echo "normal"           # Normal - low usage
            fi
            ;;
        "tx_util")
            # TX utilization: 10% per hour airtime limitation - node stops sending at 10%
            if (( $(echo "$value >= 10" | bc -l 2>/dev/null) )); then
                echo "util-critical"    # Critical - node stops transmitting
            elif (( $(echo "$value >= 8" | bc -l 2>/dev/null) )); then
                echo "util-very-high"   # Very high - approaching limit
            elif (( $(echo "$value >= 5" | bc -l 2>/dev/null) )); then
                echo "util-high"        # High - getting close to limit
            elif (( $(echo "$value >= 2" | bc -l 2>/dev/null) )); then
                echo "warning"          # Warning - moderate usage
            else
                echo "normal"           # Normal - low usage
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

# Get ML-enhanced power predictions for a specific node
get_ml_predictions() {
    local node_id="$1"
    local predictions_file="power_predictions.csv"
    
    # Default values if predictions not available
    local pred_6h="N/A"
    local pred_12h="N/A" 
    local pred_24h="N/A"
    local accuracy="Learning"
    
    if [ -f "$predictions_file" ]; then
        # Get latest ML prediction for this node
        local latest_prediction=$(grep ",$node_id," "$predictions_file" | tail -1)
        
        if [ -n "$latest_prediction" ]; then
            # Parse CSV: timestamp,node_id,current_battery,predicted_6h,predicted_12h,predicted_24h,weather_desc,cloud_cover,solar_efficiency
            local raw_6h=$(echo "$latest_prediction" | cut -d',' -f4)
            local raw_12h=$(echo "$latest_prediction" | cut -d',' -f5)
            local raw_24h=$(echo "$latest_prediction" | cut -d',' -f6)
            
            # Validate that predictions are numeric and not empty
            if [[ "$raw_6h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$raw_6h" ]; then
                pred_6h="$raw_6h"
            fi
            if [[ "$raw_12h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$raw_12h" ]; then
                pred_12h="$raw_12h"
            fi
            if [[ "$raw_24h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$raw_24h" ]; then
                pred_24h="$raw_24h"
            fi
            
            # Add percentage signs and determine icons based on trend only if we have valid predictions
            if [ "$pred_6h" != "N/A" ] && [ "$pred_12h" != "N/A" ] && [ "$pred_24h" != "N/A" ]; then
                local current_battery=$(echo "$latest_prediction" | cut -d',' -f3)
                local trend_6h=$(echo "scale=2; $pred_6h - $current_battery" | bc 2>/dev/null)
                local trend_12h=$(echo "scale=2; $pred_12h - $current_battery" | bc 2>/dev/null)
                local trend_24h=$(echo "scale=2; $pred_24h - $current_battery" | bc 2>/dev/null)
                
                # Add appropriate icons based on trend
                local icon_6h="🔋"
                local icon_12h="🔋"
                local icon_24h="🔋"
                
                if (( $(echo "$trend_6h > 2" | bc -l 2>/dev/null) )); then icon_6h="⚡"; fi
                if (( $(echo "$trend_6h < -5" | bc -l 2>/dev/null) )); then icon_6h="📉"; fi
                if (( $(echo "$trend_12h > 2" | bc -l 2>/dev/null) )); then icon_12h="⚡"; fi
                if (( $(echo "$trend_12h < -5" | bc -l 2>/dev/null) )); then icon_12h="📉"; fi
                if (( $(echo "$trend_24h > 2" | bc -l 2>/dev/null) )); then icon_24h="⚡"; fi
                if (( $(echo "$trend_24h < -5" | bc -l 2>/dev/null) )); then icon_24h="📉"; fi
                
                pred_6h="${pred_6h}% ${icon_6h}"
                pred_12h="${pred_12h}% ${icon_12h}"
                pred_24h="${pred_24h}% ${icon_24h}"
            fi
        fi
    fi
    
    # Get accuracy information from ML predictions
    local accuracy_file="prediction_accuracy.csv"
    if [ -f "$accuracy_file" ]; then
        local node_accuracy=$(grep ",$node_id," "$accuracy_file" | tail -5)
        if [ -n "$node_accuracy" ]; then
            # Calculate average absolute error from last 5 predictions
            accuracy=$(echo "$node_accuracy" | awk -F',' 'BEGIN{sum=0;count=0} {
                if($10!="") {
                    err = ($10 < 0 ? -$10 : $10)
                    sum += err
                    count++
                }
            } END{
                if(count>0) {
                    avg_err = sum/count
                    acc = 100 - avg_err
                    if(acc < 0) acc = 0
                    printf "%.0f%%", acc
                } else {
                    print "Learning"
                }
            }')
        fi
    fi
    
    echo "$pred_6h|$pred_12h|$pred_24h|$accuracy"
}

# Calculate trend for a value based on historical data
calculate_trend() {
    local node_id="$1"
    local field="$2"
    local current_value="$3"
    
    # Validate inputs
    if [ -z "$node_id" ] || [ -z "$field" ] || [ -z "$current_value" ] || [ "$current_value" = "N/A" ]; then
        echo "↔️"
        return
    fi
    
    # Get historical data from telemetry log (last 10 entries for this node)
    local history=$(grep ",$node_id," "$TELEMETRY_LOG" | tail -10 | head -9)
    
    if [ -z "$history" ]; then
        echo "↔️"
        return
    fi
    
    # Determine field position in CSV based on field name
    local field_pos=""
    case "$field" in
        "battery") field_pos="5" ;;
        "voltage") field_pos="6" ;;
        "channel_util") field_pos="7" ;;
        "tx_util") field_pos="8" ;;
        "snr") field_pos="9" ;;
        "rssi") field_pos="10" ;;
        *) echo "↔️"; return ;;
    esac
    
    # Get the average of the last few values
    local avg_previous=$(echo "$history" | awk -F',' -v pos="$field_pos" '
        BEGIN { sum=0; count=0 }
        { 
            if($pos != "" && $pos != "N/A" && $pos ~ /^[0-9.-]+$/) {
                sum += $pos
                count++
            }
        }
        END { 
            if(count > 0) 
                printf "%.2f", sum/count 
            else 
                print "N/A"
        }')
    
    if [ "$avg_previous" = "N/A" ] || ! [[ "$current_value" =~ ^[0-9.-]+$ ]]; then
        echo "↔️"
        return
    fi
    
    # Calculate percentage change
    local change=$(echo "scale=2; ($current_value - $avg_previous) / $avg_previous * 100" | bc 2>/dev/null)
    
    # Determine trend based on change and field type
    local abs_change=$(echo "$change" | sed 's/-//')
    local trend_icon="↔️"
    local trend_class=""
    
    # Different thresholds for different field types
    case "$field" in
        "battery"|"voltage")
            if (( $(echo "$change > 5" | bc -l 2>/dev/null) )); then
                trend_icon="📈"
                trend_class="trend-up"
            elif (( $(echo "$change < -5" | bc -l 2>/dev/null) )); then
                trend_icon="📉"
                trend_class="trend-down"
            fi
            ;;
        "channel_util"|"tx_util")
            # For utilization, down is good, up is bad
            if (( $(echo "$change > 10" | bc -l 2>/dev/null) )); then
                trend_icon="📈"
                trend_class="trend-up-bad"
            elif (( $(echo "$change < -10" | bc -l 2>/dev/null) )); then
                trend_icon="📉"
                trend_class="trend-down-good"
            fi
            ;;
        "snr"|"rssi")
            if (( $(echo "$change > 10" | bc -l 2>/dev/null) )); then
                trend_icon="📈"
                trend_class="trend-up"
            elif (( $(echo "$change < -10" | bc -l 2>/dev/null) )); then
                trend_icon="📉"
                trend_class="trend-down"
            fi
            ;;
    esac
    
    # Format the change percentage
    local change_str=""
    if (( $(echo "$abs_change > 1" | bc -l 2>/dev/null) )); then
        if (( $(echo "$change > 0" | bc -l 2>/dev/null) )); then
            change_str=" (+${change}%)"
        else
            change_str=" (${change}%)"
        fi
    fi
    
    echo "<span class='trend-indicator $trend_class' title='Trend vs recent average${change_str}'>${trend_icon}</span>"
}

# Get weather predictions for a specific node (enhanced with ML)
get_weather_predictions() {
    local node_id="$1"
    local predictions_file="weather_predictions.json"
    
    # Try ML predictions first
    local ml_result=$(get_ml_predictions "$node_id")
    local ml_6h=$(echo "$ml_result" | cut -d'|' -f1)
    local ml_12h=$(echo "$ml_result" | cut -d'|' -f2)
    local ml_24h=$(echo "$ml_result" | cut -d'|' -f3)
    local ml_accuracy=$(echo "$ml_result" | cut -d'|' -f4)
    
    # If ML predictions are available, use them; otherwise fall back to original method
    if [ "$ml_6h" != "N/A" ] && [ -n "$ml_6h" ]; then
        echo "$ml_6h|$ml_12h|$ml_24h"
        return
    fi
    
    # Original weather prediction logic as fallback
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
    local ts="$2"  # Accept timestamp as parameter to avoid multiple calls
    local out
    debug_log "Requesting telemetry for $addr at $ts"
    # Use configured connection method and timeout
    out=$(exec_meshtastic_command "$TELEMETRY_TIMEOUT" --request-telemetry --dest "$addr")
    local exit_code=$?
    debug_log "Telemetry output: $out"
    local status="unknown"
    local battery="" voltage="" channel_util="" tx_util="" uptime=""

    if [ $exit_code -eq 124 ]; then
        # timeout command returned 124 for timeout
        status="timeout"
        debug_log "Telemetry timeout (300s) for $addr"
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
        echo "$ts [$addr] ERROR: $out" >> "$ERROR_LOG"
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
        result=$(run_telemetry "$addr" "$ts")
        echo "$result" >> "$TELEMETRY_CSV"
    done
    
    debug_log "Sequential telemetry collection completed"
}

update_nodes_log() {
    local ts
    ts=$(iso8601_date)
    debug_log "Updating nodes log at $ts"
    local out
    # Use configured connection method and timeout
    out=$(exec_meshtastic_command "$NODES_TIMEOUT" --nodes)
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
    # Use the comprehensive HTML generation from html_generator.sh
    # This includes network news, ML predictions, and all advanced features
    generate_html_dashboards
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
while true; do
    echo "Starting telemetry collection cycle at $(date)"
    
    # Load/reload node info cache if nodes file has been updated (auto re-resolves names)
    load_node_info_cache
    
    # Use sequential telemetry collection (serial port limitation)
    run_telemetry_sequential
    
    # Update nodes and generate HTML
    echo "Updating node list and re-resolving node names..."
    update_nodes_log
    parse_nodes_to_csv "$NODES_LOG" "$NODES_CSV"
    
    # Reload cache after updating nodes data (ensures fresh node names)
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
    if [[ "$ML_ENABLED" = "true" && -f "ml_power_predictor.sh" ]]; then
        echo "Running ML power prediction analysis..."
        ML_MIN_DATA_POINTS="$ML_MIN_DATA_POINTS" ML_LEARNING_RATE="$ML_LEARNING_RATE" timeout $ML_TIMEOUT ./ml_power_predictor.sh run
    fi
    
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
