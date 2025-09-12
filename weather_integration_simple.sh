#!/bin/bash

# Simplified weather integration script
# Avoids complex bc calculations that cause character encoding issues

# File for saving predictions
PREDICTIONS_FILE="weather_predictions.json"

# Simple sunrise/sunset estimation (approximate)
get_simple_solar_hours() {
    local current_hour=$(date +%H)
    
    # Simple daylight estimation (6 AM to 6 PM = 12 hours)
    if [ $current_hour -ge 6 ] && [ $current_hour -lt 18 ]; then
        echo "12"  # Daylight hours
    else
        echo "0"   # Night hours
    fi
}

# Calculate solar efficiency without complex math
calculate_simple_solar_efficiency() {
    local cloud_cover="${1:-50}"
    local temp="${2:-20}"
    
    # Base efficiency
    local base_efficiency=85
    
    # Cloud cover penalty (simple linear reduction)
    local cloud_penalty=$(echo "$cloud_cover / 2" | bc)
    local efficiency=$(echo "$base_efficiency - $cloud_penalty" | bc)
    
    # Ensure minimum efficiency
    if [ $efficiency -lt 10 ]; then
        efficiency=10
    fi
    
    echo $efficiency
}

# Generate weather predictions for nodes
generate_weather_predictions() {
    local telemetry_csv="$1"
    
    echo "Generating simplified weather predictions..."
    
    # Create JSON header
    cat > "$PREDICTIONS_FILE" << EOF
{
  "generated_at": "$(date -Iseconds)",
  "predictions": [
EOF
    
    local first_entry=true
    
    # Process each monitored node
    if [ -f "$telemetry_csv" ]; then
        tail -n +2 "$telemetry_csv" 2>/dev/null | while IFS=',' read -r timestamp node_id user battery voltage channel_util tx_util uptime snr hops channel; do
            if [ -n "$node_id" ] && [ -n "$battery" ] && [ "$battery" != "N/A" ]; then
                # Skip header row if it somehow made it through
                if [ "$timestamp" = "timestamp" ]; then
                    continue
                fi
                
                # Clean battery value
                battery_clean=$(echo "$battery" | sed 's/%//g' | sed 's/[^0-9.]//g')
                
                if [ -n "$battery_clean" ] && [ "$battery_clean" != "0" ]; then
                    # Simple solar efficiency calculation
                    solar_efficiency=$(calculate_simple_solar_efficiency 50 20)
                    
                    # Battery capping at 100%
                    if (( $(echo "$battery_clean > 100" | bc -l) )); then
                        battery_clean=100
                    fi
                    
                    # Simple predictions (no complex weather integration)
                    # 6h prediction: slight decline for battery powered, maintain for solar
                    pred_6h=$(echo "scale=2; $battery_clean - 5" | bc)
                    if (( $(echo "$pred_6h < 0" | bc -l) )); then
                        pred_6h=0
                    fi
                    
                    # 12h prediction: more decline
                    pred_12h=$(echo "scale=2; $battery_clean - 10" | bc)
                    if (( $(echo "$pred_12h < 0" | bc -l) )); then
                        pred_12h=0
                    fi
                    
                    # 24h prediction: significant decline for battery, stable for solar
                    pred_24h=$(echo "scale=2; $battery_clean - 15" | bc)
                    if (( $(echo "$pred_24h < 0" | bc -l) )); then
                        pred_24h=0
                    fi
                    
                    # Add comma if not first entry
                    if [ "$first_entry" = false ]; then
                        echo "," >> "$PREDICTIONS_FILE"
                    fi
                    first_entry=false
                    
                    # Add prediction entry
                    cat >> "$PREDICTIONS_FILE" << EOF
    {
      "node_id": "$node_id",
      "user": "$user",
      "current_battery": $battery_clean,
      "solar_efficiency": $solar_efficiency,
      "predictions": {
        "6h": $pred_6h,
        "12h": $pred_12h,
        "24h": $pred_24h
      },
      "weather": {
        "condition": "unknown",
        "cloud_cover": 50,
        "temperature": 20
      }
    }
EOF
                fi
            fi
        done
    fi
    
    # Close JSON
    echo "" >> "$PREDICTIONS_FILE"
    echo "  ]" >> "$PREDICTIONS_FILE"
    echo "}" >> "$PREDICTIONS_FILE"
    
    echo "Weather predictions saved to $PREDICTIONS_FILE"
}

# Main execution
if [ "$1" = "generate" ]; then
    generate_weather_predictions "$2"
else
    echo "Usage: $0 generate <telemetry_csv_file>"
fi
