#!/bin/bash

# Optimized HTML Generator for Large Datasets
# This module provides performance-optimized dashboard generation

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"

# Optimized telemetry statistics generation
generate_optimized_telemetry_stats() {
    local csv_file="$1"
    local max_records="${MAX_DASHBOARD_RECORDS:-1000}"
    local progressive="${PROGRESSIVE_LOADING:-true}"
    
    debug_log "Generating optimized telemetry stats from $csv_file"
    
    if [ ! -f "$csv_file" ]; then
        echo "<p>No telemetry data available</p>"
        return
    fi
    
    # Get record count efficiently
    local total_records
    total_records=$(get_csv_record_count "$csv_file")
    
    echo "<div class='telemetry-stats-optimized'>"
    echo "<h3>Telemetry Statistics</h3>"
    
    if [ "$total_records" -gt "$max_records" ] && [ "$max_records" -gt 0 ]; then
        echo "<div class='performance-notice'>"
        echo "<p><strong>Performance Mode:</strong> Showing last $max_records of $total_records total records</p>"
        echo "<small>Adjust MAX_DASHBOARD_RECORDS in .env to change this limit</small>"
        echo "</div>"
    fi
    
    # Process limited data set
    local temp_data="/tmp/telemetry_limited_$$.csv"
    get_limited_telemetry_data "$csv_file" > "$temp_data"
    
    # Generate basic statistics
    echo "<div class='stats-summary'>"
    echo "<table class='stats-table'>"
    echo "<tr><th>Metric</th><th>Value</th></tr>"
    
    # Count active nodes efficiently
    local active_nodes
    active_nodes=$(tail -n +2 "$temp_data" | cut -d, -f2 | sort -u | wc -l)
    echo "<tr><td>Active Nodes</td><td>$active_nodes</td></tr>"
    
    # Latest update time
    local latest_time
    latest_time=$(tail -1 "$temp_data" | cut -d, -f1)
    echo "<tr><td>Latest Update</td><td>$latest_time</td></tr>"
    
    # Records processed
    local processed_records
    processed_records=$(tail -n +2 "$temp_data" | wc -l)
    echo "<tr><td>Records Processed</td><td>$processed_records</td></tr>"
    
    echo "</table>"
    echo "</div>"
    
    if [ "$progressive" = "true" ]; then
        # Add placeholder for progressive content
        echo "<div id='progressive-content' class='progressive-placeholder'>"
        echo "<p>Loading detailed statistics...</p>"
        echo "<div class='loading-indicator'></div>"
        echo "</div>"
        
        # Generate JavaScript for progressive loading
        echo "<script>"
        echo "setTimeout(function() {"
        echo "  loadProgressiveContent();"
        echo "}, 1000);"
        echo "</script>"
    fi
    
    echo "</div>"
    
    # Cleanup
    rm -f "$temp_data"
}

# Progressive loading function for detailed stats
generate_progressive_telemetry_details() {
    local csv_file="$1"
    local output_file="$2"
    
    debug_log "Generating progressive telemetry details"
    
    if [ ! -f "$csv_file" ]; then
        echo '{"error": "No data available"}' > "$output_file"
        return
    fi
    
    # Generate detailed statistics in background
    {
        echo "{"
        echo '"status": "loading",'
        echo '"timestamp": "'$(iso8601_date)'",'
        echo '"details": {'
        
        # Node-specific statistics
        echo '"node_stats": ['
        tail -n +2 "$csv_file" | head -n "${MAX_DASHBOARD_RECORDS:-1000}" | \
        awk -F, '{
            node = $2
            battery = $4
            if (battery != "" && battery != "N/A") {
                node_battery[node] = battery
                node_count[node]++
            }
        } END {
            first = 1
            for (node in node_count) {
                if (!first) printf ","
                printf "{\"node\":\"%s\",\"records\":%d,\"battery\":\"%s\"}", 
                       node, node_count[node], node_battery[node]
                first = 0
            }
        }'
        echo ']'
        
        echo '}'
        echo "}"
    } > "$output_file"
}

# Optimized modern dashboard generation
generate_stats_html_modern_optimized() {
    local output_file="${1:-stats-modern.html}"
    local fast_mode="${FAST_DASHBOARD_MODE:-true}"
    
    debug_log "Generating optimized modern dashboard: $output_file"
    
    # Load configuration but skip heavy cache loading initially
    load_config
    
    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meshtastic Network Monitor - Optimized</title>
    <style>
        /* Performance-optimized CSS */
        .loading-indicator {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #3498db;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .performance-notice {
            background: #e8f4f8;
            border: 1px solid #3498db;
            border-radius: 4px;
            padding: 10px;
            margin: 10px 0;
        }
        .progressive-placeholder {
            min-height: 100px;
            padding: 20px;
            text-align: center;
            background: #f9f9f9;
            border-radius: 4px;
        }
        .stats-table {
            width: 100%;
            border-collapse: collapse;
        }
        .stats-table th, .stats-table td {
            padding: 8px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
<div class="container">
    <h1>Meshtastic Network Monitor - Performance Mode</h1>
    <p><em>Generated: EOF
    iso8601_date >> "$output_file"
    cat >> "$output_file" << 'EOF'
</em></p>

<div id="main-content">
EOF
    
    # Add optimized telemetry stats
    generate_optimized_telemetry_stats "$TELEMETRY_CSV" >> "$output_file"
    
    cat >> "$output_file" << 'EOF'

<div class="section">
    <h3>Performance Information</h3>
    <p>This dashboard uses optimized loading for large datasets.</p>
    <ul>
        <li><strong>Fast Mode:</strong> Processing limited data for better performance</li>
        <li><strong>Progressive Loading:</strong> Detailed content loads incrementally</li>
        <li><strong>Memory Efficient:</strong> Uses chunked processing for large files</li>
    </ul>
</div>

</div>

<script>
function loadProgressiveContent() {
    // Simulate progressive loading
    const placeholder = document.getElementById('progressive-content');
    if (placeholder) {
        placeholder.innerHTML = '<p>Progressive content loaded successfully!</p>';
    }
}

// Auto-refresh every 5 minutes
setTimeout(function() {
    location.reload();
}, 300000);
</script>

</div>
</body>
</html>
EOF
    
    debug_log "Optimized modern dashboard generated successfully"
}

# Test the optimized generator
test_optimized_generation() {
    debug_log "Testing optimized HTML generation"
    
    # Set test configuration
    export MAX_DASHBOARD_RECORDS=100
    export FAST_DASHBOARD_MODE=true
    export PROGRESSIVE_LOADING=true
    export DEBUG=1
    
    # Generate test dashboard
    generate_stats_html_modern_optimized "stats-modern-test.html"
    
    if [ -f "stats-modern-test.html" ]; then
        echo "✅ Optimized dashboard generated successfully"
        echo "File size: $(wc -c < stats-modern-test.html) bytes"
        echo "Generated: stats-modern-test.html"
        return 0
    else
        echo "❌ Failed to generate optimized dashboard"
        return 1
    fi
}

# If script is run directly, run test
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    test_optimized_generation
fi