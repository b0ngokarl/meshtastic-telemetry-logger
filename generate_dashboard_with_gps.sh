#!/bin/bash

# Generate complete HTML dashboard with GPS map integration
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Generating complete Meshtastic dashboard with GPS map..."

# Set up environment
export TELEMETRY_CSV="telemetry_log.csv"
export NODES_CSV="nodes_log.csv"
export HTML_OUTPUT="stats-modern.html"
export DEBUG_MODE="true"

# Source the HTML generator
source ./html_generator.sh

echo "Calling generate_stats_html..."

# Generate the dashboard
generate_stats_html

if [ -f "$HTML_OUTPUT" ]; then
    echo "✅ Dashboard generated successfully: $HTML_OUTPUT"
    echo ""
    echo "Features included:"
    echo "  📊 Telemetry statistics and trends"
    echo "  🗺️ Interactive GPS map with 200+ nodes"
    echo "  📡 Network topology analysis"
    echo "  🤖 Machine learning predictions"
    echo "  📰 Network activity monitoring"
    echo ""
    echo "Open $HTML_OUTPUT in a web browser to view the dashboard!"
else
    echo "❌ Failed to generate dashboard"
fi