#!/bin/bash

# Quick HTML Generator for Meshtastic Telemetry Logger
# Generates stats.html from existing telemetry and nodes data
# This is a lightweight version that only regenerates the HTML dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source utility modules
source "$SCRIPT_DIR/common_utils.sh"
source "$SCRIPT_DIR/html_generator.sh"

# Load configuration
load_config

# Check if required files exist
if [ ! -f "$TELEMETRY_CSV" ]; then
    echo "Error: $TELEMETRY_CSV not found. Run the main telemetry logger first."
    exit 1
fi

echo "Generating HTML dashboard from existing data..."

# Generate the HTML file
generate_stats_html

echo "HTML dashboard generated: $STATS_HTML"
echo "Open $STATS_HTML in your web browser to view the results."