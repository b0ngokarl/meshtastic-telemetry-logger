#!/bin/bash

# Generate HTML with embedded charts
cd "$(dirname "$0")"

# Load configuration and functions
source common_utils.sh
source telemetry_collector.sh
load_node_info_cache
source html_generator.sh

# Generate charts first
echo "Generating charts..."
if [ -f "generate_full_telemetry_chart.py" ]; then
    python3 generate_full_telemetry_chart.py
fi

if [ -f "generate_node_chart.py" ]; then
    python3 generate_node_chart.py
fi

# Generate HTML with embedded charts
echo "Generating HTML with embedded charts..."
generate_stats_html

echo "✅ HTML with charts generated: stats.html"