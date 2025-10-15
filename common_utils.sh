#!/bin/bash

# Meshtastic Telemetry Logger - Common Utility Functions
# This library contains shared functions used across multiple scripts

# Debug log function (prints only if DEBUG=1)
debug_log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf '[DEBUG] %s\n' "$*" >&2
    fi
}

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

# Validate numeric input
is_numeric() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# Validate node ID format
is_valid_node_id() {
    local node_id="$1"
    [[ "$node_id" =~ ^![\da-f]{8}$ ]]
}

# Load configuration with defaults
load_config() {
    # Load from .env if exists
    if [ -f ".env" ]; then
        source .env
    fi
    
    # Set defaults for undefined variables
    TELEMETRY_TIMEOUT=${TELEMETRY_TIMEOUT:-300}
    NODES_TIMEOUT=${NODES_TIMEOUT:-300}
    WEATHER_TIMEOUT=${WEATHER_TIMEOUT:-300}
    ML_TIMEOUT=${ML_TIMEOUT:-300}
    POLLING_INTERVAL=${POLLING_INTERVAL:-300}
    DEBUG_MODE=${DEBUG_MODE:-false}
    ML_ENABLED=${ML_ENABLED:-true}
    
    # Convert string to boolean for DEBUG
    if [ "$DEBUG_MODE" = "true" ]; then
        DEBUG=1
    else
        DEBUG=0
    fi
    
    # Set file paths with defaults
    TELEMETRY_CSV=${TELEMETRY_CSV:-"telemetry_log.csv"}
    NODES_LOG=${NODES_LOG:-"nodes_log.txt"}
    NODES_CSV=${NODES_CSV:-"nodes_log.csv"}
    STATS_HTML=${HTML_OUTPUT:-"stats.html"}
    ERROR_LOG=${ERROR_LOG:-"error.log"}
}

# Log error to error log file
log_error() {
    local message="$1"
    local timestamp=$(iso8601_date)
    echo "$timestamp ERROR: $message" >> "${ERROR_LOG:-error.log}"
}

# Check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    # Check for required commands
    for tool in jq bc curl date; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install them using your package manager."
        return 1
    fi
    
    return 0
}

# Initialize CSV file with headers if it doesn't exist
init_csv_file() {
    local file="$1"
    local headers="$2"
    
    if [ ! -f "$file" ]; then
        echo "$headers" > "$file"
    fi
}

# Build Meshtastic command with appropriate connection parameters
# Usage: build_meshtastic_command [additional_args...]
# Returns the complete meshtastic command as a string
build_meshtastic_command() {
    local connection_type="${MESHTASTIC_CONNECTION_TYPE:-serial}"
    local cmd="meshtastic"
    
    case "$connection_type" in
        serial)
            if [ "${MESHTASTIC_SERIAL_PORT:-auto}" != "auto" ]; then
                cmd="$cmd --port $MESHTASTIC_SERIAL_PORT"
            fi
            # If auto, let meshtastic auto-detect the serial port
            ;;
        tcp)
            local host="${MESHTASTIC_TCP_HOST:-192.168.1.100}"
            local port="${MESHTASTIC_TCP_PORT:-4403}"
            cmd="$cmd --host $host --port $port"
            ;;
        ble)
            local ble_address="${MESHTASTIC_BLE_ADDRESS}"
            if [ -z "$ble_address" ]; then
                echo "Error: MESHTASTIC_BLE_ADDRESS not configured for BLE connection" >&2
                return 1
            fi
            cmd="$cmd --ble $ble_address"
            ;;
        *)
            echo "Error: Invalid MESHTASTIC_CONNECTION_TYPE: $connection_type" >&2
            echo "Valid options: serial, tcp, ble" >&2
            return 1
            ;;
    esac
    
    # Add any additional arguments passed to the function
    if [ $# -gt 0 ]; then
        cmd="$cmd $*"
    fi
    
    echo "$cmd"
}

# Execute a meshtastic command and parse the output
# This function now uses a python parser to handle the table output from --nodes
exec_meshtastic_command() {
    local timeout_duration="$1"
    shift # Remove timeout from arguments
    local command_args=("$@")

    # Construct the full command, including the port if specified
    local meshtastic_cmd=("meshtastic")
    if [ -n "$MESHTASTIC_PORT" ]; then
        meshtastic_cmd+=("--port" "$MESHTASTIC_PORT")
    fi
    meshtastic_cmd+=("${command_args[@]}")
    
    debug_log "Executing command: timeout ${timeout_duration}s ${meshtastic_cmd[*]}"

    # Execute the command and pipe it to the Python parser
    local output
    if ! output=$(timeout "${timeout_duration}s" "${meshtastic_cmd[@]}" 2> >(debug_log) | python3 "$SCRIPT_DIR/nodes_parser.py" 2> >(debug_log)); then
        log_error "Failed to execute or parse meshtastic command: ${meshtastic_cmd[*]}"
        return 1
    fi

    # Check if the output is valid JSON
    if ! echo "$output" | jq . >/dev/null 2>&1; then
        log_error "Generated output is not valid JSON."
        debug_log "Invalid JSON output: $output"
        return 1
    fi
    
    echo "$output"
}

# Performance optimization utility functions

# Get limited telemetry data for dashboard processing
get_limited_telemetry_data() {
    local csv_file="$1"
    local max_records="${MAX_DASHBOARD_RECORDS:-1000}"
    local fast_mode="${FAST_DASHBOARD_MODE:-true}"
    
    if [ ! -f "$csv_file" ]; then
        return 1
    fi
    
    debug_log "Getting limited telemetry data from $csv_file (max: $max_records)"
    
    if [ "$max_records" -eq 0 ]; then
        # No limit, return all data
        cat "$csv_file"
    else
        # Return header + last N records for better performance
        head -1 "$csv_file"
        tail -n "$max_records" "$csv_file" | tail -n +2
    fi
}

# Process data in chunks for better memory usage
process_data_chunks() {
    local csv_file="$1"
    local chunk_size="${DASHBOARD_PAGINATION_SIZE:-500}"
    local callback_function="$2"
    
    if [ ! -f "$csv_file" ]; then
        return 1
    fi
    
    debug_log "Processing $csv_file in chunks of $chunk_size"
    
    local line_count
    line_count=$(wc -l < "$csv_file")
    local chunks=$((line_count / chunk_size + 1))
    
    debug_log "Total lines: $line_count, Processing in $chunks chunks"
    
    # Process header first
    head -1 "$csv_file" | "$callback_function" "header"
    
    # Process chunks
    for ((i = 1; i <= chunks; i++)); do
        local start_line=$((i * chunk_size))
        local end_line=$(((i + 1) * chunk_size - 1))
        
        debug_log "Processing chunk $i/$chunks (lines $start_line-$end_line)"
        
        sed -n "${start_line},${end_line}p" "$csv_file" | "$callback_function" "chunk_$i"
        
        # Allow interruption for large datasets
        if [ $((i % 5)) -eq 0 ]; then
            sleep 0.1  # Brief pause every 5 chunks
        fi
    done
}

# Fast CSV record count (more efficient than wc -l for large files)
get_csv_record_count() {
    local csv_file="$1"
    local fast_mode="${FAST_DASHBOARD_MODE:-true}"
    
    if [ ! -f "$csv_file" ]; then
        echo "0"
        return
    fi
    
    if [ "$fast_mode" = "true" ]; then
        # Use approximate count for speed (sample first 1000 lines)
        local sample_lines=1000
        local total_lines
        total_lines=$(wc -l < "$csv_file")
        
        if [ "$total_lines" -le "$sample_lines" ]; then
            echo "$total_lines"
        else
            # Estimate based on sample
            local estimate=$((total_lines - 1))  # Subtract header
            echo "$estimate"
        fi
    else
        # Accurate count (slower for large files)
        local count
        count=$(tail -n +2 "$csv_file" | wc -l)
        echo "$count"
    fi
}