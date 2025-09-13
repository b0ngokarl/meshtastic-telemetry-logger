#!/bin/bash

# Meshtastic Telemetry Logger - Streamlined Main Script
# This is the main entry point for the telemetry collection system

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Get script directory and change to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source utility modules
source "$SCRIPT_DIR/common_utils.sh"
source "$SCRIPT_DIR/telemetry_collector.sh" 
source "$SCRIPT_DIR/html_generator.sh"

# Main function for single data collection cycle
run_collection_cycle() {
    echo "Starting telemetry collection cycle at $(iso8601_date)"
    
    # Load/reload node info cache if nodes file has been updated
    load_node_info_cache
    
    # Collect telemetry from monitored nodes
    run_telemetry_sequential
    
    # Update nodes list and parse to CSV
    update_nodes_log
    parse_nodes_to_csv "$NODES_LOG" "$NODES_CSV"
    
    # Reload cache after updating nodes data
    load_node_info_cache
    
    # Generate HTML dashboard
    generate_stats_html
    
    # Run weather predictions if available
    if [[ -f "weather_integration.sh" ]]; then
        echo "Generating weather-based energy predictions..."
        timeout "$WEATHER_TIMEOUT" ./weather_integration.sh "$NODES_CSV" "$TELEMETRY_CSV" weather_predictions.json || {
            log_error "Weather integration failed or timed out"
        }
    fi
    
    # Run ML power predictor if enabled
    if [[ "$ML_ENABLED" = "true" && -f "ml_power_predictor.sh" ]]; then
        echo "Running ML power prediction analysis..."
        timeout "$ML_TIMEOUT" ./ml_power_predictor.sh run || {
            log_error "ML power predictor failed or timed out"
        }
    fi
    
    echo "Collection cycle completed successfully"
}

# Show usage information
show_usage() {
    cat << EOF
Meshtastic Telemetry Logger - Streamlined Version

Usage: $0 [options] [command]

Commands:
    run             Run continuous telemetry collection (default)
    once            Run single collection cycle
    html            Generate HTML dashboard only
    config          Open configuration manager
    help            Show this help

Options:
    --debug         Enable debug output
    --no-ml         Disable ML features for this run
    --interval N    Override polling interval (seconds)

Configuration:
    Configuration is managed through .env file
    Run '$0 config' to set up or modify configuration

Examples:
    $0                          # Run continuous collection
    $0 once                     # Run single cycle
    $0 html                     # Generate HTML only
    $0 --debug run              # Run with debug output
    $0 --interval 600 once      # Single cycle with custom interval
EOF
}

# Parse command line arguments
COMMAND="run"
OVERRIDE_INTERVAL=""
OVERRIDE_ML=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG=1
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
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Load configuration
load_config

# Apply command line overrides
if [ -n "$OVERRIDE_INTERVAL" ]; then
    POLLING_INTERVAL="$OVERRIDE_INTERVAL"
fi
if [ -n "$OVERRIDE_ML" ]; then
    ML_ENABLED="$OVERRIDE_ML"
fi

# Parse monitored nodes from configuration
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
    echo "Warning: No monitored nodes configured. Please run '$0 config' to set up monitoring."
    ADDRESSES=()
fi

# Validate configuration
if [ ${#ADDRESSES[@]} -eq 0 ] && [ "$COMMAND" != "config" ] && [ "$COMMAND" != "help" ]; then
    echo "Error: No valid node addresses configured."
    echo "Please run '$0 config' to configure node monitoring."
    exit 1
fi

# Check dependencies
check_dependencies || exit 1

# Initialize CSV files
init_telemetry_files

# Execute the requested command
case "$COMMAND" in
    run)
        echo "Starting continuous telemetry collection..."
        echo "Monitoring ${#ADDRESSES[@]} nodes with ${POLLING_INTERVAL}s interval"
        echo "Press Ctrl+C to stop"
        
        # Trap Ctrl+C for graceful shutdown
        trap 'echo "Shutting down gracefully..."; exit 0' INT
        
        while true; do
            run_collection_cycle
            
            echo "Sleeping for ${POLLING_INTERVAL} seconds..."
            sleep "$POLLING_INTERVAL"
        done
        ;;
        
    once)
        echo "Running single collection cycle..."
        run_collection_cycle
        echo "Single cycle completed. Dashboard available at: $STATS_HTML"
        ;;
        
    html)
        echo "Generating HTML dashboard from existing data..."
        if [ ! -f "$TELEMETRY_CSV" ]; then
            echo "Error: No telemetry data found. Run collection first."
            exit 1
        fi
        load_node_info_cache
        generate_stats_html
        echo "Dashboard generated: $STATS_HTML"
        ;;
        
    config)
        exec ./config_manager.sh
        ;;
        
    help)
        show_usage
        ;;
        
    *)
        echo "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac