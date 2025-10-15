#!/bin/bash

# HTML Dashboard Generator for Meshtastic Telemetry Logger
# This module generates the interactive HTML dashboard from telemetry data

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"

# We need some functions from telemetry collector for the HTML generation
# Load them if not already available
if ! type load_node_info_cache >/dev/null 2>&1; then
    source "$SCRIPT_DIR/telemetry_collector.sh"
fi

# Load configuration defaults (paths, flags) if available
# Ensures variables like NODES_CSV/TELEMETRY_CSV have sensible defaults
if type load_config >/dev/null 2>&1; then
    load_config
fi

# Load node info cache to resolve node names
load_node_info_cache

# Shared content generation functions to ensure consistency between dashboards

# Generate telemetry statistics section (shared content)
generate_telemetry_stats_content() {
    local total_records=$(count_telemetry_records)
    local online_nodes=$(count_online_nodes)
    local total_nodes=$(count_total_nodes)
    
    echo "Total Records: $total_records"
    echo "Online Nodes: $online_nodes"
    echo "Total Nodes: $total_nodes"
    
    # Generate detailed telemetry tables and statistics
    if [ -f "$TELEMETRY_CSV" ]; then
        # Recent telemetry section
        echo "<!-- Recent Telemetry Data -->"
        
        # Show recent entries (last 20)
        tail -n 20 "$TELEMETRY_CSV" | while IFS=',' read -r timestamp node_id status battery voltage channel_util air_util uptime lat lon alt sats last_heard; do
            # Skip header
            [ "$timestamp" = "timestamp" ] && continue
            
            # Format node name
            local display_name=$(get_node_display_name "$node_id")
            
            echo "Node: $display_name | Status: $status | Battery: ${battery}% | Voltage: ${voltage}V"
        done
    fi
}

# Generate network activity content (shared)
generate_network_activity_content() {
    if [ -f "network_news.html" ]; then
        # Extract just the content without HTML wrapper for reuse
        sed -n '/<h3 id=.network-news./,/<\/div>$/p' network_news.html 2>/dev/null || cat network_news.html
    else
        echo "<p>Network activity analysis not available</p>"
    fi
}

# Generate ML status content (shared)
generate_ml_status_content() {
    if [ -f "power_predictions.csv" ] && [ -f "prediction_accuracy.csv" ]; then
        # Count total predictions made
        local total_predictions=$(tail -n +2 "power_predictions.csv" 2>/dev/null | wc -l)
        
        # Count accuracy measurements
        local total_accuracy_checks=$(tail -n +2 "prediction_accuracy.csv" 2>/dev/null | wc -l)
        
        echo "<p>Total Predictions: $total_predictions</p>"
        echo "<p>Accuracy Checks: $total_accuracy_checks</p>"
        
        # Show recent predictions
        if [ "$total_predictions" -gt 0 ]; then
            echo "<h4>Recent Predictions:</h4>"
            tail -n 5 "power_predictions.csv" | while IFS=',' read -r line; do
                [ "$line" != "${line#timestamp}" ] && continue  # Skip header
                echo "<div class='prediction-entry'>$line</div>"
            done
        fi
    else
        echo "<p>Machine learning power predictor is collecting initial data. Improved predictions will be available after sufficient data is gathered.</p>"
    fi
}

# Generate monitored nodes content (shared)
generate_monitored_nodes_content() {
    if [ -f "$NODES_CSV" ]; then
        echo "<h4>Node Information:</h4>"
        tail -n +2 "$NODES_CSV" | while IFS=',' read -r NodeID ShortName LongName AKA LastHeard Since Role Position Battery Voltage Hops; do
            local display_name=$(get_node_display_name "$NodeID")
            echo "<div class='node-entry'>"
            echo "  <strong>$display_name</strong> ($NodeID)"
            echo "  <br>Role: $Role | Battery: $Battery | Last Heard: $LastHeard"
            echo "</div>"
        done
    else
        echo "<p>Node information not available</p>"
    fi
}

# Helper functions for modern dashboard
count_telemetry_records() {
    if [ -f "$TELEMETRY_CSV" ]; then
        tail -n +2 "$TELEMETRY_CSV" | wc -l
    else
        echo "0"
    fi
}

count_online_nodes() {
    if [ -f "$TELEMETRY_CSV" ]; then
        # Get unique addresses from recent successful records
        tail -100 "$TELEMETRY_CSV" | awk -F',' '$3=="success" {print $2}' | sort -u | wc -l
    else
        echo "0"
    fi
}

count_total_nodes() {
    if [ -f "$TELEMETRY_CSV" ]; then
        awk -F',' 'NR>1 {print $2}' "$TELEMETRY_CSV" | sort -u | wc -l
    else
        echo "0"
    fi
}

get_overall_success_rate() {
    if [ -f "$TELEMETRY_CSV" ]; then
        awk -F',' 'NR>1 && $2 != "" {
            total++
            if ($3 == "success") success++
        } END {
            if (total > 0) print int((success/total)*100)
            else print 0
        }' "$TELEMETRY_CSV"
    else
        echo "0"
    fi
}

# Efficient CSV statistics computation
compute_telemetry_stats() {
    if [ ! -f "$TELEMETRY_CSV" ]; then
        return
    fi
    
    local temp_stats="/tmp/telemetry_stats_$$"
    
    # Single awk pass to compute all statistics we need
    awk -F',' 'NR>1 && $2 != "" {
        addr = $2
        status = $3
        timestamp = $1
        battery = $4
        voltage = $5
        
        # Count attempts and successes
        total_attempts[addr]++
        if (status == "success") {
            success_count[addr]++
            latest_success[addr] = timestamp
            if (battery != "" && battery != "N/A") {
                if (min_battery[addr] == "" || battery < min_battery[addr]) 
                    min_battery[addr] = battery
                if (max_battery[addr] == "" || battery > max_battery[addr]) 
                    max_battery[addr] = battery
                current_battery[addr] = battery
            }
            if (voltage != "" && voltage != "N/A") {
                current_voltage[addr] = voltage
            }
        }
        latest_timestamp[addr] = timestamp
    } END {
        for (addr in total_attempts) {
            success = (success_count[addr] ? success_count[addr] : 0)
            failures = total_attempts[addr] - success
            rate = (total_attempts[addr] > 0 ? (success * 100.0 / total_attempts[addr]) : 0)
            
            print addr "|" total_attempts[addr] "|" success "|" failures "|" rate "|" \
                  (latest_success[addr] ? latest_success[addr] : "Never") "|" \
                  (latest_success[addr] ? latest_success[addr] : "Never") "|" \
                  (current_battery[addr] ? current_battery[addr] : "N/A") "|" \
                  (current_voltage[addr] ? current_voltage[addr] : "N/A") "|" \
                  (min_battery[addr] ? min_battery[addr] : "N/A") "|" \
                  (max_battery[addr] ? max_battery[addr] : "N/A")
        }
    }' "$TELEMETRY_CSV" > "$temp_stats"
    
    echo "$temp_stats"
}

# Get ML-enhanced power predictions for a specific node
get_ml_predictions() {
    local node_id="$1"
    local predictions_file="power_predictions.csv"
    
    # Default values if predictions not available
    local pred_6h="N/A"
    local pred_12h="N/A" 
    local pred_24h="N/A"
    local accuracy="Learning"
    
    if [ -f "$predictions_file" ]; then
        # Get latest ML prediction for this node
        local latest_prediction=$(grep ",$node_id," "$predictions_file" | tail -1)
        
        if [ -n "$latest_prediction" ]; then
            # Parse CSV: timestamp,node_id,current_battery,predicted_6h,predicted_12h,predicted_24h,weather_desc,cloud_cover,solar_efficiency
            local raw_6h=$(echo "$latest_prediction" | cut -d',' -f4)
            local raw_12h=$(echo "$latest_prediction" | cut -d',' -f5)
            local raw_24h=$(echo "$latest_prediction" | cut -d',' -f6)
            
            # Validate that predictions are numeric and not empty
            if [[ "$raw_6h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$raw_6h" ]; then
                pred_6h="$raw_6h"
            fi
            if [[ "$raw_12h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$raw_12h" ]; then
                pred_12h="$raw_12h"
            fi
            if [[ "$raw_24h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ -n "$raw_24h" ]; then
                pred_24h="$raw_24h"
            fi
            
            # Add percentage signs and determine icons based on trend only if we have valid predictions
            if [ "$pred_6h" != "N/A" ] && [ "$pred_12h" != "N/A" ] && [ "$pred_24h" != "N/A" ]; then
                local current_battery=$(echo "$latest_prediction" | cut -d',' -f3)
                local trend_6h=$(echo "scale=2; $pred_6h - $current_battery" | bc 2>/dev/null)
                local trend_12h=$(echo "scale=2; $pred_12h - $current_battery" | bc 2>/dev/null)
                local trend_24h=$(echo "scale=2; $pred_24h - $current_battery" | bc 2>/dev/null)
                
                # Add appropriate icons based on trend
                local icon_6h="🔋"
                local icon_12h="🔋"
                local icon_24h="🔋"
                
                if (( $(echo "$trend_6h > 2" | bc -l 2>/dev/null) )); then icon_6h="⚡"; fi
                if (( $(echo "$trend_6h < -5" | bc -l 2>/dev/null) )); then icon_6h="📉"; fi
                if (( $(echo "$trend_12h > 2" | bc -l 2>/dev/null) )); then icon_12h="⚡"; fi
                if (( $(echo "$trend_12h < -5" | bc -l 2>/dev/null) )); then icon_12h="📉"; fi
                if (( $(echo "$trend_24h > 2" | bc -l 2>/dev/null) )); then icon_24h="⚡"; fi
                if (( $(echo "$trend_24h < -5" | bc -l 2>/dev/null) )); then icon_24h="📉"; fi
                
                pred_6h="${pred_6h}% ${icon_6h}"
                pred_12h="${pred_12h}% ${icon_12h}"
                pred_24h="${pred_24h}% ${icon_24h}"
            fi
        fi
    fi
    
    # Get accuracy information from ML predictions
    local accuracy_file="prediction_accuracy.csv"
    if [ -f "$accuracy_file" ]; then
        local node_accuracy=$(grep ",$node_id," "$accuracy_file" | tail -5)
        if [ -n "$node_accuracy" ]; then
            # Calculate average absolute error from last 5 predictions
            accuracy=$(echo "$node_accuracy" | awk -F',' 'BEGIN{sum=0;count=0} {
                if($10!="") {
                    err = ($10 < 0 ? -$10 : $10)
                    sum += err
                    count++
                }
            } END{
                if(count>0) {
                    avg_err = sum/count
                    acc = 100 - avg_err
                    if(acc < 0) acc = 0
                    printf "%.0f%%", acc
                } else {
                    print "Learning"
                }
            }')
        fi
    fi
    
    echo "$pred_6h|$pred_12h|$pred_24h|$accuracy"
}

# Calculate trend for a value based on historical data
calculate_trend() {
    local node_id="$1"
    local field="$2"
    local current_value="$3"
    
    # Validate inputs
    if [ -z "$node_id" ] || [ -z "$field" ] || [ -z "$current_value" ] || [ "$current_value" = "N/A" ]; then
        echo "↔️"
        return
    fi
    
    # Get historical data from telemetry log (last 10 entries for this node)
    local history=$(grep ",$node_id," "$TELEMETRY_CSV" | tail -10 | head -9)
    
    if [ -z "$history" ]; then
        echo "↔️"
        return
    fi
    
    # Determine field position in CSV based on field name
    local field_pos=""
    case "$field" in
        "battery") field_pos="5" ;;
        "voltage") field_pos="6" ;;
        "channel_util") field_pos="7" ;;
        "tx_util") field_pos="8" ;;
        "snr") field_pos="9" ;;
        "rssi") field_pos="10" ;;
        *) echo "↔️"; return ;;
    esac
    
    # Get the average of the last few values
    local avg_previous=$(echo "$history" | awk -F',' -v pos="$field_pos" '
        BEGIN { sum=0; count=0 }
        { 
            if($pos != "" && $pos != "N/A" && $pos ~ /^[0-9.-]+$/) {
                sum += $pos
                count++
            }
        }
        END { 
            if(count > 0) 
                printf "%.2f", sum/count 
            else 
                print "N/A"
        }')
    
    if [ "$avg_previous" = "N/A" ] || ! [[ "$current_value" =~ ^[0-9.-]+$ ]]; then
        echo "↔️"
        return
    fi
    
    # Calculate percentage change
    local change=$(echo "scale=2; ($current_value - $avg_previous) / $avg_previous * 100" | bc 2>/dev/null)
    
    # Determine trend based on change and field type
    local abs_change=$(echo "$change" | sed 's/-//')
    local trend_icon="↔️"
    local trend_class=""
    
    # Different thresholds for different field types
    case "$field" in
        "battery"|"voltage")
            if (( $(echo "$change > 5" | bc -l 2>/dev/null) )); then
                trend_icon="📈"
                trend_class="trend-up"
            elif (( $(echo "$change < -5" | bc -l 2>/dev/null) )); then
                trend_icon="📉"
                trend_class="trend-down"
            fi
            ;;
        "channel_util"|"tx_util")
            # For utilization, down is good, up is bad
            if (( $(echo "$change > 10" | bc -l 2>/dev/null) )); then
                trend_icon="📈"
                trend_class="trend-up-bad"
            elif (( $(echo "$change < -10" | bc -l 2>/dev/null) )); then
                trend_icon="📉"
                trend_class="trend-down-good"
            fi
            ;;
        "snr"|"rssi")
            if (( $(echo "$change > 10" | bc -l 2>/dev/null) )); then
                trend_icon="📈"
                trend_class="trend-up"
            elif (( $(echo "$change < -10" | bc -l 2>/dev/null) )); then
                trend_icon="📉"
                trend_class="trend-down"
            fi
            ;;
    esac
    
    # Format the change percentage
    local change_str=""
    if (( $(echo "$abs_change > 1" | bc -l 2>/dev/null) )); then
        if (( $(echo "$change > 0" | bc -l 2>/dev/null) )); then
            change_str=" (+${change}%)"
        else
            change_str=" (${change}%)"
        fi
    fi
    
    echo "<span class='trend-indicator $trend_class' title='Trend vs recent average${change_str}'>${trend_icon}</span>"
}

# Get weather predictions for a specific node (enhanced with ML)
get_weather_predictions() {
    local node_id="$1"
    local predictions_file="weather_predictions.json"
    
    # Try ML predictions first
    local ml_result=$(get_ml_predictions "$node_id")
    local ml_6h=$(echo "$ml_result" | cut -d'|' -f1)
    local ml_12h=$(echo "$ml_result" | cut -d'|' -f2)
    local ml_24h=$(echo "$ml_result" | cut -d'|' -f3)
    local ml_accuracy=$(echo "$ml_result" | cut -d'|' -f4)
    
    # If ML predictions are available, use them; otherwise fall back to original method
    if [ "$ml_6h" != "N/A" ] && [ -n "$ml_6h" ]; then
        echo "$ml_6h|$ml_12h|$ml_24h"
        return
    fi
    
    # Original weather prediction logic as fallback
    local pred_6h="N/A"
    local pred_12h="N/A" 
    local pred_24h="N/A"
    
    if [ -f "$predictions_file" ]; then
        # Extract prediction for this node ID
        local prediction_text=$(jq -r --arg id "$node_id" '.predictions[] | select(.node_id == $id) | .prediction' "$predictions_file" 2>/dev/null)
        
        if [ -n "$prediction_text" ] && [ "$prediction_text" != "null" ] && [ "$prediction_text" != "Unknown battery level" ]; then
            # Parse prediction text like "+3h: 93% 🔋 (Clear, 5% clouds) | +6h: 87% 🔋 (Clear, 92% clouds) | +9h: 81% 🔋 (Clear, 66% clouds)"
            # Extract 6h prediction (which is actually +6h in the format)
            pred_6h=$(echo "$prediction_text" | sed -n 's/.*+6h: \([0-9]\+%[^|]*\).*/\1/p' | sed 's/^ *//')
            
            # For 12h and 24h, we'll extrapolate based on the trend
            local current_battery=$(jq -r --arg id "$node_id" '.predictions[] | select(.node_id == $id) | .current_battery' "$predictions_file" 2>/dev/null)
            local h6_battery=$(echo "$pred_6h" | sed 's/%.*$//')
            
            if [ -n "$current_battery" ] && [ "$current_battery" != "Unknown" ] && [ -n "$h6_battery" ] && [ "$h6_battery" != "" ]; then
                # Calculate battery change rate per hour
                local battery_change=$(echo "scale=2; ($h6_battery - ${current_battery%.*}) / 6" | bc 2>/dev/null)
                
                if [ -n "$battery_change" ]; then
                    # Project 12h and 24h assuming linear trend (simplified)
                    local h12_battery=$(echo "scale=0; ${current_battery%.*} + $battery_change * 12" | bc 2>/dev/null)
                    local h24_battery=$(echo "scale=0; ${current_battery%.*} + $battery_change * 24" | bc 2>/dev/null)
                    
                    # Clamp values between 0 and 100
                    h12_battery=$(echo "$h12_battery" | awk '{print ($1 < 0) ? 0 : ($1 > 100) ? 100 : int($1)}')
                    h24_battery=$(echo "$h24_battery" | awk '{print ($1 < 0) ? 0 : ($1 > 100) ? 100 : int($1)}')
                    
                    # Determine status icons based on battery level and trend
                    local h12_icon="🔋"
                    local h24_icon="🔋"
                    
                    if (( $(echo "$battery_change > 0.5" | bc -l 2>/dev/null) )); then
                        h12_icon="⚡"; h24_icon="⚡"  # Charging
                    elif (( $(echo "$battery_change < -1" | bc -l 2>/dev/null) )); then
                        h12_icon="📉"; h24_icon="📉"  # Fast drain
                    fi
                    
                    pred_12h="${h12_battery}% ${h12_icon}"
                    pred_24h="${h24_battery}% ${h24_icon}"
                fi
            fi
        fi
    fi
    
    echo "$pred_6h|$pred_12h|$pred_24h"
}

# Generate network topology section using Python analyzer
generate_network_topology_section() {
    if [ "$TRACEROUTE_ENABLED" != "true" ]; then
        return  # Skip if traceroute is disabled
    fi
    
    debug_log "Generating network topology section..."
    
    # Use Python import to return clean HTML without stdout noise
    if [ -f "routing_topology_analyzer.py" ]; then
        if ! python3 -c "from routing_topology_analyzer import generate_routing_topology_section; print(generate_routing_topology_section())" 2>/dev/null; then
            debug_log "Failed to generate network topology HTML via import"
            echo "<div style='background: #f8d7da; padding: 15px; border-radius: 5px; margin: 20px 0;'><h3>🗺️ Network Routing Topology</h3><p><em>Topology data not available yet.</em></p></div>"
        else
            debug_log "Network topology section generated successfully"
        fi
    else
        debug_log "routing_topology_analyzer.py not found"
        echo "<div style='background: #f8d7da; padding: 15px; border-radius: 5px; margin: 20px 0;'><h3>🗺️ Network Routing Topology</h3><p><em>Routing analyzer not available.</em></p></div>"
    fi
}

# Generate GPS map section using Python generator
generate_gps_map_section() {
    debug_log "Generating GPS map section..."
    
    # Use Python import to return clean HTML without stdout noise
    if [ -f "gps_map_generator.py" ]; then
        # Ensure NODES_CSV has a default
        local nodes_csv_path="${NODES_CSV:-nodes_log.csv}"
        if ! python3 -c "from gps_map_generator import generate_gps_map_section; print(generate_gps_map_section('${nodes_csv_path}'))" 2>/dev/null; then
            debug_log "Failed to generate GPS map HTML via import"
            echo "<div class='card'><div style='text-align: center; padding: 40px; color: #666;'><i class='fas fa-map-marker-alt' style='font-size: 48px; margin-bottom: 20px; opacity: 0.3;'></i><h3>GPS Map Unavailable</h3><p>Unable to generate GPS map section.</p></div></div>"
        else
            debug_log "GPS map section generated successfully"
        fi
    else
        debug_log "gps_map_generator.py not found"
        echo "<div class='card'><div style='text-align: center; padding: 40px; color: #666;'><i class='fas fa-map-marker-alt' style='font-size: 48px; margin-bottom: 20px; opacity: 0.3;'></i><h3>GPS Map Generator Not Found</h3><p>GPS map generator script is missing.</p></div></div>"
    fi
}



# Main HTML generation function that respects HTML_DASHBOARD_MODE configuration
generate_html_dashboards() {
    local mode="${HTML_DASHBOARD_MODE:-both}"
    
    case "$mode" in
        "old")
            debug_log "HTML Mode: Generating only original stats.html"
            generate_stats_html_original
            ;;
        "modern")
            debug_log "HTML Mode: Generating only modern stats-modern.html"
            generate_stats_html_modern
            ;;
        "both"|*)
            debug_log "HTML Mode: Generating both HTML dashboards"
            generate_stats_html_original
            generate_stats_html_modern
            ;;
    esac
}

# Generate the modern HTML dashboard
generate_stats_html_modern() {
    local output_file="stats-modern.html"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get telemetry statistics
    local total_records=$(count_telemetry_records)
    local online_nodes=$(count_online_nodes)
    local total_nodes=$(count_total_nodes)
    
    debug_log "Generating comprehensive modern HTML dashboard with all data"
    
    {
        cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>📡 Meshtastic Network Dashboard</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <!-- Leaflet CSS for GPS Maps -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" 
          integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="" />
    <!-- Leaflet JavaScript -->
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
            integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
    <style>
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #3498db;
            --success-color: #27ae60;
            --warning-color: #f39c12;
            --danger-color: #e74c3c;
            --light-bg: #ecf0f1;
            --dark-bg: #34495e;
            --card-bg: #ffffff;
            --text-primary: #2c3e50;
            --text-secondary: #7f8c8d;
            --border-radius: 12px;
            --shadow: 0 4px 20px rgba(0,0,0,0.1);
            --shadow-hover: 0 8px 30px rgba(0,0,0,0.15);
            --transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: var(--text-primary);
            line-height: 1.6;
            min-height: 100vh;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        .header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
            animation: fadeInDown 0.8s ease-out;
        }

        .header h1 {
            font-size: 3.5rem;
            font-weight: 300;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }

        .header .subtitle {
            font-size: 1.2rem;
            opacity: 0.9;
            margin-bottom: 10px;
        }

        .header .last-updated {
            font-size: 0.9rem;
            opacity: 0.7;
        }

        .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 25px;
            margin-bottom: 40px;
        }

        .card {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            box-shadow: var(--shadow);
            padding: 25px;
            transition: var(--transition);
            overflow: hidden;
            position: relative;
            animation: fadeInUp 0.6s ease-out;
        }

        .card:hover {
            transform: translateY(-8px);
            box-shadow: var(--shadow-hover);
        }

        .card-header {
            display: flex;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid var(--light-bg);
        }

        .card-header i {
            font-size: 2.5rem;
            margin-right: 15px;
            padding: 15px;
            border-radius: 50%;
            color: white;
            background: linear-gradient(45deg, var(--secondary-color), #2980b9);
        }

        .card-header h3 {
            font-size: 1.3rem;
            font-weight: 600;
            color: var(--text-primary);
        }

        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin: 15px 0;
            padding: 10px 0;
            border-bottom: 1px solid #f8f9fa;
        }

        .metric:last-child {
            border-bottom: none;
        }

        .metric-label {
            font-weight: 500;
            color: var(--text-secondary);
        }

        .metric-value {
            font-weight: 700;
            font-size: 1.1rem;
            color: var(--text-primary);
        }

        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .status-online { background: #d4edda; color: #155724; }
        .status-warning { background: #fff3cd; color: #856404; }
        .status-offline { background: #f8d7da; color: #721c24; }

        .progress-bar {
            width: 100%;
            height: 8px;
            background: var(--light-bg);
            border-radius: 4px;
            overflow: hidden;
            margin-top: 8px;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--success-color), #2ecc71);
            border-radius: 4px;
            transition: width 0.5s ease;
        }

        .chart-container {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: var(--shadow);
            animation: fadeInUp 0.8s ease-out;
        }

        .chart-container img {
            width: 100%;
            height: auto;
            border-radius: 8px;
        }

        .table-container {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: var(--shadow);
            overflow-x: auto;
            animation: fadeInUp 1s ease-out;
        }

        .modern-table {
            width: 100%;
            border-collapse: collapse;
            margin: 0;
        }

        .modern-table th {
            background: linear-gradient(135deg, var(--primary-color), var(--dark-bg));
            color: white;
            padding: 15px 12px;
            text-align: left;
            font-weight: 600;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            position: sticky;
            top: 0;
        }

        .modern-table td {
            padding: 12px;
            border-bottom: 1px solid #f8f9fa;
            vertical-align: middle;
        }

        .modern-table tr:hover {
            background: #f8f9fa;
            transition: var(--transition);
        }

        .section-title {
            color: white;
            font-size: 2rem;
            font-weight: 300;
            margin: 40px 0 20px 0;
            text-align: center;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.3);
        }

        .network-news {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: var(--shadow);
            animation: fadeInUp 0.9s ease-out;
        }

        .news-summary {
            display: flex;
            justify-content: space-around;
            margin-bottom: 20px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
        }

        .news-stat {
            text-align: center;
        }

        .news-stat-value {
            font-size: 2rem;
            font-weight: 700;
            margin-bottom: 5px;
        }

        .news-stat-label {
            font-size: 0.9rem;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .collapsible {
            cursor: pointer;
            user-select: none;
            display: flex;
            align-items: center;
            justify-content: space-between;
            transition: var(--transition);
        }

        .collapsible:hover {
            opacity: 0.8;
        }

        .collapsible-content {
            max-height: 400px;
            overflow-y: auto;
            margin-top: 20px;
        }

        @keyframes fadeInDown {
            from { opacity: 0; transform: translateY(-30px); }
            to { opacity: 1; transform: translateY(0); }
        }

        @keyframes fadeInUp {
            from { opacity: 0; transform: translateY(30px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .ml-status {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: var(--shadow);
        }

        .ml-predictions {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }

        .prediction-card {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid var(--secondary-color);
        }

        @media (max-width: 768px) {
            .header h1 { font-size: 2.5rem; }
            .dashboard-grid { grid-template-columns: 1fr; }
            .news-summary { flex-direction: column; gap: 15px; }
            .container { padding: 15px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-broadcast-tower"></i> Meshtastic Network</h1>
            <div class="subtitle">Advanced Telemetry Dashboard</div>
EOF

        echo "            <div class=\"last-updated\">Last Updated: $timestamp</div>"
        
        cat << 'EOF'
        </div>

        <!-- Key Metrics Dashboard -->
        <div class="dashboard-grid">
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-signal"></i>
                    <h3>Network Status</h3>
                </div>
EOF

        echo "                <div class=\"metric\">"
        echo "                    <span class=\"metric-label\">Online Nodes</span>"
        echo "                    <span class=\"metric-value status-badge status-online\">$online_nodes / $total_nodes</span>"
        echo "                </div>"
        echo "                <div class=\"metric\">"
        echo "                    <span class=\"metric-label\">Success Rate</span>"
        local success_rate_value=$(get_overall_success_rate)
        echo "                    <span class=\"metric-value\">${success_rate_value}%</span>"
        echo "                </div>"
        echo "                <div class=\"progress-bar\">"
        echo "                    <div class=\"progress-fill\" style=\"width: ${success_rate_value}%\"></div>"
        echo "                </div>"

        cat << 'EOF'
            </div>

            <div class="card">
                <div class="card-header">
                    <i class="fas fa-database"></i>
                    <h3>Data Collection</h3>
                </div>
EOF

        echo "                <div class=\"metric\">"
        echo "                    <span class=\"metric-label\">Total Records</span>"
        echo "                    <span class=\"metric-value\">$total_records</span>"
        echo "                </div>"

        cat << 'EOF'
                <div class="metric">
                    <span class="metric-label">Data Retention</span>
                    <span class="metric-value">30 days</span>
                </div>
            </div>

            <div class="card">
                <div class="card-header">
                    <i class="fas fa-robot"></i>
                    <h3>ML Predictions</h3>
                </div>
                <div class="metric">
                    <span class="metric-label">Status</span>
                    <span class="metric-value status-badge status-online">Active</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Accuracy</span>
                    <span class="metric-value">85%</span>
                </div>
            </div>
        </div>

        <!-- Channel & TX Utilization Charts -->
        <h2 class="section-title">📊 Channel & TX Utilization Analysis</h2>
        <div class="chart-container">
            <h3 style="margin-bottom: 20px; color: var(--text-primary);">
                <i class="fas fa-signal"></i> Focused Network Utilization (Chart Nodes)
            </h3>
EOF

        # Embed utilization chart for focused nodes only
        if [ -f "multi_node_utilization_chart.png" ]; then
            echo "            <img src=\"multi_node_utilization_chart.png\" alt=\"Utilization Chart\" style=\"max-width:100%; height:auto;\" />"
        fi

        cat << 'EOF'
        </div>

        <!-- Network Activity News -->
        <h2 class="section-title">📰 Network Activity</h2>
        <div class="network-news">
EOF

        # Include network news snippet (full header and content)
        if [ -f "network_news.html" ]; then
            # Insert the entire news HTML
            sed -n '/<h3 id=.network-news./,/<\/div>$/p' network_news.html 2>/dev/null || cat network_news.html
        else
            echo "<p>Network activity analysis not available</p>"
        fi

        cat << 'EOF'
        </div>

        <!-- Network Topology Section -->
EOF

        # Include network topology if traceroute is enabled
        generate_network_topology_section

        cat << 'EOF'

        <!-- GPS Map Section -->
        <h2 class="section-title">🗺️ Network GPS Map</h2>
EOF

        # Include GPS map section
        generate_gps_map_section

        cat << 'EOF'

        <!-- ML Status Section -->
        <h2 class="section-title">🤖 Machine Learning Status</h2>
        <div class="ml-status">
            <h3 style="margin-bottom: 20px;"><i class="fas fa-brain"></i> Power Prediction Analysis</h3>
EOF

        # Include ML status
        echo "            <div class=\"ml-predictions\">"
        if [ -f "$TELEMETRY_CSV" ]; then
            # Get recent ML predictions from the CSV
            tail -20 "$TELEMETRY_CSV" | grep -v "^Timestamp" | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
                if [ "$status" = "success" ] && [ -n "$battery" ] && [ "$battery" != "null" ]; then
                    echo "                <div class=\"prediction-card\">"
                    echo "                    <strong>$address</strong><br>"
                    echo "                    <small>Battery: ${battery}% | Updated: $(echo $timestamp | cut -d'T' -f2 | cut -d'+' -f1)</small>"
                    echo "                </div>"
                fi
            done | head -6  # Limit to 6 most recent
        fi
        echo "            </div>"

        cat << 'EOF'
        </div>

        <!-- Monitored Addresses Table -->
        <h2 class="section-title">📍 Monitored Nodes</h2>
        <div class="table-container">
            <table class="modern-table">
                <thead>
                    <tr>
                        <th>Address</th>
                        <th>Battery</th>
                        <th>Success Rate</th>
                        <th>Last Success</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
EOF

        # Generate monitored addresses table
        if [ -f "$TELEMETRY_CSV" ]; then
            # Get unique addresses and their latest data
            awk -F',' 'NR>1 && $3=="success" {
                addr=$2; 
                battery=$4; 
                timestamp=$1; 
                gsub(/["\047]/, "", addr);
                gsub(/["\047]/, "", battery);
                gsub(/["\047]/, "", timestamp);
                if (addr != "" && battery != "null" && battery != "") {
                    latest[addr] = timestamp "," battery
                }
            } END {
                for (addr in latest) {
                    split(latest[addr], data, ",");
                    printf "                    <tr>\n";
                    printf "                        <td><strong>%s</strong></td>\n", addr;
                    printf "                        <td>%s%%</td>\n", data[2];
                    printf "                        <td><span class=\"status-badge status-online\">Active</span></td>\n";
                    printf "                        <td>%s</td>\n", data[1];
                    printf "                        <td><span class=\"status-badge status-online\">Online</span></td>\n";
                    printf "                    </tr>\n";
                }
            }' "$TELEMETRY_CSV" | head -10
        fi

        cat << 'EOF'
                </tbody>
            </table>
        </div>

        <!-- Recent Telemetry Data -->
        <h2 class="section-title">📊 Recent Telemetry</h2>
        <div class="table-container">
            <h3 class="collapsible" onclick="toggleSection('recent-telemetry')">
                <span><i class="fas fa-clock"></i> Last 10 Records</span>
                <i class="fas fa-chevron-down"></i>
            </h3>
            <div id="recent-telemetry" class="collapsible-content">
                <table class="modern-table">
                    <thead>
                        <tr>
                            <th>Timestamp</th>
                            <th>Address</th>
                            <th>Battery</th>
                            <th>Voltage</th>
                            <th>Channel Util</th>
                            <th>TX Util</th>
                        </tr>
                    </thead>
                    <tbody>
EOF

        # Generate recent telemetry table
        if [ -f "$TELEMETRY_CSV" ]; then
            tail -10 "$TELEMETRY_CSV" | grep -v "^Timestamp" | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
                if [ "$status" = "success" ]; then
                    echo "                        <tr>"
                    echo "                            <td>$(echo $timestamp | cut -d'T' -f2 | cut -d'+' -f1)</td>"
                    echo "                            <td><strong>$address</strong></td>"
                    echo "                            <td>${battery}%</td>"
                    echo "                            <td>${voltage}V</td>"
                    echo "                            <td>${channel_util}%</td>"
                    echo "                            <td>${tx_util}%</td>"
                    echo "                        </tr>"
                fi
            done
        fi

        cat << 'EOF'
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Comprehensive Telemetry History by Node (same as original) -->
        <h2 class="section-title">📊 Complete Telemetry History by Node</h2>
        <div class="table-container">
            <h3 class="collapsible" onclick="toggleSection('telemetry-history')">
                <span><i class="fas fa-history"></i> Historical Data by Node</span>
                <i class="fas fa-chevron-down"></i>
            </h3>
            <div id="telemetry-history" class="collapsible-content" style="display: none;">
EOF

        # Generate comprehensive per-node telemetry history (same as original)
        if [ -f "$TELEMETRY_CSV" ]; then
            last_address=""
            awk -F',' '$3=="success"' "$TELEMETRY_CSV" | sort -t',' -k2,2 -k1,1r | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
                device_name="$(get_node_info "$address")"
                if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                    address_display="$address ($device_name)"
                else
                    address_display="$address"
                fi
                
                # Start new section for each address
                if [ "$last_address" != "$address" ]; then
                    if [ -n "$last_address" ]; then 
                        echo "                </tbody></table></div>"
                    fi
                    echo "                <h4 style=\"margin-top: 20px; color: var(--primary-color);\">$address_display</h4>"
                    echo "                <div class=\"node-history\">"
                    echo "                <table class=\"modern-table\">"
                    echo "                <thead><tr><th>Timestamp</th><th>Battery (%)</th><th>Voltage (V)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (h)</th></tr></thead>"
                    echo "                <tbody>"
                    last_address="$address"
                fi
                
                echo "                <tr>"
                echo "                    <td>$(format_human_time "$timestamp")</td>"
                echo "                    <td>${battery:-N/A}</td>"
                echo "                    <td>${voltage:-N/A}</td>"
                echo "                    <td>${channel_util:-N/A}</td>"
                echo "                    <td>${tx_util:-N/A}</td>"
                uptime_hours=$(convert_uptime_to_hours "$uptime")
                echo "                    <td>${uptime_hours:-N/A}</td>"
                echo "                </tr>"
            done
            if [ -n "$last_address" ]; then
                echo "                </tbody></table></div>"
            fi
        fi

        cat << 'EOF'
            </div>
        </div>

        <!-- All Nodes Ever Heard Section (same as original) -->
        <h2 class="section-title">📡 All Nodes Ever Heard</h2>
        <div class="table-container">
            <h3 class="collapsible" onclick="toggleSection('all-nodes-content')">
                <span><i class="fas fa-list"></i> Complete Node Registry</span>
                <i class="fas fa-chevron-down"></i>
            </h3>
            <div id="all-nodes-content" class="collapsible-content" style="display: none;">
                <p><em>Comprehensive list of all nodes that have ever been detected on the mesh network</em></p>
                <table class="modern-table">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>User</th>
                            <th>ID</th>
                            <th>Hardware</th>
                            <th>Role</th>
                            <th>GPS</th>
                            <th>First Heard</th>
                            <th>Last Heard</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
EOF

        # Generate all nodes table (same as original)
        if [ -f "$NODES_CSV" ]; then
            index=1
            tail -n +2 "$NODES_CSV" 2>/dev/null | awk -F',' '!seen[$2]++ {print}' | sort -t',' -k17,17 | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
                # Remove quotes if present
                user=$(echo "$user" | sed 's/^"//;s/"$//')
                hardware=$(echo "$hardware" | sed 's/^"//;s/"$//')
                latitude=$(echo "$latitude" | sed 's/^"//;s/"$//')
                longitude=$(echo "$longitude" | sed 's/^"//;s/"$//')
                
                # Check if GPS coordinates are valid
                gps_status="No GPS"
                if [ -n "$latitude" ] && [ -n "$longitude" ] && \
                   [ "$latitude" != "N/A" ] && [ "$longitude" != "N/A" ] && \
                   [ "$latitude" != "0.0" ] && [ "$longitude" != "0.0" ]; then
                    gps_status="📍 GPS"
                fi
                
                # Determine status based on recent activity
                node_status="Unknown"
                if [ -n "$lastheard" ]; then
                    current_time=$(date +%s)
                    last_heard_time=$(date -d "$lastheard" +%s 2>/dev/null)
                    if [ -n "$last_heard_time" ]; then
                        time_diff=$(( current_time - last_heard_time ))
                        if [ $time_diff -lt 3600 ]; then  # Less than 1 hour
                            node_status="<span class=\"status-badge status-online\">Online</span>"
                        elif [ $time_diff -lt 86400 ]; then  # Less than 24 hours
                            node_status="<span class=\"status-badge status-idle\">Recent</span>"
                        else
                            node_status="<span class=\"status-badge status-offline\">Offline</span>"
                        fi
                    fi
                fi
                
                echo "                        <tr>"
                echo "                            <td>$index</td>"
                echo "                            <td><strong>${user:-Unknown}</strong></td>"
                echo "                            <td><code>$id</code></td>"
                echo "                            <td>${hardware:-Unknown}</td>"
                echo "                            <td>${role:-Unknown}</td>"
                echo "                            <td>$gps_status</td>"
                echo "                            <td>$(format_human_time "$since")</td>"
                echo "                            <td>$(format_human_time "$lastheard")</td>"
                echo "                            <td>$node_status</td>"
                echo "                        </tr>"
                index=$((index + 1))
            done
        fi

        cat << 'EOF'
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <script>
        function toggleSection(id) {
            const element = document.getElementById(id);
            const icon = element.previousElementSibling.querySelector('.fa-chevron-down, .fa-chevron-up');
            
            if (element.style.display === 'none' || element.style.display === '') {
                element.style.display = 'block';
                icon.className = 'fas fa-chevron-up';
            } else {
                element.style.display = 'none';
                icon.className = 'fas fa-chevron-down';
            }
        }

        // Auto-refresh page every 5 minutes
        setTimeout(() => location.reload(), 300000);
        
        // Add smooth scrolling
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                document.querySelector(this.getAttribute('href')).scrollIntoView({
                    behavior: 'smooth'
                });
            });
        });
    </script>
</body>
</html>
EOF
    } > "$output_file"
    
    debug_log "✅ Comprehensive modern HTML dashboard generated: $output_file"
}

# Original HTML generation function (renamed for clarity)
generate_stats_html_original() {
    # Generate HTML stats file
    {
        # HTML Header with basic styling
        cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meshtastic Telemetry Stats</title>
    <!-- Font Awesome for icons used in GPS/sections -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <!-- Leaflet CSS for GPS Maps -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" 
          integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="" />
    <!-- Leaflet JavaScript -->
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
            integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        h2 { color: #666; margin-top: 30px; }
        h3 { color: #888; margin-top: 20px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; position: relative; cursor: pointer; }
        th:hover { background-color: #e8e8e8; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .timestamp { font-family: monospace; }
        .number { text-align: right; }
        .address { font-weight: bold; }
        
        /* Color coding for values */
        .critical { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .warning { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .high { background-color: #fff8e1; color: #f57f17; }
        .normal { color: #2e7d32; }
        .good { background-color: #e8f5e8; color: #1b5e20; font-weight: bold; }
        .unknown { color: #666; font-style: italic; }
        
        /* Specific value styling */
        .battery-critical { background-color: #ffcdd2; color: #c62828; font-weight: bold; }
        .battery-low { background-color: #ffe0b2; color: #ef6c00; }
        .battery-good { color: #2e7d32; }
        .util-high { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .util-very-high { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .voltage-low { background-color: #fff3e0; color: #ef6c00; }
        .time-critical { background-color: #ffcdd2; color: #c62828; font-weight: bold; }
        
        /* Weather prediction styling */
        .prediction { 
            font-family: monospace; 
            font-size: 0.9em; 
            background-color: #f8f9fa;
            padding: 4px;
        }
        .time-warning { background-color: #ffe0b2; color: #ef6c00; }
        
        /* Sortable table styles */
        .sort-indicator { float: right; font-size: 12px; margin-left: 5px; }
        .sort-asc::after { content: ' ▲'; color: #4caf50; }
        .sort-desc::after { content: ' ▼'; color: #f44336; }
        th.sortable { 
            background: linear-gradient(135deg, #f2f2f2, #e8e8e8); 
            transition: all 0.2s ease;
        }
        th.sortable:hover { 
            background: linear-gradient(135deg, #e8e8e8, #ddd); 
            transform: translateY(-1px);
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        /* Enhanced filter styles */
        .filter-container { 
            margin: 15px 0; 
            padding: 10px; 
            background: #f8f9fa; 
            border-radius: 5px; 
            border-left: 4px solid #007bff;
        }
        .filter-input { 
            padding: 8px 12px; 
            margin: 5px; 
            border: 1px solid #ddd; 
            border-radius: 4px; 
            font-size: 14px;
            width: 300px;
            transition: border-color 0.2s ease;
        }
        .filter-input:focus {
            outline: none;
            border-color: #007bff;
            box-shadow: 0 0 0 2px rgba(0,123,255,0.25);
        }
        .filter-label { 
            font-weight: bold; 
            margin-right: 10px; 
            color: #495057;
        }
        .clear-filters { 
            background: #dc3545; 
            color: white; 
            border: none; 
            padding: 8px 12px; 
            border-radius: 4px; 
            cursor: pointer; 
            margin-left: 10px;
            transition: background 0.2s ease;
        }
        .clear-filters:hover { 
            background: #c82333; 
            transform: translateY(-1px);
        }
        
        /* Global controls styling */
        .global-controls {
            position: fixed; 
            top: 10px; 
            right: 10px; 
            z-index: 1000; 
            background: white; 
            padding: 12px; 
            border: 1px solid #ddd; 
            border-radius: 8px; 
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            font-family: Arial, sans-serif;
        }
        .global-controls button {
            margin: 0 3px;
            font-size: 12px;
            transition: all 0.2s ease;
        }
        .global-controls button:hover {
            transform: translateY(-1px);
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        /* Table row highlighting */
        tbody tr:hover {
            background-color: #fff3cd !important;
            transition: background-color 0.2s ease;
        }
        
        /* Responsive table improvements */
        @media (max-width: 768px) {
            .filter-input { width: 200px; }
            .global-controls { position: relative; top: auto; right: auto; margin: 10px 0; }
        }
        
        /* Hide rows when filtering */
        .hidden-row { display: none !important; }
        
        /* GPS link styling */
        a { color: #1976d2; text-decoration: none; }
        a:hover { color: #0d47a1; text-decoration: underline; }
        a[title]:hover { cursor: help; }
        
        /* Smooth scrolling for navigation */
        html { scroll-behavior: smooth; }
        
        /* Navigation link hover effects */
        .nav-link { transition: transform 0.2s, box-shadow 0.2s; }
        .nav-link:hover { 
            transform: translateY(-2px); 
            box-shadow: 0 4px 8px rgba(0,0,0,0.1); 
            text-decoration: none !important; 
        }
        
        /* Trend indicator styles */
        .trend-indicator {
            font-size: 0.9em;
            margin-left: 5px;
            display: inline-block;
            vertical-align: middle;
        }
        .trend-up { color: #2e7d32; }
        .trend-down { color: #c62828; }
        .trend-up-bad { color: #c62828; } /* For utilization - up is bad */
        .trend-down-good { color: #2e7d32; } /* For utilization - down is good */
        .trend-indicator:hover {
            transform: scale(1.2);
            transition: transform 0.2s;
        }
    </style>
    <script>
        function makeSortable(tableId) {
            const table = document.getElementById(tableId);
            if (!table) return;
            
            const headers = table.querySelectorAll('th');
            
            headers.forEach((header, index) => {
                header.addEventListener('click', () => sortTable(tableId, index));
                header.classList.add('sortable');
                header.style.cursor = 'pointer';
                header.title = 'Click to sort by ' + header.textContent.trim();
                
                // Add visual indicator that column is sortable
                if (!header.querySelector('.sort-indicator')) {
                    const indicator = document.createElement('span');
                    indicator.className = 'sort-indicator';
                    indicator.textContent = '⇅';
                    header.appendChild(indicator);
                }
            });
        }
        
        function sortTable(tableId, columnIndex) {
            const table = document.getElementById(tableId);
            const tbody = table.querySelector('tbody') || table;
            const rows = Array.from(tbody.querySelectorAll('tr')).slice(1); // Skip header row
            const header = table.querySelectorAll('th')[columnIndex];
            
            // Remove existing sort indicators
            table.querySelectorAll('th').forEach(th => {
                th.classList.remove('sort-asc', 'sort-desc');
            });
            
            // Determine sort direction
            const isAscending = !header.dataset.sortDirection || header.dataset.sortDirection === 'desc';
            header.dataset.sortDirection = isAscending ? 'asc' : 'desc';
            header.classList.add(isAscending ? 'sort-asc' : 'sort-desc');
            
            // Sort rows with enhanced type detection
            rows.sort((a, b) => {
                const aCell = a.cells[columnIndex];
                const bCell = b.cells[columnIndex];
                const aText = aCell?.textContent.trim() || '';
                const bText = bCell?.textContent.trim() || '';
                
                let comparison = 0;
                
                // Handle special cases - sort N/A and unknown values to bottom
                if ((aText === 'N/A' || aText.toLowerCase() === 'unknown') && (bText === 'N/A' || bText.toLowerCase() === 'unknown')) return 0;
                if (aText === 'N/A' || aText.toLowerCase() === 'unknown') return isAscending ? 1 : -1;
                if (bText === 'N/A' || bText.toLowerCase() === 'unknown') return isAscending ? -1 : 1;
                
                // Detect column type and sort accordingly
                const columnHeader = header.textContent.toLowerCase();
                
                if (columnHeader.includes('timestamp') || columnHeader.includes('last success')) {
                    // Date/time sorting
                    const aDate = new Date(aText);
                    const bDate = new Date(bText);
                    if (!isNaN(aDate) && !isNaN(bDate)) {
                        comparison = aDate - bDate;
                    } else {
                        comparison = aText.localeCompare(bText);
                    }
                } else if (columnHeader.includes('address')) {
                    // Address sorting (handle device names vs addresses)
                    const aAddr = aText.includes('!') ? aText.split('(')[1]?.replace(')', '') || aText : aText;
                    const bAddr = bText.includes('!') ? bText.split('(')[1]?.replace(')', '') || bText : bText;
                    comparison = aAddr.localeCompare(bAddr);
                } else if (columnHeader.includes('rate') || columnHeader.includes('%')) {
                    // Percentage sorting
                    const aNum = parseFloat(aText.replace(/[%\s]/g, ''));
                    const bNum = parseFloat(bText.replace(/[%\s]/g, ''));
                    if (!isNaN(aNum) && !isNaN(bNum)) {
                        comparison = aNum - bNum;
                    } else {
                        comparison = aText.localeCompare(bText);
                    }
                } else if (columnHeader.includes('uptime')) {
                    // Uptime sorting (handle d/h/m formats)
                    const aSeconds = parseUptimeToSeconds(aText);
                    const bSeconds = parseUptimeToSeconds(bText);
                    comparison = aSeconds - bSeconds;
                } else {
                    // Try numeric first, then text
                    const aNum = parseFloat(aText.replace(/[^\d.-]/g, ''));
                    const bNum = parseFloat(bText.replace(/[^\d.-]/g, ''));
                    
                    if (!isNaN(aNum) && !isNaN(bNum)) {
                        comparison = aNum - bNum;
                    } else {
                        comparison = aText.localeCompare(bText, undefined, { numeric: true });
                    }
                }
                
                return isAscending ? comparison : -comparison;
            });
            
            // Reorder DOM
            rows.forEach(row => tbody.appendChild(row));
        }
        
        // Helper function to convert uptime formats to seconds for comparison
        function parseUptimeToSeconds(uptimeStr) {
            if (!uptimeStr || uptimeStr === 'N/A') return 0;
            
            let seconds = 0;
            const dayMatch = uptimeStr.match(/(\d+)d/);
            const hourMatch = uptimeStr.match(/(\d+(?:\.\d+)?)h/);
            const minMatch = uptimeStr.match(/(\d+)m/);
            
            if (dayMatch) seconds += parseInt(dayMatch[1]) * 24 * 3600;
            if (hourMatch) seconds += parseFloat(hourMatch[1]) * 3600;
            if (minMatch) seconds += parseInt(minMatch[1]) * 60;
            
            return seconds;
        }
        
        function addTableFilter(tableId, placeholder = 'Filter table...') {
            const table = document.getElementById(tableId);
            if (!table) return;
            
            // Create filter container
            const filterContainer = document.createElement('div');
            filterContainer.className = 'filter-container';
            
            // Create filter input
            const filterInput = document.createElement('input');
            filterInput.type = 'text';
            filterInput.className = 'filter-input';
            filterInput.placeholder = placeholder;
            filterInput.addEventListener('input', () => filterTable(tableId, filterInput.value));
            
            // Create clear button
            const clearButton = document.createElement('button');
            clearButton.className = 'clear-filters';
            clearButton.textContent = 'Clear';
            clearButton.addEventListener('click', () => {
                filterInput.value = '';
                filterTable(tableId, '');
            });
            
            filterContainer.appendChild(document.createTextNode('Filter: '));
            filterContainer.appendChild(filterInput);
            filterContainer.appendChild(clearButton);
            
            // Insert before table
            table.parentNode.insertBefore(filterContainer, table);
        }
        
        function filterTable(tableId, filterValue) {
            const table = document.getElementById(tableId);
            const tbody = table.querySelector('tbody') || table;
            const rows = tbody.querySelectorAll('tr');
            const searchTerm = filterValue.toLowerCase();
            let visibleCount = 0;
            
            rows.forEach((row, index) => {
                if (index === 0) return; // Skip header row
                
                const text = row.textContent.toLowerCase();
                if (text.includes(searchTerm)) {
                    row.classList.remove('hidden-row');
                    visibleCount++;
                    
                    // Highlight matching text
                    if (searchTerm && searchTerm.length > 1) {
                        highlightMatches(row, searchTerm);
                    } else {
                        removeHighlights(row);
                    }
                } else {
                    row.classList.add('hidden-row');
                    removeHighlights(row);
                }
            });
            
            // Update filter info
            updateFilterInfo(tableId, visibleCount, rows.length - 1);
        }
        
        function highlightMatches(row, searchTerm) {
            const walker = document.createTreeWalker(
                row,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );
            
            const textNodes = [];
            let node;
            while (node = walker.nextNode()) {
                textNodes.push(node);
            }
            
            textNodes.forEach(textNode => {
                const text = textNode.textContent;
                const lowText = text.toLowerCase();
                const index = lowText.indexOf(searchTerm);
                
                if (index !== -1) {
                    const beforeText = text.substring(0, index);
                    const matchText = text.substring(index, index + searchTerm.length);
                    const afterText = text.substring(index + searchTerm.length);
                    
                    const span = document.createElement('span');
                    span.innerHTML = beforeText + 
                        '<mark style="background: #ffeb3b; padding: 1px 2px; border-radius: 2px;">' + 
                        matchText + '</mark>' + afterText;
                    
                    textNode.parentNode.replaceChild(span, textNode);
                }
            });
        }
        
        function removeHighlights(row) {
            const highlights = row.querySelectorAll('mark');
            highlights.forEach(mark => {
                mark.outerHTML = mark.textContent;
            });
        }
        
        function updateFilterInfo(tableId, visibleCount, totalCount) {
            const filterContainer = document.querySelector(`#${tableId}`).previousElementSibling;
            let infoSpan = filterContainer.querySelector('.filter-info');
            
            if (!infoSpan) {
                infoSpan = document.createElement('span');
                infoSpan.className = 'filter-info';
                infoSpan.style.cssText = 'margin-left: 10px; font-size: 12px; color: #6c757d;';
                filterContainer.appendChild(infoSpan);
            }
            
            if (visibleCount === totalCount) {
                infoSpan.textContent = '';
            } else {
                infoSpan.textContent = `(showing ${visibleCount} of ${totalCount} rows)`;
            }
        }
        
        // Initialize sortable tables when page loads
        document.addEventListener('DOMContentLoaded', function() {
            // Add unique IDs to tables and make them sortable/filterable
            const tables = document.querySelectorAll('table');
            tables.forEach((table, index) => {
                if (!table.id) {
                    // Assign meaningful IDs based on context
                    const prevHeading = table.previousElementSibling;
                    let id = 'table-' + index;
                    
                    if (prevHeading && prevHeading.tagName && prevHeading.tagName.match(/^H[1-6]$/)) {
                        const headingText = prevHeading.textContent.toLowerCase();
                        if (headingText.includes('summary statistics')) {
                            id = 'summary-table';
                        } else if (headingText.includes('recent telemetry')) {
                            id = 'recent-table';
                        } else if (headingText.includes('monitored addresses')) {
                            id = 'monitored-table';
                        } else if (headingText.includes('current nodes')) {
                            id = 'current-nodes-table';
                        } else if (headingText.includes('all nodes')) {
                            id = 'all-nodes-table';
                        } else if (headingText.includes('ml status')) {
                            id = 'ml-status-table';
                        } else if (headingText.includes('weather')) {
                            id = 'weather-table';
                        }
                    }
                    
                    table.id = id;
                }
                makeSortable(table.id);
                
                // Add appropriate filter placeholder based on table content
                let placeholder = 'Filter table...';
                const firstHeader = table.querySelector('th')?.textContent || '';
                
                if (firstHeader.includes('Address')) {
                    placeholder = 'Filter by node address, device name, status...';
                } else if (firstHeader.includes('Timestamp')) {
                    placeholder = 'Filter by timestamp, battery, voltage...';
                } else if (firstHeader.includes('Node ID') || firstHeader.includes('Node')) {
                    placeholder = 'Filter by node ID, location, coordinates...';
                }
                
                addTableFilter(table.id, placeholder);
            });
            
            // Add keyboard shortcuts for common actions
            document.addEventListener('keydown', function(e) {
                // Ctrl+F to focus first filter input
                if (e.ctrlKey && e.key === 'f') {
                    e.preventDefault();
                    const firstFilter = document.querySelector('.filter-input');
                    if (firstFilter) firstFilter.focus();
                }
                
                // Escape to clear all filters
                if (e.key === 'Escape') {
                    const filterInputs = document.querySelectorAll('.filter-input');
                    filterInputs.forEach(input => {
                        input.value = '';
                        filterTable(input.closest('.filter-container').nextElementSibling.id, '');
                    });
                }
            });
            
            // Add a "Clear All Filters" button at the top
            const body = document.body;
            const globalControls = document.createElement('div');
            globalControls.className = 'global-controls';
            globalControls.innerHTML = `
                <button onclick="clearAllFilters()" style="background: #dc3545; color: white; border: none; padding: 8px 12px; border-radius: 4px; cursor: pointer; margin-right: 5px;">🗑️ Clear All Filters</button>
                <button onclick="resetAllSorting()" style="background: #007bff; color: white; border: none; padding: 8px 12px; border-radius: 4px; cursor: pointer; margin-right: 5px;">↕️ Reset Sorting</button>
                <button onclick="exportTableData()" style="background: #28a745; color: white; border: none; padding: 8px 12px; border-radius: 4px; cursor: pointer;">📊 Export Data</button>
                <div style="font-size: 11px; margin-top: 8px; color: #6c757d; line-height: 1.3;">
                    <strong>Shortcuts:</strong><br>
                    Ctrl+F: Focus filter | Esc: Clear filters<br>
                    Click headers to sort tables
                </div>
            `;
            body.appendChild(globalControls);
        });
        
        // Export function for table data
        function exportTableData() {
            const tables = document.querySelectorAll('table');
            let csvContent = '';
            
            tables.forEach((table, tableIndex) => {
                const tableTitle = table.previousElementSibling?.textContent || 'Table ' + (tableIndex + 1);
                csvContent += '\\n\\n=== ' + tableTitle + ' ===\\n';
                
                const rows = table.querySelectorAll('tr');
                rows.forEach(row => {
                    if (!row.classList.contains('hidden-row')) {
                        const cells = Array.from(row.cells).map(cell => 
                            '"' + cell.textContent.trim().replace(/"/g, '""') + '"'
                        );
                        csvContent += cells.join(',') + '\\n';
                    }
                });
            });
            
            const blob = new Blob([csvContent], { type: 'text/csv' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'meshtastic-telemetry-' + new Date().toISOString().split('T')[0] + '.csv';
            a.click();
            window.URL.revokeObjectURL(url);
        }
        
        // Global control functions
        function clearAllFilters() {
            const filterInputs = document.querySelectorAll('.filter-input');
            filterInputs.forEach(input => {
                input.value = '';
                const tableId = input.closest('.filter-container').nextElementSibling.id;
                filterTable(tableId, '');
            });
        }
        
        function resetAllSorting() {
            const tables = document.querySelectorAll('table');
            tables.forEach(table => {
                const headers = table.querySelectorAll('th');
                headers.forEach(header => {
                    header.classList.remove('sort-asc', 'sort-desc');
                    header.dataset.sortDirection = '';
                });
                
                // Reset row order to original (reload would be needed for true reset)
                const tbody = table.querySelector('tbody') || table;
                const rows = Array.from(tbody.querySelectorAll('tr')).slice(1);
                // Sort by first column (usually timestamp or address) ascending
                if (rows.length > 0 && table.id) {
                    sortTable(table.id, 0);
                }
            });
        }
        
        // Toggle section visibility
        function toggleSection(sectionId) {
            const section = document.getElementById(sectionId);
            const toggle = document.getElementById(sectionId + '-toggle');
            
            if (section.style.display === 'none') {
                section.style.display = 'block';
                toggle.textContent = '[click to collapse]';
            } else {
                section.style.display = 'none';
                toggle.textContent = '[click to expand]';
            }
        }
    </script>
</head>
<body>
EOF
        
        echo "<h1>Meshtastic Telemetry Statistics</h1>"
        echo "<p><em>Last updated: $(date)</em></p>"
        
        # Embed comprehensive telemetry chart for all monitored nodes
        if [ -f "multi_node_telemetry_chart.png" ]; then
            echo "<div style='background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #28a745;'>"
            echo "<h3 style='margin-top: 0; color: #28a745;'>📊 Comprehensive Telemetry Chart</h3>"
            echo "<h4>Multi-Node Telemetry Overview (All Monitored Nodes)</h4>"
            echo "<img src='multi_node_telemetry_chart.png' alt='Multi-Node Telemetry Chart' style='max-width: 70%; height: auto; border: 1px solid #ddd; border-radius: 4px; margin: 10px 0; display: block; margin-left: auto; margin-right: auto;'>"
            echo "</div>"
        fi
        
        # Navigation Index
        echo "<div style='background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #007bff;'>"
        echo "<h3 style='margin-top: 0; color: #007bff;'>📍 Quick Navigation</h3>"
        echo "<div style='display: flex; flex-wrap: wrap; gap: 15px;'>"
    echo "<a href='#gps-map-header' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #e8f5e9; border-radius: 4px; color: #388e3c;'>🗺️ GPS Map</a>"
        echo "<a href='#ml-status' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #e3f2fd; border-radius: 4px; color: #1976d2;'>🤖 ML Status</a>"
        echo "<a href='#monitored-addresses' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #e8f5e9; border-radius: 4px; color: #388e3c;'>📊 Monitored Addresses</a>"
        echo "<a href='#latest-telemetry' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #fff3e0; border-radius: 4px; color: #f57c00;'>📈 Latest Telemetry</a>"
        echo "<a href='#telemetry-history' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #fce4ec; border-radius: 4px; color: #c2185b;'>📋 Telemetry History</a>"
        echo "<a href='#current-nodes' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #f3e5f5; border-radius: 4px; color: #7b1fa2;'>🌐 Current Nodes</a>"
        echo "<a href='#all-nodes-header' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #ede7f6; border-radius: 4px; color: #5e35b1;'>📡 All Nodes Ever Heard</a>"
        echo "<a href='#weather-predictions' class='nav-link' style='text-decoration: none; padding: 8px 12px; background: #e0f7fa; border-radius: 4px; color: #00796b;'>☀️ Weather Predictions</a>"
        echo "</div>"
        echo "</div>"
        
        # GPS Map Section
    echo "<h2 id='gps-map-header'>🗺️ Network GPS Map</h2>"
        echo "<div style='background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #28a745;'>"
        
        # Include GPS map section
        generate_gps_map_section
        
        echo "</div>"
        
        # Include network topology if traceroute is enabled
        generate_network_topology_section

        # Network Activity News Section (original stats)
        echo "<h2>📰 Network Activity</h2>"
        if [ -f "network_news.html" ]; then
            # Include full network news HTML (header + lists)
            cat network_news.html
        else
            echo "<p>Network activity analysis not available</p>"
        fi
        
        # ML Learning Status Section
        echo "<h2 id='ml-status'>🤖 Machine Learning Power Prediction Status</h2>"
        
        # Check if ML system is active
        if [ -f "power_predictions.csv" ] && [ -f "prediction_accuracy.csv" ]; then
            # Count total predictions made
            total_predictions=$(tail -n +2 "power_predictions.csv" 2>/dev/null | wc -l)
            
            # Count accuracy measurements
            total_accuracy_checks=$(tail -n +2 "prediction_accuracy.csv" 2>/dev/null | wc -l)
            
            # Calculate overall accuracy if data available
            if [ -f "prediction_accuracy.csv" ] && [ "$total_accuracy_checks" -gt 0 ]; then
                overall_accuracy=$(tail -n +2 "prediction_accuracy.csv" | awk -F',' 'BEGIN{sum=0;count=0} {
                    if($10!="") {
                        err = ($10 < 0 ? -$10 : $10)
                        sum += err
                        count++
                    }
                } END{
                    if(count>0) {
                        avg_err = sum/count
                        acc = 100 - avg_err
                        if(acc < 0) acc = 0
                        printf "%.1f%%", acc
                    } else {
                        print "Calculating..."
                    }
                }')
            else
                overall_accuracy="Learning..."
            fi
            
            # Get nodes being tracked
            nodes_tracked=$(cut -d',' -f2 "power_predictions.csv" 2>/dev/null | tail -n +2 | sort -u | wc -l)
            
            echo "<div style='background: #e8f5e8; padding: 15px; border-radius: 5px; margin: 10px 0;'>"
            echo "<p><strong>🟢 ML System Active</strong></p>"
            echo "<ul>"
            echo "<li><strong>Predictions Made:</strong> $total_predictions</li>"
            echo "<li><strong>Accuracy Checks:</strong> $total_accuracy_checks</li>"
            echo "<li><strong>Overall Accuracy:</strong> $overall_accuracy</li>"
            echo "<li><strong>Nodes Tracked:</strong> $nodes_tracked</li>"
            echo "</ul>"
            
            # Show recent learning activity
            if [ "$total_accuracy_checks" -gt 0 ]; then
                echo "<p><strong>Recent Learning Activity:</strong></p>"
                echo "<ul style='font-size: 0.9em;'>"
                tail -3 "prediction_accuracy.csv" | while IFS=',' read -r timestamp node_id pred_time predicted_6h actual_6h predicted_12h actual_12h predicted_24h actual_24h error_6h error_12h error_24h weather; do
                    if [ "$timestamp" != "timestamp" ]; then
                        echo "<li>$(date -d "$timestamp" '+%m-%d %H:%M'): $node_id predicted ${predicted_6h}%, actual ${actual_6h}% (error: ${error_6h}%)</li>"
                    fi
                done
                echo "</ul>"
            fi
            echo "</div>"
        else
            echo "<div style='background: #fff3cd; padding: 15px; border-radius: 5px; margin: 10px 0;'>"
            echo "<p><strong>🟡 ML System Initializing</strong></p>"
            echo "<p>Machine learning power predictor is collecting initial data. Improved predictions will be available after sufficient data is gathered.</p>"
            echo "</div>"
        fi
        
        # Display monitored addresses with resolved names and success/failure rates
        echo "<h3 id='monitored-addresses'>Monitored Addresses</h3>"
        echo "<table>"
        echo "<tr><th>#</th><th>Address</th><th>Device Name</th><th>Success</th><th>Failures</th><th>Success Rate</th><th>Last Success</th></tr>"
        index=1
        
        # Pre-compute all statistics with single awk pass
        local stats_file
        stats_file=$(compute_telemetry_stats)
        
        for addr in "${ADDRESSES[@]}"; do
            device_name="$(get_node_info "$addr")"
            if [ -n "$device_name" ] && [ "$device_name" != "$addr" ]; then
                resolved_name="$device_name"
            else
                resolved_name="Unknown"
            fi
            
            # Read pre-computed statistics
            if [ -f "$stats_file" ]; then
                local stats_line
                stats_line=$(grep "^$addr|" "$stats_file")
                if [ -n "$stats_line" ]; then
                    IFS='|' read -r _ total_attempts success_count failure_count success_rate_num actual_last_seen _ _ _ _ _ <<< "$stats_line"
                    success_rate="${success_rate_num}%"
                    display_timestamp=$(echo "$actual_last_seen" | sed 's/:[0-9][0-9]+[0-9:+-]*$//')
                else
                    total_attempts=0
                    success_count=0
                    failure_count=0
                    success_rate="N/A"
                    display_timestamp="Never"
                fi
            else
                total_attempts=0
                success_count=0
                failure_count=0
                success_rate="N/A"
                display_timestamp="Never"
            fi
            
            # Color code success rate
            if [ "$total_attempts" -gt 0 ]; then
                success_rate_num_clean=$(echo "$success_rate" | sed 's/%//')
                if (( $(echo "$success_rate_num_clean >= 90" | bc -l 2>/dev/null) )); then
                    success_rate_class="good"
                elif (( $(echo "$success_rate_num_clean >= 70" | bc -l 2>/dev/null) )); then
                    success_rate_class="normal"
                elif (( $(echo "$success_rate_num_clean >= 50" | bc -l 2>/dev/null) )); then
                    success_rate_class="warning"
                else
                    success_rate_class="critical"
                fi
            else
                success_rate_class="unknown"
            fi
            
            # Check if this address has GPS coordinates in the nodes CSV
            if [ -f "$NODES_CSV" ]; then
                gps_coords=$(awk -F, -v id="$addr" '$2 == id {
                    lat = $7; gsub(/^"|"$/, "", lat)
                    lon = $8; gsub(/^"|"$/, "", lon)
                    if (lat != "" && lon != "" && lat != "N/A" && lon != "N/A" && 
                        lat != "0.0" && lon != "0.0" && lat != "0" && lon != "0") {
                        print lat "," lon
                    }
                    exit
                }' "$NODES_CSV")
                
                if [ -n "$gps_coords" ]; then
                    lat=$(echo "$gps_coords" | cut -d',' -f1)
                    lon=$(echo "$gps_coords" | cut -d',' -f2)
                    device_name_display="<a href=\"https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}&zoom=15\" target=\"_blank\" title=\"View ${resolved_name} on OpenStreetMap (${lat}, ${lon})\">${resolved_name}</a>"
                else
                    device_name_display="$resolved_name"
                fi
            else
                device_name_display="$resolved_name"
            fi
            
            echo "<tr>"
            echo "<td class=\"number\">$index</td>"
            echo "<td class=\"address\">$addr</td>"
            echo "<td>$device_name_display</td>"
            echo "<td class=\"number good\">$success_count</td>"
            echo "<td class=\"number critical\">$failure_count</td>"
            echo "<td class=\"number $success_rate_class\">$success_rate</td>"
            echo "<td class=\"timestamp\">$(format_human_time "$display_timestamp")</td>"
            echo "</tr>"
            index=$((index + 1))
        done
        echo "</table>"
        
        # Clean up stats file
        [ -n "$stats_file" ] && rm -f "$stats_file"

        # Gather all successful telemetry for per-node stats
        awk -F',' '$3=="success"' "$TELEMETRY_CSV" > /tmp/all_success.csv
        
        # Per-Node Statistics Summary
        echo "<h2 id='monitored-addresses'>Node Summary Statistics</h2>"
        echo "<table id='summary-table'>"
        echo "<tr><th>Address</th><th>Battery (%)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (h)</th><th>Last Success</th><th>Success</th><th>Failures</th><th>Success Rate</th><th>Voltage (V)</th><th>Min Battery</th><th>Max Battery</th><th>Max Channel Util</th><th>Max Tx Util</th><th>Est. Time Left (h)</th><th>Power in 6h (ML)</th><th>Power in 12h (ML)</th><th>Power in 24h (ML)</th><th>ML Accuracy</th></tr>"
        
        cut -d',' -f2 /tmp/all_success.csv | sort | uniq | while read address; do
            if [ -z "$address" ]; then continue; fi
            
            # Get all records for this address (both success and failures) for counting
            all_attempts=$(grep ",$address," "$TELEMETRY_CSV" | sort -t',' -k1,1)
            total_attempts=$(echo "$all_attempts" | wc -l)
            
            # Count success and failures
            success_count=$(echo "$all_attempts" | awk -F',' '$3=="success"' | wc -l)
            failure_count=$(echo "$all_attempts" | awk -F',' '$3!="success" && $3!=""' | wc -l)
            
            # Calculate success rate
            if [ "$total_attempts" -gt 0 ]; then
                success_rate=$(echo "scale=1; $success_count * 100 / $total_attempts" | bc 2>/dev/null)
                success_rate="${success_rate}%"
            else
                success_rate="N/A"
            fi
            
            # Get all successful records for this address sorted by timestamp
            node_data=$(grep ",$address," /tmp/all_success.csv | sort -t',' -k1,1)
            
            # Get latest record for current values (from successful attempts)
            latest=$(echo "$node_data" | tail -1)
            IFS=',' read -r latest_timestamp latest_address latest_status latest_battery latest_voltage latest_channel_util latest_tx_util latest_uptime <<< "$latest"
            
            # Get last successful attempt time (not including failures/timeouts)
            last_success_timestamp=$(echo "$node_data" | tail -1 | cut -d',' -f1)
            if [ -n "$last_success_timestamp" ]; then
                latest_timestamp="$last_success_timestamp"
            else
                # If no successful attempts, use "Never"
                latest_timestamp="Never"
            fi
            
            # Calculate min/max battery values
            min_battery=$(echo "$node_data" | awk -F',' '{if($4 != "") print $4}' | sort -n | head -1)
            max_battery=$(echo "$node_data" | awk -F',' '{if($4 != "") print $4}' | sort -nr | head -1)
            
            # Calculate max channel util and tx util values
            max_channel_util=$(echo "$node_data" | awk -F',' '{if($6 != "") print $6}' | sort -nr | head -1)
            max_tx_util=$(echo "$node_data" | awk -F',' '{if($7 != "") print $7}' | sort -nr | head -1)
            
            # Advanced battery life estimation with improved accuracy
            est_hours_left="N/A"
            record_count=$(echo "$node_data" | wc -l)
            
            if [ "$record_count" -ge 2 ] && [ -n "$latest_battery" ] && [ "$latest_battery" != "" ]; then
                # Filter out records with missing battery data
                filtered_data=$(echo "$node_data" | awk -F',' '$4 != "" && $4 > 0')
                filtered_count=$(echo "$filtered_data" | wc -l)
                
                if [ "$filtered_count" -ge 2 ]; then
                    # Use different sample sizes based on available data
                    if [ "$filtered_count" -ge 10 ]; then
                        sample_size=8  # Use last 8 records for better trend analysis
                    elif [ "$filtered_count" -ge 5 ]; then
                        sample_size=5
                    else
                        sample_size=$filtered_count
                    fi
                    
                    # Get sample data (last N records with valid battery)
                    sample_data=$(echo "$filtered_data" | tail -$sample_size)
                    
                    # Calculate multiple trend estimates and average them
                    total_trend=0
                    valid_trends=0
                    
                    # Method 1: First vs Last in sample
                    first_record=$(echo "$sample_data" | head -1)
                    last_record=$(echo "$sample_data" | tail -1)
                    
                    IFS=',' read -r first_ts first_addr first_status first_batt first_volt first_ch first_tx first_up <<< "$first_record"
                    IFS=',' read -r last_ts last_addr last_status last_batt last_volt last_ch last_tx last_up <<< "$last_record"
                    
                    if [ -n "$first_batt" ] && [ -n "$last_batt" ] && [ "$first_batt" != "" ] && [ "$last_batt" != "" ]; then
                        first_epoch=$(date -d "$first_ts" +%s 2>/dev/null)
                        last_epoch=$(date -d "$last_ts" +%s 2>/dev/null)
                        
                        if [ -n "$first_epoch" ] && [ -n "$last_epoch" ] && [ "$last_epoch" -gt "$first_epoch" ]; then
                            time_diff_hours=$(echo "scale=4; ($last_epoch - $first_epoch) / 3600" | bc 2>/dev/null)
                            battery_diff=$(echo "$first_batt - $last_batt" | bc 2>/dev/null)
                            
                            if [ -n "$time_diff_hours" ] && [ -n "$battery_diff" ] && (( $(echo "$time_diff_hours > 0.5" | bc -l 2>/dev/null) )); then
                                trend1=$(echo "scale=6; $battery_diff / $time_diff_hours" | bc 2>/dev/null)
                                if [ -n "$trend1" ]; then
                                    total_trend=$(echo "$total_trend + $trend1" | bc 2>/dev/null)
                                    valid_trends=$((valid_trends + 1))
                                fi
                            fi
                        fi
                    fi
                    
                    # Method 2: Linear regression-like approach using multiple points
                    if [ "$sample_size" -ge 3 ]; then
                        # Calculate average trend from consecutive pairs
                        echo "$sample_data" | while IFS=',' read -r ts addr status batt volt ch tx up; do
                            echo "$ts,$batt"
                        done > /tmp/battery_trend_$$.csv
                        
                        trend_sum=0
                        trend_count=0
                        prev_epoch=""
                        prev_batt=""
                        
                        while IFS=',' read -r ts batt; do
                            if [ -n "$prev_epoch" ] && [ -n "$prev_batt" ] && [ -n "$batt" ] && [ "$batt" != "" ]; then
                                curr_epoch=$(date -d "$ts" +%s 2>/dev/null)
                                if [ -n "$curr_epoch" ] && [ "$curr_epoch" -gt "$prev_epoch" ]; then
                                    time_diff_h=$(echo "scale=4; ($curr_epoch - $prev_epoch) / 3600" | bc 2>/dev/null)
                                    batt_diff=$(echo "$prev_batt - $batt" | bc 2>/dev/null)
                                    
                                    if [ -n "$time_diff_h" ] && [ -n "$batt_diff" ] && (( $(echo "$time_diff_h > 0.1" | bc -l 2>/dev/null) )); then
                                        pair_trend=$(echo "scale=6; $batt_diff / $time_diff_h" | bc 2>/dev/null)
                                        if [ -n "$pair_trend" ]; then
                                            trend_sum=$(echo "$trend_sum + $pair_trend" | bc 2>/dev/null)
                                            trend_count=$((trend_count + 1))
                                        fi
                                    fi
                                fi
                            fi
                            prev_epoch=$(date -d "$ts" +%s 2>/dev/null)
                            prev_batt="$batt"
                        done < /tmp/battery_trend_$$.csv
                        
                        if [ "$trend_count" -gt 0 ]; then
                            avg_trend=$(echo "scale=6; $trend_sum / $trend_count" | bc 2>/dev/null)
                            if [ -n "$avg_trend" ]; then
                                total_trend=$(echo "$total_trend + $avg_trend" | bc 2>/dev/null)
                                valid_trends=$((valid_trends + 1))
                            fi
                        fi
                        
                        rm -f /tmp/battery_trend_$$.csv
                    fi
                    
                    # Calculate final estimate
                    if [ "$valid_trends" -gt 0 ]; then
                        avg_drop_per_hour=$(echo "scale=6; $total_trend / $valid_trends" | bc 2>/dev/null)
                        
                        if [ -n "$avg_drop_per_hour" ]; then
                            # Check for different scenarios
                            if (( $(echo "$avg_drop_per_hour <= 0" | bc -l 2>/dev/null) )); then
                                est_hours_left="Stable/Charging"
                            elif (( $(echo "$avg_drop_per_hour < 0.1" | bc -l 2>/dev/null) )); then
                                # Very slow drain - calculate but cap at reasonable max
                                raw_estimate=$(echo "scale=1; $latest_battery / $avg_drop_per_hour" | bc 2>/dev/null)
                                if [ -n "$raw_estimate" ] && (( $(echo "$raw_estimate > 2160" | bc -l 2>/dev/null) )); then
                                    est_hours_left=">3mo"
                                elif [ -n "$raw_estimate" ] && (( $(echo "$raw_estimate > 720" | bc -l 2>/dev/null) )); then
                                    est_hours_left=">1mo"
                                else
                                    est_hours_left="$raw_estimate"
                                fi
                            elif (( $(echo "$avg_drop_per_hour > 10" | bc -l 2>/dev/null) )); then
                                # Very fast drain - likely abnormal
                                raw_estimate=$(echo "scale=1; $latest_battery / $avg_drop_per_hour" | bc 2>/dev/null)
                                if [ -n "$raw_estimate" ]; then
                                    est_hours_left="$raw_estimate (fast drain)"
                                fi
                            else
                                # Normal drain rate
                                est_hours_left=$(echo "scale=1; $latest_battery / $avg_drop_per_hour" | bc 2>/dev/null)
                                
                                # Add confidence indicator based on data quality
                                if [ "$sample_size" -ge 6 ] && [ "$filtered_count" -ge 8 ]; then
                                    # High confidence - sufficient data
                                    est_hours_left="$est_hours_left"
                                elif [ "$sample_size" -ge 3 ]; then
                                    # Medium confidence
                                    est_hours_left="~$est_hours_left"
                                else
                                    # Low confidence
                                    est_hours_left="~$est_hours_left?"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
            
            # Get device name
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            
            # Format timestamp for display (remove seconds for brevity)
            display_timestamp=$(echo "$latest_timestamp" | sed 's/:[0-9][0-9]+[0-9:+-]*$//')
            
            # Get CSS classes for color coding
            battery_class=$(get_value_class "$latest_battery" "battery")
            voltage_class=$(get_value_class "$latest_voltage" "voltage")
            channel_util_class=$(get_value_class "$latest_channel_util" "channel_util")
            tx_util_class=$(get_value_class "$latest_tx_util" "tx_util")
            min_battery_class=$(get_value_class "$min_battery" "battery")
            max_battery_class=$(get_value_class "$max_battery" "battery")
            max_channel_util_class=$(get_value_class "$max_channel_util" "channel_util")
            max_tx_util_class=$(get_value_class "$max_tx_util" "tx_util")
            time_left_class=$(get_value_class "$est_hours_left" "time_left")
            
            # Color code success rate
            if [ "$total_attempts" -gt 0 ]; then
                success_rate_num=$(echo "$success_rate" | sed 's/%//')
                if (( $(echo "$success_rate_num >= 90" | bc -l 2>/dev/null) )); then
                    success_rate_class="good"
                elif (( $(echo "$success_rate_num >= 70" | bc -l 2>/dev/null) )); then
                    success_rate_class="normal"
                elif (( $(echo "$success_rate_num >= 50" | bc -l 2>/dev/null) )); then
                    success_rate_class="warning"
                else
                    success_rate_class="critical"
                fi
            else
                success_rate_class="unknown"
            fi
            
            echo "<tr>"
            echo "<td class=\"address\">$address_display</td>"
            
            # Add trend indicators to key metrics
            battery_trend=$(calculate_trend "$address" "battery" "$latest_battery")
            voltage_trend=$(calculate_trend "$address" "voltage" "$latest_voltage")
            channel_util_trend=$(calculate_trend "$address" "channel_util" "$latest_channel_util")
            tx_util_trend=$(calculate_trend "$address" "tx_util" "$latest_tx_util")
            
            # Convert uptime to human-readable format
            uptime_hours=$(convert_uptime_to_hours "$latest_uptime")
            uptime_class=$(get_value_class "$latest_uptime" "uptime")
            
            # Priority columns first: Battery, Channel Util, Tx Util, Uptime
            echo "<td class=\"number $battery_class\">${latest_battery:-N/A}${battery_trend}</td>"
            echo "<td class=\"number $channel_util_class\">${latest_channel_util:-N/A}${channel_util_trend}</td>"
            echo "<td class=\"number $tx_util_class\">${latest_tx_util:-N/A}${tx_util_trend}</td>"
            echo "<td class=\"number $uptime_class\">${uptime_hours:-N/A}</td>"
            
            # Then Last Seen and connection stats
            echo "<td class=\"timestamp\">$(format_human_time "$display_timestamp")</td>"
            echo "<td class=\"number good\">$success_count</td>"
            echo "<td class=\"number critical\">$failure_count</td>"
            echo "<td class=\"number $success_rate_class\">$success_rate</td>"
            
            # Other metrics
            echo "<td class=\"number $voltage_class\">${latest_voltage:-N/A}${voltage_trend}</td>"
            echo "<td class=\"number $min_battery_class\">${min_battery:-N/A}</td>"
            echo "<td class=\"number $max_battery_class\">${max_battery:-N/A}</td>"
            echo "<td class=\"number $max_channel_util_class\">${max_channel_util:-N/A}</td>"
            echo "<td class=\"number $max_tx_util_class\">${max_tx_util:-N/A}</td>"
            echo "<td class=\"number $time_left_class\">$est_hours_left</td>"
            
            # Get ML-enhanced weather predictions for this node
            ml_result=$(get_ml_predictions "$address")
            IFS='|' read -r ml_6h ml_12h ml_24h ml_accuracy <<< "$ml_result"
            
            # Fall back to regular weather predictions if ML not available
            if [ "$ml_6h" = "N/A" ]; then
                weather_predictions=$(get_weather_predictions "$address")
                IFS='|' read -r pred_6h pred_12h pred_24h <<< "$weather_predictions"
                ml_accuracy="N/A"
            else
                pred_6h="$ml_6h"
                pred_12h="$ml_12h"
                pred_24h="$ml_24h"
            fi
            
            # Determine accuracy class for color coding
            accuracy_class="unknown"
            if [ "$ml_accuracy" != "N/A" ] && [ "$ml_accuracy" != "Learning" ]; then
                accuracy_num=$(echo "$ml_accuracy" | sed 's/%//')
                if (( $(echo "$accuracy_num >= 90" | bc -l 2>/dev/null) )); then
                    accuracy_class="good"
                elif (( $(echo "$accuracy_num >= 75" | bc -l 2>/dev/null) )); then
                    accuracy_class="normal"
                elif (( $(echo "$accuracy_num >= 60" | bc -l 2>/dev/null) )); then
                    accuracy_class="warning"
                else
                    accuracy_class="critical"
                fi
            fi
            
            echo "<td class=\"prediction\">${pred_6h}</td>"
            echo "<td class=\"prediction\">${pred_12h}</td>"
            echo "<td class=\"prediction\">${pred_24h}</td>"
            echo "<td class=\"number $accuracy_class\" title=\"ML prediction accuracy based on historical performance\">${ml_accuracy}</td>"
            echo "</tr>"
        done
        echo "</table>"

        # Recent Telemetry Data
        echo "<h2 id='latest-telemetry'>Recent Telemetry Data (Last 20 Records)</h2>"
        echo "<table id='recent-table'>"
        echo "<tr><th>Timestamp</th><th>Address</th><th>Battery (%)</th><th>Voltage (V)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (h)</th></tr>"
        
        awk -F',' '$3=="success"' "$TELEMETRY_CSV" | sort -t',' -k1,1r | head -20 | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            
            # Get CSS classes for color coding
            battery_class=$(get_value_class "$battery" "battery")
            voltage_class=$(get_value_class "$voltage" "voltage")
            channel_util_class=$(get_value_class "$channel_util" "channel_util")
            tx_util_class=$(get_value_class "$tx_util" "tx_util")
            
            echo "<tr>"
            echo "<td class=\"timestamp\">$(format_human_time "$timestamp")</td>"
            echo "<td class=\"address\">$address_display</td>"
            echo "<td class=\"number $battery_class\">${battery:-N/A}</td>"
            echo "<td class=\"number $voltage_class\">${voltage:-N/A}</td>"
            echo "<td class=\"number $channel_util_class\">${channel_util:-N/A}</td>"
            echo "<td class=\"number $tx_util_class\">${tx_util:-N/A}</td>"
            uptime_hours=$(convert_uptime_to_hours "$uptime")
            echo "<td class=\"number\">${uptime_hours:-N/A}</td>"
            echo "</tr>"
        done
        echo "</table>"

        # Per-Node History
        echo "<h2 id='telemetry-history' onclick=\"toggleSection('telemetry-history')\" style=\"cursor: pointer; user-select: none;\">"
        echo "📊 Telemetry History by Node <span id=\"telemetry-history-toggle\" style=\"font-size: 0.8em; color: #666;\">[click to expand]</span>"
        echo "</h2>"
        echo "<div id=\"telemetry-history\" style=\"display: none;\">"
        last_address=""
        prev_battery=""
        prev_voltage=""
        prev_channel_util=""
        prev_tx_util=""
        awk -F',' '$3=="success"' "$TELEMETRY_CSV" | sort -t',' -k2,2 -k1,1r | while IFS=',' read -r timestamp address status battery voltage channel_util tx_util uptime; do
            device_name="$(get_node_info "$address")"
            if [ -n "$device_name" ] && [ "$device_name" != "$address" ]; then
                address_display="$address ($device_name)"
            else
                address_display="$address"
            fi
            
            # Start new section for each address
            if [ "$last_address" != "$address" ]; then
                if [ -n "$last_address" ]; then 
                    echo "</table>"
                fi
                echo "<h3>$address_display</h3>"
                echo "<table id='history-table-${address//[!a-zA-Z0-9]/-}'>"
                echo "<tr><th>Timestamp</th><th>Battery (%)</th><th>Voltage (V)</th><th>Channel Util (%)</th><th>Tx Util (%)</th><th>Uptime (h)</th></tr>"
                last_address="$address"
                # Reset previous values for new node
                prev_battery=""
                prev_voltage=""
                prev_channel_util=""
                prev_tx_util=""
            fi
            
            # Get CSS classes for color coding
            battery_class=$(get_value_class "$battery" "battery")
            voltage_class=$(get_value_class "$voltage" "voltage")
            channel_util_class=$(get_value_class "$channel_util" "channel_util")
            tx_util_class=$(get_value_class "$tx_util" "tx_util")
            
            # Calculate simple trend indicators compared to previous entry
            battery_trend=""
            voltage_trend=""
            channel_util_trend=""
            tx_util_trend=""
            
            if [ -n "$prev_battery" ] && [ -n "$battery" ] && [ "$battery" != "N/A" ] && [ "$prev_battery" != "N/A" ]; then
                if (( $(echo "$battery > $prev_battery + 2" | bc -l 2>/dev/null) )); then
                    battery_trend=" <span class='trend-indicator trend-up' title='Up from ${prev_battery}%'>📈</span>"
                elif (( $(echo "$battery < $prev_battery - 2" | bc -l 2>/dev/null) )); then
                    battery_trend=" <span class='trend-indicator trend-down' title='Down from ${prev_battery}%'>📉</span>"
                fi
            fi
            
            if [ -n "$prev_voltage" ] && [ -n "$voltage" ] && [ "$voltage" != "N/A" ] && [ "$prev_voltage" != "N/A" ]; then
                if (( $(echo "$voltage > $prev_voltage + 0.1" | bc -l 2>/dev/null) )); then
                    voltage_trend=" <span class='trend-indicator trend-up' title='Up from ${prev_voltage}V'>📈</span>"
                elif (( $(echo "$voltage < $prev_voltage - 0.1" | bc -l 2>/dev/null) )); then
                    voltage_trend=" <span class='trend-indicator trend-down' title='Down from ${prev_voltage}V'>📉</span>"
                fi
            fi
            
            if [ -n "$prev_channel_util" ] && [ -n "$channel_util" ] && [ "$channel_util" != "N/A" ] && [ "$prev_channel_util" != "N/A" ]; then
                if (( $(echo "$channel_util > $prev_channel_util + 5" | bc -l 2>/dev/null) )); then
                    channel_util_trend=" <span class='trend-indicator trend-up-bad' title='Up from ${prev_channel_util}%'>📈</span>"
                elif (( $(echo "$channel_util < $prev_channel_util - 5" | bc -l 2>/dev/null) )); then
                    channel_util_trend=" <span class='trend-indicator trend-down-good' title='Down from ${prev_channel_util}%'>📉</span>"
                fi
            fi
            
            if [ -n "$prev_tx_util" ] && [ -n "$tx_util" ] && [ "$tx_util" != "N/A" ] && [ "$prev_tx_util" != "N/A" ]; then
                if (( $(echo "$tx_util > $prev_tx_util + 2" | bc -l 2>/dev/null) )); then
                    tx_util_trend=" <span class='trend-indicator trend-up-bad' title='Up from ${prev_tx_util}%'>📈</span>"
                elif (( $(echo "$tx_util < $prev_tx_util - 2" | bc -l 2>/dev/null) )); then
                    tx_util_trend=" <span class='trend-indicator trend-down-good' title='Down from ${prev_tx_util}%'>📉</span>"
                fi
            fi
            
            echo "<tr>"
            echo "<td class=\"timestamp\">$(format_human_time "$timestamp")</td>"
            echo "<td class=\"number $battery_class\">${battery:-N/A}${battery_trend}</td>"
            echo "<td class=\"number $voltage_class\">${voltage:-N/A}${voltage_trend}</td>"
            echo "<td class=\"number $channel_util_class\">${channel_util:-N/A}${channel_util_trend}</td>"
            echo "<td class=\"number $tx_util_class\">${tx_util:-N/A}${tx_util_trend}</td>"
            uptime_hours=$(convert_uptime_to_hours "$uptime")
            echo "<td class=\"number\">${uptime_hours:-N/A}</td>"
            echo "</tr>"
            
            # Store current values as previous for next iteration
            prev_battery="$battery"
            prev_voltage="$voltage"
            prev_channel_util="$channel_util"
            prev_tx_util="$tx_util"
        done
        if [ -n "$last_address" ]; then 
            echo "</table>"
        fi
        echo "</div>"

        # Current Node List
        if [ -f "$NODES_CSV" ]; then
            echo "<h2 id='current-nodes' onclick=\"toggleSection('current-nodes')\" style=\"cursor: pointer; user-select: none;\">"
            echo "🌐 Current Node List <span id=\"current-nodes-toggle\" style=\"font-size: 0.8em; color: #666;\">[click to expand]</span>"
            echo "</h2>"
            echo "<div id=\"current-nodes\" style=\"display: none;\">"
            echo "<table>"
            echo "<tr><th>#</th><th>User</th><th>ID</th><th>Hardware</th><th>Battery (%)</th><th>Channel Util (%)</th><th>Last Heard</th></tr>"
            
            # Sort with nodes having valid Last Heard first, then N/A entries at bottom
            index=1
            tail -n +2 "$NODES_CSV" 2>/dev/null | awk -F',' '{
                # Check if Last Heard field (column 16) is empty or N/A
                if ($16 == "" || $16 == "N/A") {
                    print "1," $0  # Add prefix "1" for N/A entries (sort last)
                } else {
                    print "0," $0  # Add prefix "0" for valid entries (sort first)
                }
            }' | sort -t',' -k1,1n -k17,17r | cut -d',' -f2- | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
                # Remove quotes if present
                user=$(echo "$user" | sed 's/^"//;s/"$//')
                hardware=$(echo "$hardware" | sed 's/^"//;s/"$//')
                latitude=$(echo "$latitude" | sed 's/^"//;s/"$//')
                longitude=$(echo "$longitude" | sed 's/^"//;s/"$//')
                
                # Check if GPS coordinates are valid (not empty, not 0.0, not "N/A")
                if [ -n "$latitude" ] && [ -n "$longitude" ] && \
                   [ "$latitude" != "N/A" ] && [ "$longitude" != "N/A" ] && \
                   [ "$latitude" != "0.0" ] && [ "$longitude" != "0.0" ] && \
                   [ "$latitude" != "0" ] && [ "$longitude" != "0" ]; then
                    # Create clickable link to OpenStreetMap
                    user_display="<a href=\"https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}&zoom=15\" target=\"_blank\" title=\"View ${user:-Unknown} on OpenStreetMap (${latitude}, ${longitude})\">${user:-N/A}</a>"
                else
                    user_display="${user:-N/A}"
                fi
                
                # Get CSS classes for color coding
                battery_class=$(get_value_class "$battery" "battery")
                channel_util_class=$(get_value_class "$channel_util" "channel_util")
                
                # Add trend indicators
                battery_trend=$(calculate_trend "$id" "battery" "$battery")
                channel_util_trend=$(calculate_trend "$id" "channel_util" "$channel_util")
                
                echo "<tr>"
                echo "<td class=\"number\">$index</td>"
                echo "<td>$user_display</td>"
                echo "<td class=\"address\">$id</td>"
                echo "<td>${hardware:-N/A}</td>"
                echo "<td class=\"number $battery_class\">${battery:-N/A}${battery_trend}</td>"
                echo "<td class=\"number $channel_util_class\">${channel_util:-N/A}${channel_util_trend}</td>"
                echo "<td class=\"timestamp\">$(format_human_time "${lastheard:-N/A}")</td>"
                echo "</tr>"
                index=$((index + 1))
            done
            echo "</table>"
            echo "</div>"
        fi
        
        # All Nodes Ever Heard Section
        if [ -f "$NODES_CSV" ]; then
            echo "<h2 id='all-nodes-header' onclick=\"toggleSection('all-nodes-content')\" style=\"cursor: pointer; user-select: none;\">"
            echo "📡 All Nodes Ever Heard <span id=\"all-nodes-toggle\" style=\"font-size: 0.8em; color: #666;\">[click to expand]</span>"
            echo "</h2>"
            echo "<div id=\"all-nodes-content\" style=\"display: none;\">"
            echo "<p><em>Comprehensive list of all nodes that have ever been detected on the mesh network, sorted by first appearance</em></p>"
            echo "<table>"
            echo "<tr><th>#</th><th>User</th><th>ID</th><th>Hardware</th><th>Role</th><th>GPS</th><th>First Heard</th><th>Last Heard</th><th>Status</th></tr>"
            
            # Get all unique nodes from nodes log, sorted by first appearance
            index=1
            tail -n +2 "$NODES_CSV" 2>/dev/null | awk -F',' '!seen[$2]++ {print}' | sort -t',' -k17,17 | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_util snr hops channel lastheard since; do
                # Remove quotes if present
                user=$(echo "$user" | sed 's/^"//;s/"$//')
                hardware=$(echo "$hardware" | sed 's/^"//;s/"$//')
                latitude=$(echo "$latitude" | sed 's/^"//;s/"$//')
                longitude=$(echo "$longitude" | sed 's/^"//;s/"$//')
                
                # Check if GPS coordinates are valid
                if [ -n "$latitude" ] && [ -n "$longitude" ] && \
                   [ "$latitude" != "N/A" ] && [ "$longitude" != "N/A" ] && \
                   [ "$latitude" != "0.0" ] && [ "$longitude" != "0.0" ] && \
                   [ "$latitude" != "0" ] && [ "$longitude" != "0" ]; then
                    gps_display="<a href=\"https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}&zoom=15\" target=\"_blank\" title=\"View on map\">${latitude}, ${longitude}</a>"
                else
                    gps_display="N/A"
                fi
                
                # Determine node status based on last heard time
                status="Unknown"
                status_class="unknown"
                if [ -n "$lastheard" ] && [ "$lastheard" != "N/A" ]; then
                    current_time=$(date +%s)
                    last_heard_time=$(date -d "$lastheard" +%s 2>/dev/null)
                    if [ -n "$last_heard_time" ]; then
                        time_diff=$((current_time - last_heard_time))
                        hours_ago=$((time_diff / 3600))
                        
                        if [ $hours_ago -lt 1 ]; then
                            status="🟢 Active"
                            status_class="good"
                        elif [ $hours_ago -lt 24 ]; then
                            status="🟡 Recent"
                            status_class="warning"
                        elif [ $hours_ago -lt 168 ]; then  # 1 week
                            status="🟠 Inactive"
                            status_class="critical"
                        else
                            status="🔴 Offline"
                            status_class="critical"
                        fi
                    fi
                fi
                
                # Format first heard time
                first_heard="${since:-N/A}"
                if [ "$first_heard" != "N/A" ] && [ -n "$first_heard" ]; then
                    first_heard=$(date -d "$first_heard" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$first_heard")
                fi
                
                # Format last heard time
                last_heard="${lastheard:-N/A}"
                if [ "$last_heard" != "N/A" ] && [ -n "$last_heard" ]; then
                    last_heard=$(date -d "$last_heard" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_heard")
                fi
                
                echo "<tr>"
                echo "<td class=\"number\">$index</td>"
                echo "<td>${user:-N/A}</td>"
                echo "<td class=\"address\">$id</td>"
                echo "<td>${hardware:-N/A}</td>"
                echo "<td>${role:-N/A}</td>"
                echo "<td>$gps_display</td>"
                echo "<td class=\"timestamp\">$first_heard</td>"
                echo "<td class=\"timestamp\">$last_heard</td>"
                echo "<td class=\"$status_class\">$status</td>"
                echo "</tr>"
                index=$((index + 1))
            done
            echo "</table>"
            echo "</div>"
        fi

        # Weather-based Energy Predictions Section - DISABLED
        # Uncomment the section below to re-enable weather predictions
        #if [[ -f "weather_predictions.json" ]]; then
        #    echo "<h2 id='weather-predictions'>☀️ Weather-Based Energy Predictions</h2>"
        #    echo "<p><em>Solar energy predictions based on weather forecast and current battery levels</em></p>"
        #    echo "<table>"
        #    echo "<tr>"
        #    echo "<th>#</th>"
        #    echo "<th>Node</th>"
        #    echo "<th>Location</th>"
        #    echo "<th>Current Battery</th>"
        #    echo "<th>Weather Prediction</th>"
        #    echo "</tr>"
        #    
        #    # Parse JSON predictions and display only nodes with valid battery data
        #    local weather_index=1
        #    if command -v jq &> /dev/null; then
        #        jq -r '.predictions[] | "\(.node_id)|\(.longname)|\(.coordinates.lat),\(.coordinates.lon)|\(.current_battery)|\(.predictions."6h".battery_level // "N/A")|\(.predictions."12h".battery_level // "N/A")|\(.predictions."24h".battery_level // "N/A")"' weather_predictions.json 2>/dev/null | while IFS='|' read -r node_id longname location current_battery pred_6h pred_12h pred_24h; do
        #            # Only show nodes with known battery levels (not N/A and not empty)
        #            if [ "$current_battery" != "N/A" ] && [ -n "$current_battery" ] && [[ "$current_battery" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        #                echo "<tr>"
        #                echo "<td>$weather_index</td>"
        #                echo "<td>$(echo "$node_id" | sed 's/</\&lt;/g; s/>/\&gt;/g')</td>"
        #                echo "<td>$location</td>"
        #                echo "<td>$current_battery%</td>"
        #                
        #                # Format prediction display
        #                local prediction_display=""
        #                if [ "$pred_6h" != "N/A" ] && [ "$pred_12h" != "N/A" ] && [ "$pred_24h" != "N/A" ]; then
        #                    prediction_display="6h: ${pred_6h}% | 12h: ${pred_12h}% | 24h: ${pred_24h}%"
        #                else
        #                    prediction_display="Calculating..."
        #                fi
        #                
        #                echo "<td class=\"prediction\">$prediction_display</td>"
        #                echo "</tr>"
        #                weather_index=$((weather_index + 1))
        #            fi
        #        done
        #    else
        #        echo "<tr><td colspan=\"5\">Weather predictions require 'jq' tool. Install with: sudo apt install jq</td></tr>"
        #    fi
        #    
        #    echo "</table>"
        #    echo "<p><em>Legend: ⚡ Charging | 📉 Slow drain | 🔋 Fast drain | 📊 Stable</em></p>"
        #    echo "<p><em>Note: Predictions are estimates based on weather data and typical solar panel performance</em></p>"
        #else
        #    echo "<h2>☀️ Weather-Based Energy Predictions</h2>"
        #    echo "<p><em>Weather predictions will appear here after the next data collection cycle</em></p>"
        #fi
        
        echo "</body></html>"
    } > "$STATS_HTML"
    
    # Clean up temporary files
    rm -f /tmp/all_success.csv /tmp/last_success.csv
}

# Backward compatibility wrapper - calls the new configurable function
generate_stats_html() {
    generate_html_dashboards
}

# If this script is executed directly (not sourced), run the generator
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Load configuration if available
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        # shellcheck disable=SC1090
        source "$SCRIPT_DIR/.env"
    fi
    generate_html_dashboards
fi
