#!/bin/bash

# Simplified Configuration Manager for Meshtastic Telemetry Logger
# This script provides a simple way to configure the telemetry logger

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Default configuration values
DEFAULT_CONFIG=(
    "# Meshtastic Telemetry Logger Configuration"
    ""
    "# Meshtastic Connection Configuration"
    "# Choose ONE connection method by setting the appropriate variables"
    "MESHTASTIC_CONNECTION_TYPE=serial  # Options: serial, tcp, ble"
    ""
    "# Serial Connection (default)"
    "MESHTASTIC_SERIAL_PORT=auto        # auto = auto-detect, or specific port like /dev/ttyUSB0"
    ""
    "# TCP Connection (for WiFi/Ethernet connected devices)"
    "MESHTASTIC_TCP_HOST=192.168.1.100  # IP address of your Meshtastic device"
    "MESHTASTIC_TCP_PORT=4403           # Port (default: 4403)"
    ""
    "# Bluetooth Low Energy (BLE) Connection"
    "MESHTASTIC_BLE_ADDRESS=12:34:56:78:9A:BC  # MAC address of your Meshtastic device"
    ""
    "# Basic Settings"
    "POLLING_INTERVAL=300          # Time between collection cycles (seconds)"
    "DEBUG_MODE=false              # Enable debug output (true/false)"
    ""
    "# Timeouts (seconds) - increase if you have slow network"
    "TELEMETRY_TIMEOUT=120         # Timeout for individual telemetry requests"
    "NODES_TIMEOUT=60              # Timeout for node discovery"
    "WEATHER_TIMEOUT=30            # Timeout for weather API calls"
    "ML_TIMEOUT=60                 # Timeout for ML processing"
    ""
    "# Node Monitoring - Replace with your actual node IDs"
    "MONITORED_NODES=\"!9eed0410,!2c9e092b,!849c4818\""
    ""
    "# Weather & Location (optional)"
    "WEATHER_API_KEY=              # OpenWeatherMap API key (leave empty for mock data)"
    "DEFAULT_LATITUDE=50.1109      # Your location latitude"
    "DEFAULT_LONGITUDE=8.6821      # Your location longitude"
    ""
    "# Machine Learning Features"
    "ML_ENABLED=true               # Enable ML power predictions"
    "ML_MIN_DATA_POINTS=5          # Minimum data points for predictions"
    ""
    "# File Paths (usually don't need to change)"
    "TELEMETRY_CSV=telemetry_log.csv"
    "NODES_CSV=nodes_log.csv"
    "HTML_OUTPUT=stats.html"
)

show_usage() {
    cat << EOF
Meshtastic Telemetry Logger Configuration Tool

Usage: $0 [command]

Commands:
    init        Create initial configuration file with defaults
    edit        Open configuration file in default editor
    show        Display current configuration
    connection  Show current Meshtastic connection configuration
    validate    Validate configuration file
    reset       Reset configuration to defaults
    help        Show this help message

Examples:
    $0 init                    # Create default .env file
    $0 edit                    # Edit configuration in your default editor
    $0 show                    # Show current settings
    $0 connection              # Show connection settings and test command
    $0 validate                # Check for configuration issues

Configuration file: $ENV_FILE
EOF
}

create_default_config() {
    echo "Creating default configuration file..."
    printf '%s\n' "${DEFAULT_CONFIG[@]}" > "$ENV_FILE"
    echo "Configuration file created: $ENV_FILE"
    echo "Please edit the MONITORED_NODES setting with your actual node IDs."
}

show_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "Configuration file not found: $ENV_FILE"
        echo "Run '$0 init' to create a default configuration."
        return 1
    fi
    
    source "$ENV_FILE"
    
    echo "Current Configuration Summary"
    echo "============================="
    echo
    
    echo "📡 CONNECTION SETTINGS:"
    echo "  Device Port: ${DEVICE_PORT:-/dev/ttyUSB0}"
    echo "  Monitored Nodes: ${MONITORED_NODES:-all}"
    echo "  Connection Timeout: ${CONNECTION_TIMEOUT:-30}s"
    echo "  Max Retries: ${MAX_RETRIES:-3}"
    echo "  Polling Interval: ${POLLING_INTERVAL:-60}s"
    echo
    
    echo "📊 CHART SETTINGS:"
    echo "  Chart Width: ${CHART_FIGSIZE_WIDTH:-16}"
    echo "  Chart Height: ${CHART_FIGSIZE_HEIGHT:-12}"
    echo "  Chart DPI: ${CHART_DPI:-300}"
    echo "  Size Multiplier: ${CHART_SIZE_MULTIPLIER:-1.0}"
    echo
    
    echo "🤖 MACHINE LEARNING:"
    echo "  ML Timeout: ${ML_TIMEOUT:-120}s"
    echo "  Historical Window: ${ML_HISTORICAL_WINDOW:-50} records"
    echo "  Minimum Data Points: ${ML_MIN_DATA_POINTS:-10}"
    echo "  Learning Rate: ${ML_LEARNING_RATE:-0.01}"
    echo
    
    echo "🌤️ WEATHER INTEGRATION:"
    echo "  OpenWeather API Key: ${OPENWEATHER_API_KEY:+[Set]}${OPENWEATHER_API_KEY:-[Not Set]}"
    echo "  Cache TTL: ${WEATHER_CACHE_TTL:-3600}s"
    echo
    
    echo "📰 NETWORK NEWS:"
    echo "  News Enabled: ${NEWS_ENABLED:-true}"
    echo "  Time Window: ${NEWS_TIME_WINDOW:-24} hours"
    echo "  Max Hops: ${NEWS_MAX_HOPS:-2} (0=direct, 1=1 hop, 2=2 hops, etc.)"
    echo
    
    echo "📝 LOGGING & DATA:"
    echo "  Log Level: ${LOG_LEVEL:-INFO}"
    echo "  Log Telemetry Requests: ${LOG_TELEMETRY_REQUESTS:-false}"
    echo "  Log to File: ${LOG_TO_FILE:-true}"
    echo "  Error Log: ${ERROR_LOG:-error.log}"
    echo "  Max Telemetry Days: ${MAX_TELEMETRY_DAYS:-30}"
    echo "  Max Log Size: ${MAX_LOG_SIZE_MB:-100}MB"
    echo "  Backup Old Data: ${BACKUP_OLD_DATA:-true}"
    echo
    
    echo "📁 FILE PATHS:"
    echo "  Telemetry Log: ${TELEMETRY_LOG:-telemetry_log.csv}"
    echo "  Nodes Log: ${NODES_LOG:-nodes_log.csv}"
    echo "  Stats HTML: ${STATS_HTML:-stats.html}"
    echo "  Weather Cache: ${WEATHER_CACHE_DIR:-weather_cache}"
    echo
    
    echo "🔧 ADVANCED SETTINGS:"
    echo "  Debug Mode: ${DEBUG:-false}"
    echo "  Quiet Mode: ${QUIET:-false}"
    echo "  Auto Backup: ${AUTO_BACKUP:-true}"
    echo "  Backup Retention: ${BACKUP_RETENTION_DAYS:-7} days"
    echo
    echo "To edit configuration: $0 edit"
    echo "To see raw .env file: cat $ENV_FILE"
}

edit_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "Configuration file not found. Creating default configuration first..."
        create_default_config
    fi
    
    # Try to use the user's preferred editor
    local editor="${EDITOR:-nano}"
    
    # Check if editor is available
    if ! command -v "$editor" &> /dev/null; then
        # Fallback editors
        for fallback in nano vim vi; do
            if command -v "$fallback" &> /dev/null; then
                editor="$fallback"
                break
            fi
        done
    fi
    
    echo "Opening configuration file with $editor..."
    "$editor" "$ENV_FILE"
}

validate_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "Error: Configuration file not found at $ENV_FILE"
        echo "Run '$0 init' to create a default configuration."
        return 1
    fi
    
    # Basic validation
    local errors=0
    
    source "$ENV_FILE"
    
    # Check required variables
    if [ -z "$MONITORED_NODES" ]; then
        echo "Warning: MONITORED_NODES is not set"
        errors=$((errors + 1))
    fi
    
    if [ -z "$POLLING_INTERVAL" ]; then
        echo "Warning: POLLING_INTERVAL is not set"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        echo "Configuration validation passed"
        return 0
    else
        echo "Configuration has $errors warnings"
        return 1
    fi
}

show_connection_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "Error: Configuration file not found at $ENV_FILE"
        echo "Run '$0 init' to create a default configuration."
        return 1
    fi
    
    source "$ENV_FILE"
    source "$SCRIPT_DIR/common_utils.sh"
    
    echo "=== Meshtastic Connection Configuration ==="
    echo "Connection Type: ${MESHTASTIC_CONNECTION_TYPE:-serial}"
    echo ""
    
    case "${MESHTASTIC_CONNECTION_TYPE:-serial}" in
        serial)
            echo "Serial Configuration:"
            echo "  Port: ${MESHTASTIC_SERIAL_PORT:-auto}"
            ;;
        tcp)
            echo "TCP Configuration:"
            echo "  Host: ${MESHTASTIC_TCP_HOST:-192.168.1.100}"
            echo "  Port: ${MESHTASTIC_TCP_PORT:-4403}"
            ;;
        ble)
            echo "BLE Configuration:"
            echo "  Address: ${MESHTASTIC_BLE_ADDRESS:-not set}"
            if [ -z "$MESHTASTIC_BLE_ADDRESS" ]; then
                echo "  Warning: BLE address not configured!"
            fi
            ;;
        *)
            echo "Error: Invalid connection type"
            return 1
            ;;
    esac
    
    echo ""
    echo "Example command that will be generated:"
    local test_cmd
    if test_cmd=$(build_meshtastic_command --nodes 2>/dev/null); then
        echo "  $test_cmd"
    else
        echo "  Error: Cannot build command with current configuration"
        return 1
    fi
    
    echo ""
    echo "To change connection method, edit $ENV_FILE"
    echo "Valid connection types: serial, tcp, ble"
}

validate_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ Configuration file not found: $ENV_FILE"
        return 1
    fi
    
    echo "Validating configuration..."
    
    # Source the config file
    source "$ENV_FILE"
    
    local errors=0
    
    # Check MONITORED_NODES
    if [ -z "$MONITORED_NODES" ]; then
        echo "❌ MONITORED_NODES is not set"
        errors=$((errors + 1))
    elif [[ "$MONITORED_NODES" == *"!9eed0410"* ]] && [[ "$MONITORED_NODES" == *"!2c9e092b"* ]]; then
        echo "⚠️  You're using default node IDs. Please update MONITORED_NODES with your actual node IDs."
    else
        echo "✅ MONITORED_NODES is configured"
    fi
    
    # Check timeouts are numeric
    for timeout_var in TELEMETRY_TIMEOUT NODES_TIMEOUT WEATHER_TIMEOUT ML_TIMEOUT POLLING_INTERVAL; do
        eval "timeout_val=\${$timeout_var}"
        if [ -n "$timeout_val" ] && ! [[ "$timeout_val" =~ ^[0-9]+$ ]]; then
            echo "❌ $timeout_var must be a number (got: $timeout_val)"
            errors=$((errors + 1))
        fi
    done
    
    # Check geographic coordinates
    if [ -n "$DEFAULT_LATITUDE" ] && ! [[ "$DEFAULT_LATITUDE" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "❌ DEFAULT_LATITUDE must be a valid number"
        errors=$((errors + 1))
    fi
    
    if [ -n "$DEFAULT_LONGITUDE" ] && ! [[ "$DEFAULT_LONGITUDE" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "❌ DEFAULT_LONGITUDE must be a valid number"
        errors=$((errors + 1))
    fi
    
    # Check boolean values
    for bool_var in DEBUG_MODE ML_ENABLED; do
        eval "bool_val=\${$bool_var}"
        if [ -n "$bool_val" ] && [[ "$bool_val" != "true" ]] && [[ "$bool_val" != "false" ]]; then
            echo "❌ $bool_var must be 'true' or 'false' (got: $bool_val)"
            errors=$((errors + 1))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        echo "✅ Configuration is valid"
        return 0
    else
        echo "❌ Found $errors error(s) in configuration"
        return 1
    fi
}

reset_config() {
    echo "This will overwrite your current configuration with defaults."
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_default_config
        echo "Configuration reset to defaults."
    else
        echo "Reset cancelled."
    fi
}

# Main command handling
case "${1:-help}" in
    init)
        if [ -f "$ENV_FILE" ]; then
            echo "Configuration file already exists: $ENV_FILE"
            echo "Use '$0 reset' to overwrite with defaults."
        else
            create_default_config
        fi
        ;;
    edit)
        edit_config
        ;;
    show)
        show_config
        ;;
    connection)
        show_connection_config
        ;;
    validate)
        validate_config
        ;;
    reset)
        reset_config
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac