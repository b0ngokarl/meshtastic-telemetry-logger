#!/bin/bash

# Weather Integration for Meshtastic Telemetry Logger
# Provides weather-based solar energy predictions for nodes

# Configuration
WEATHER_API_KEY=""  # Get free API key from openweathermap.org
WEATHER_CACHE_DIR="weather_cache"
WEATHER_CACHE_DURATION=3600  # 1 hour in seconds
PREDICTIONS_FILE="weather_predictions.json"

# Solar panel efficiency factors (adjustable based on your setup)
SOLAR_PANEL_WATTS=5  # Typical small solar panel wattage
BATTERY_CAPACITY_MAH=18650  # Typical 18650 battery
CONVERSION_EFFICIENCY=0.85  # Solar charging efficiency

# Create weather cache directory
mkdir -p "$WEATHER_CACHE_DIR"

# Function to get weather data for coordinates
get_weather_data() {
    local lat="$1"
    local lon="$2"
    local cache_file="${WEATHER_CACHE_DIR}/weather_${lat}_${lon}.json"
    
    # Check if cached data exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        if [[ $cache_age -lt $WEATHER_CACHE_DURATION ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Fetch fresh weather data
    if [[ -n "$WEATHER_API_KEY" ]]; then
        local weather_url="https://api.openweathermap.org/data/2.5/forecast?lat=${lat}&lon=${lon}&appid=${WEATHER_API_KEY}&units=metric"
        if curl -s "$weather_url" > "$cache_file"; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Fallback: generate mock weather data for demonstration
    generate_mock_weather "$lat" "$lon" > "$cache_file"
    cat "$cache_file"
}

# Generate mock weather data for demonstration purposes
generate_mock_weather() {
    local lat="$1"
    local lon="$2"
    local current_hour=$(date +%H)
    
    cat << EOF
{
    "list": [
        {
            "dt": $(date +%s),
            "main": {"temp": $((15 + RANDOM % 15))},
            "weather": [{"main": "$([ $((RANDOM % 3)) -eq 0 ] && echo "Clouds" || echo "Clear")", "description": "scattered clouds"}],
            "clouds": {"all": $((RANDOM % 100))},
            "dt_txt": "$(date '+%Y-%m-%d %H:00:00')"
        },
        {
            "dt": $(($(date +%s) + 10800)),
            "main": {"temp": $((15 + RANDOM % 15))},
            "weather": [{"main": "$([ $((RANDOM % 4)) -eq 0 ] && echo "Rain" || echo "Clear")", "description": "light rain"}],
            "clouds": {"all": $((RANDOM % 100))},
            "dt_txt": "$(date -d '+3 hours' '+%Y-%m-%d %H:00:00')"
        },
        {
            "dt": $(($(date +%s) + 21600)),
            "main": {"temp": $((15 + RANDOM % 15))},
            "weather": [{"main": "$([ $((RANDOM % 3)) -eq 0 ] && echo "Clouds" || echo "Clear")", "description": "clear sky"}],
            "clouds": {"all": $((RANDOM % 100))},
            "dt_txt": "$(date -d '+6 hours' '+%Y-%m-%d %H:00:00')"
        }
    ]
}
EOF
}

# Calculate solar generation potential based on weather
calculate_solar_generation() {
    local weather_condition="$1"
    local cloud_coverage="$2"
    local hour="$3"
    local temperature="$4"
    
    # Base solar efficiency (0-1 scale)
    local base_efficiency=1.0
    
    # Adjust for weather conditions
    case "$weather_condition" in
        "Clear"|"Sunny") base_efficiency=1.0 ;;
        "Clouds") base_efficiency=0.7 ;;
        "Rain"|"Drizzle") base_efficiency=0.3 ;;
        "Snow") base_efficiency=0.2 ;;
        "Thunderstorm") base_efficiency=0.1 ;;
        *) base_efficiency=0.8 ;;
    esac
    
    # Adjust for cloud coverage (0-100%)
    local cloud_factor=$(echo "scale=2; 1 - ($cloud_coverage / 100) * 0.5" | bc)
    
    # Adjust for time of day (simplified sun angle)
    local hour_factor=0
    if [[ $hour -ge 6 && $hour -le 18 ]]; then
        # Simplified solar curve: peak at noon, reduced at morning/evening
        if [[ $hour -ge 10 && $hour -le 14 ]]; then
            hour_factor=1.0
        elif [[ $hour -ge 8 && $hour -le 16 ]]; then
            hour_factor=0.8
        else
            hour_factor=0.4
        fi
    fi
    
    # Temperature derating (solar panels lose efficiency when hot)
    local temp_factor=1.0
    if [[ $(echo "$temperature > 25" | bc) -eq 1 ]]; then
        temp_factor=$(echo "scale=2; 1 - (($temperature - 25) * 0.004)" | bc)
    fi
    
    # Calculate final generation percentage
    local generation=$(echo "scale=2; $base_efficiency * $cloud_factor * $hour_factor * $temp_factor" | bc)
    echo "$generation"
}

# Predict battery level changes
predict_battery_level() {
    local current_battery="$1"
    local current_voltage="$2"
    local weather_data="$3"
    local node_id="$4"
    
    # Parse current battery level
    if [[ "$current_battery" == "Powered" ]]; then
        echo "Powered (No prediction needed)"
        return
    fi
    
    # Extract numeric battery percentage
    local battery_percent=$(echo "$current_battery" | grep -o '[0-9]\+' | head -1)
    if [[ -z "$battery_percent" ]]; then
        echo "Unknown battery level"
        return
    fi
    
    # Calculate energy consumption (rough estimate)
    local hourly_consumption=2  # Rough estimate: 2% per hour for typical usage
    
    local predictions=""
    local current_level=$battery_percent
    
    # Process weather forecast (3 time periods)
    for i in 0 1 2; do
        local forecast=$(echo "$weather_data" | jq -r ".list[$i] // empty")
        if [[ -z "$forecast" ]]; then
            break
        fi
        
        local weather_main=$(echo "$forecast" | jq -r '.weather[0].main // "Clear"')
        local cloud_coverage=$(echo "$forecast" | jq -r '.clouds.all // 20')
        local temperature=$(echo "$forecast" | jq -r '.main.temp // 20')
        local forecast_time=$(echo "$forecast" | jq -r '.dt_txt // ""')
        local hour=$(date -d "$forecast_time" +%H 2>/dev/null || echo "12")
        
        # Calculate solar generation for this period
        local solar_gen=$(calculate_solar_generation "$weather_main" "$cloud_coverage" "$hour" "$temperature")
        
        # Estimate energy gain from solar (rough calculation)
        local solar_gain=$(echo "scale=1; $solar_gen * 8" | bc)  # Up to 8% gain per 3-hour period
        
        # Calculate net battery change
        local net_change=$(echo "scale=1; $solar_gain - ($hourly_consumption * 3)" | bc)
        current_level=$(echo "scale=0; $current_level + $net_change" | bc)
        
        # Constrain between 0-100%
        if [[ $(echo "$current_level < 0" | bc) -eq 1 ]]; then
            current_level=0
        elif [[ $(echo "$current_level > 100" | bc) -eq 1 ]]; then
            current_level=100
        fi
        
        local time_label
        case $i in
            0) time_label="+3h" ;;
            1) time_label="+6h" ;;
            2) time_label="+9h" ;;
        esac
        
        local status_icon="📊"
        if [[ $(echo "$net_change > 0" | bc) -eq 1 ]]; then
            status_icon="⚡"  # Charging
        elif [[ $(echo "$net_change < -3" | bc) -eq 1 ]]; then
            status_icon="🔋"  # Draining fast
        else
            status_icon="📉"  # Slow drain
        fi
        
        predictions+="$time_label: ${current_level}% $status_icon ($weather_main, ${cloud_coverage}% clouds) | "
    done
    
    echo "${predictions%% | }"
}

# Generate weather report for all nodes with GPS coordinates
generate_weather_report() {
    local nodes_csv="$1"
    local telemetry_csv="$2"
    local output_file="$3"
    
    echo "Generating weather-based energy predictions..."
    
    # Start JSON output
    cat > "$output_file" << EOF
{
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "predictions": [
EOF
    
    local first_entry=true
    
    # Read nodes with GPS coordinates
    tail -n +2 "$nodes_csv" | while IFS=',' read -r user id aka hardware pubkey role latitude longitude altitude battery channel_util tx_air_util snr hops channel lastheard since; do
        # Clean up the fields (remove quotes if present)
        user=$(echo "$user" | sed 's/^"//;s/"$//')
        id=$(echo "$id" | sed 's/^"//;s/"$//')
        latitude=$(echo "$latitude" | sed 's/^"//;s/"$//;s/°//')
        longitude=$(echo "$longitude" | sed 's/^"//;s/"$//;s/°//')
        
        # Skip nodes without GPS coordinates
        if [[ "$latitude" == "N/A" || "$longitude" == "N/A" || -z "$latitude" || -z "$longitude" ]]; then
            continue
        fi
        
        # Skip invalid coordinates
        if [[ "$latitude" == "0.0" || "$longitude" == "0.0" ]]; then
            continue
        fi
        
        # Validate coordinates are numeric
        if ! [[ "$latitude" =~ ^-?[0-9]+\.?[0-9]*$ ]] || ! [[ "$longitude" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            continue
        fi
        
        # Get latest telemetry data for this node
        local latest_telemetry=$(grep -F ",$id," "$telemetry_csv" | tail -1)
        local current_battery="Unknown"
        local current_voltage="Unknown"
        
        if [[ -n "$latest_telemetry" ]]; then
            current_battery=$(echo "$latest_telemetry" | cut -d',' -f4)
            current_voltage=$(echo "$latest_telemetry" | cut -d',' -f5)
        fi
        
        # Get weather data for this location
        local weather_data=$(get_weather_data "$latitude" "$longitude")
        
        # Generate prediction
        local prediction=$(predict_battery_level "$current_battery" "$current_voltage" "$weather_data" "$id")
        
        # Add to JSON output
        if [[ "$first_entry" != "true" ]]; then
            echo "," >> "$output_file"
        fi
        first_entry=false
        
        cat >> "$output_file" << EOF
        {
            "node_id": "$id",
            "user": "$(echo "$user" | sed 's/"/\\"/g')",
            "location": {
                "latitude": $latitude,
                "longitude": $longitude
            },
            "current_battery": "$current_battery",
            "prediction": "$prediction",
            "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        }
EOF
    done
    
    # Close JSON
    cat >> "$output_file" << 'EOF'
    ]
}
EOF
    
    echo "Weather predictions saved to $output_file"
}

# Main execution
main() {
    local nodes_csv="${1:-nodes_log.csv}"
    local telemetry_csv="${2:-telemetry_log.csv}"
    local output_file="${3:-$PREDICTIONS_FILE}"
    
    if [[ ! -f "$nodes_csv" ]]; then
        echo "Error: Nodes CSV file not found: $nodes_csv"
        exit 1
    fi
    
    if [[ ! -f "$telemetry_csv" ]]; then
        echo "Error: Telemetry CSV file not found: $telemetry_csv"
        exit 1
    fi
    
    # Check for required tools
    if ! command -v jq &> /dev/null; then
        echo "Warning: jq not found. Installing jq for JSON processing..."
        sudo apt update && sudo apt install -y jq
    fi
    
    if ! command -v bc &> /dev/null; then
        echo "Warning: bc not found. Installing bc for calculations..."
        sudo apt update && sudo apt install -y bc
    fi
    
    echo "Starting weather integration for solar energy predictions..."
    echo "Note: Set WEATHER_API_KEY for real weather data (currently using mock data)"
    
    generate_weather_report "$nodes_csv" "$telemetry_csv" "$output_file"
    
    echo "Weather integration complete!"
    echo "Generated predictions: $output_file"
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
