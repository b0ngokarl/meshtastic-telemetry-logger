#!/bin/bash

# Simplified Configuration Manager for Meshtastic Telemetry Logger
# This script provides a simple way to configure the telemetry logger

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Default configuration values
DEFAULT_CONFIG=(
    "# Meshtastic Telemetry Logger Configuration"
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
    validate    Check configuration for common issues
    reset       Reset to default configuration
    help        Show this help message

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
    
    echo "Current configuration:"
    echo "====================="
    cat "$ENV_FILE"
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