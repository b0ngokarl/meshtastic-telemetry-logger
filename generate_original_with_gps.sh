#!/bin/bash

# Generate original stats.html with GPS map integration
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Generating original stats.html with GPS map..."

# Set up environment
export TELEMETRY_CSV="telemetry_log.csv"
export NODES_CSV="nodes_log.csv"
export DEBUG_MODE="true"

# Source the HTML generator
source ./html_generator.sh

echo "Calling generate_stats_html_original..."

# Generate the original dashboard with GPS map
generate_stats_html_original > stats.html

if [ -f "stats.html" ]; then
    echo "✅ Original dashboard generated successfully: stats.html"
    echo ""
    echo "🔍 Checking GPS map integration..."
    
    # Check if GPS map section is included
    if grep -q "Network GPS Map" stats.html; then
        echo "✅ GPS map section found!"
    else
        echo "❌ GPS map section missing"
    fi
    
    # Check if Leaflet is included
    if grep -q "leaflet" stats.html; then
        echo "✅ Leaflet library included!"
    else
        echo "❌ Leaflet library missing"
    fi
    
    # Count GPS nodes in the HTML
    GPS_COUNT=$(grep -o '"latitude": [0-9.]*' stats.html | wc -l)
    echo "✅ GPS nodes embedded: $GPS_COUNT"
    
    echo ""
    echo "📊 Features included in stats.html:"
    echo "  • Classic telemetry tables and charts"
    echo "  • Interactive GPS map with $GPS_COUNT nodes"  
    echo "  • Network topology analysis"
    echo "  • Machine learning predictions"
    echo "  • Weather forecasting"
    echo ""
    echo "🌐 TO VIEW: Open stats.html in a web browser"
    
else
    echo "❌ Failed to generate stats.html"
fi