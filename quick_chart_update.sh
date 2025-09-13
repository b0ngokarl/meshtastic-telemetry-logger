#!/bin/bash

# Quick Chart Generation and HTML Update Script
# Run this script manually to generate charts and update HTML dashboard

echo "🔄 Quick Chart Generation & HTML Update"
echo "========================================"

# Generate charts
echo "📊 Generating telemetry charts..."

if [[ -f "generate_full_telemetry_chart.py" ]]; then
    echo "  -> Generating multi-node telemetry chart..."
    python3 generate_full_telemetry_chart.py && echo "     ✅ Telemetry chart generated" || echo "     ❌ Failed to generate telemetry chart"
else
    echo "  ❌ generate_full_telemetry_chart.py not found"
fi

if [[ -f "generate_node_chart.py" ]]; then
    echo "  -> Generating multi-node utilization chart..."
    python3 generate_node_chart.py && echo "     ✅ Utilization chart generated" || echo "     ❌ Failed to generate utilization chart"
else
    echo "  ❌ generate_node_chart.py not found"
fi

# Update HTML dashboard
echo ""
echo "📄 Updating HTML dashboard..."

if [[ -f "auto_chart_embedder.py" ]]; then
    echo "  -> Embedding charts in HTML..."
    python3 auto_chart_embedder.py && echo "     ✅ Charts embedded in HTML" || echo "     ❌ Failed to embed charts"
else
    echo "  ❌ auto_chart_embedder.py not found"
fi

echo ""
echo "✅ Quick chart generation and HTML update complete!"
echo "📂 View your dashboard: file://$(pwd)/stats.html"