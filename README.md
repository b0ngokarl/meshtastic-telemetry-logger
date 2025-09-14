# Meshtastic Telemetry Logger with Weather Integration

A comprehensive telemetry monitoring system for Meshtastic mesh networks with advanced weather-based solar energy predictions.

## 🌟 Features

### Core Telemetry Collection
- **Automated telemetry requests** to configured Meshtastic nodes
- **Battery, voltage, and channel utilization monitoring**
- **Success/failure tracking** with retry logic
- **Persistent CSV logging** with timestamps
- **Interactive HTML dashboard** with real-time updates

### Advanced Analytics
- **Try/fail count tracking** for reliability monitoring
- **Node summary statistics** with color-coded health indicators
- **Battery trend analysis** with estimated time remaining
- **Channel utilization tracking** for network optimization

### Weather Integration
- **Weather-based solar energy predictions** for solar-powered nodes
- **6h/12h/24h battery forecasting** based on weather conditions
- **OpenWeatherMap API integration** with mock data fallback
- **Solar panel efficiency calculations** accounting for cloud coverage
- **Visual battery trend indicators** (⚡ Charging, 🔋 Stable, 📉 Draining)

### Network Activity News (🆕)
- **Real-time network change tracking** with configurable time windows
- **New node discovery** notifications
- **Lost node detection** when nodes go offline
- **Name change monitoring** (AKA updates)
- **Role change tracking** (CLIENT ↔ ROUTER mode switches)
- **Hardware change detection** and public key updates
- **Hop-distance filtering** to focus on relevant network segments

### Interactive Dashboard Features
- **GPS integration** - clickable node names open OpenStreetMap locations
- **Index numbering** for easy node counting
- **Sortable tables** for data analysis
- **Color-coded health indicators** for quick status assessment
- **Responsive design** with professional styling

## 📁 Project Structure

```
meshtastic-telemetry-logger/
├── meshtastic-telemetry-logger.sh    # Main telemetry collection script
├── weather_integration.sh            # Weather-based prediction engine
├── weather_predictions.json          # Generated weather forecast data
├── nodes_log.csv                     # Node discovery data
├── telemetry_log.csv                 # Telemetry history
├── stats.html                        # Interactive dashboard
├── error.log                         # Error logging
└── README.md                         # This documentation
```

## 🚀 Quick Start

### Prerequisites
- Meshtastic CLI installed and configured
- `jq`, `bc`, `curl` utilities
- Bash shell environment
- Optional: OpenWeatherMap API key for real weather data

### Installation
```bash
git clone <repository-url>
cd meshtastic-telemetry-logger
chmod +x meshtastic-telemetry-logger.sh weather_integration.sh
```

### Configuration
1. **Edit node addresses** in `meshtastic-telemetry-logger.sh`:
   ```bash
   MONITORED_ADDRESSES=(
       "!9eed0410"  # Your node addresses here
       "!2df67288"
       # Add more nodes...
   )
   ```

2. **Optional: Add weather API key** in `weather_integration.sh`:
   ```bash
   WEATHER_API_KEY="your_openweathermap_api_key"
   ```

### Usage
```bash
# Run full telemetry collection
./meshtastic-telemetry-logger.sh

# Generate HTML dashboard only
./meshtastic-telemetry-logger.sh --generate-html-only

# Run weather predictions independently
./weather_integration.sh

# Generate telemetry charts (with auto-detected node names)
python generate_node_chart.py              # Utilization charts (2-panel)
python generate_full_telemetry_chart.py    # Comprehensive charts (5-panel)
```

## 📈 Chart Generation (New!)

### Automatic Node Name Detection
- **No manual configuration needed** - node names automatically pulled from `nodes_log.csv`
- **Smart naming**: Combines full name + short alias (e.g., "TRUTZTURM Solar (TRZS)")
- **Works with both chart types**: utilization-focused and comprehensive telemetry

### Chart Types
1. **Utilization Charts** (`generate_node_chart.py`)
   - Channel utilization trends
   - Transmission utilization patterns
   - Perfect for network performance analysis

2. **Comprehensive Telemetry** (`generate_full_telemetry_chart.py`)
   - Battery levels over time
   - Voltage monitoring
   - Channel & transmission utilization
   - Node uptime tracking
   - Ideal for complete health monitoring

See `TELEMETRY_CHARTS.md` for detailed chart generation documentation.

## 📊 Dashboard Features

### Node Summary Statistics Table
| Column | Description |
|--------|-------------|
| Address | Node ID with clickable GPS links |
| Last Seen | Timestamp of last successful contact |
| Success/Failures | Communication reliability metrics |
| Success Rate | Percentage of successful telemetry requests |
| Battery (%) | Current battery level with health indicators |
| Voltage (V) | Battery voltage with warning thresholds |
| Channel/Tx Util | Network utilization percentages |
| Min/Max Battery | Historical battery level ranges |
| Est. Time Left | Predicted hours until battery depletion |
| **Power in 6h** | Weather-based 6-hour battery prediction |
| **Power in 12h** | Extrapolated 12-hour forecast |
| **Power in 24h** | Long-term 24-hour projection |

### Current Node List
- **Index numbers** for easy counting
- **GPS-linked usernames** (clickable to OpenStreetMap)
- **Real-time status indicators**
- **Hardware and firmware information**

### Monitored Addresses Table
- **Index numbering** for quick reference
- **GPS coordinate links** to mapping services
- **Status tracking** for configured monitoring targets

## 🌤️ Weather Integration System

### How It Works
1. **Location Detection**: Extracts GPS coordinates from node data
2. **Weather API Calls**: Fetches forecasts from OpenWeatherMap
3. **Solar Calculations**: Estimates charging efficiency based on:
   - Cloud coverage percentages
   - Weather conditions (Clear, Clouds, Rain)
   - Time of day and solar angle
4. **Battery Modeling**: Projects battery levels using:
   - Current battery percentage
   - Historical drain patterns
   - Weather-adjusted solar input
   - Configurable panel wattage and efficiency

### Prediction Algorithm
```bash
# Solar generation calculation
solar_efficiency = base_efficiency * (1 - cloud_coverage/100) * weather_modifier
estimated_charging = solar_watts * solar_efficiency * time_hours
battery_change = estimated_charging - typical_drain_rate
future_battery = current_battery + battery_change
```

### Weather Data Sources
- **Primary**: OpenWeatherMap API (requires free key)
- **Fallback**: Generated mock weather data for demonstration
- **Caching**: 1-hour cache to minimize API calls

## 🎯 Color-Coded Health Indicators

### Battery Levels
- 🟢 **Good (>50%)**: Green background
- 🟡 **Warning (20-50%)**: Orange background  
- 🔴 **Critical (<20%)**: Red background

### Channel Utilization
- 🟢 **Normal (<25%)**: Standard display
- 🟡 **High (25-50%)**: Orange warning
- 🔴 **Very High (>50%)**: Red critical

### Success Rates
- 🟢 **Good (>90%)**: Reliable communication
- 🟡 **Warning (70-90%)**: Occasional issues
- 🔴 **Critical (<70%)**: Frequent failures

## 🔧 Advanced Configuration

### Solar Panel Settings
Edit `weather_integration.sh`:
```bash
SOLAR_PANEL_WATTS=5        # Panel wattage
BATTERY_CAPACITY_MAH=18650 # Battery capacity
CONVERSION_EFFICIENCY=0.85  # Charging efficiency
```

### Telemetry Intervals
Edit `meshtastic-telemetry-logger.sh`:
```bash
RETRY_DELAY=30    # Seconds between retries
TIMEOUT=25        # Request timeout
```

### Weather Cache Settings
```bash
WEATHER_CACHE_DURATION=3600  # Cache duration (seconds)
```

### Chart Generation (via .env file)
```bash
# Nodes to include in charts (auto-updates names from nodes_log.csv)
CHART_NODES="!9eed0410,!2c9e092b,!849c4818"

# Optional: Override auto-detected names
CHART_NODE_NAMES="Custom Name 1,Custom Name 2,Custom Name 3"
```

## 📈 Development History

### Phase 1: Basic Telemetry (Initial Implementation)
- ✅ Node discovery and telemetry collection
- ✅ CSV logging with timestamps
- ✅ Basic HTML report generation
- ✅ Error handling and retry logic

### Phase 2: Enhanced Analytics (Feature Expansion)
- ✅ Try/fail count tracking for reliability metrics
- ✅ Success rate calculations with color coding
- ✅ Battery trend analysis and time estimation
- ✅ Advanced health indicators

### Phase 3: Interactive Features (UX Improvements)
- ✅ Index numbering for easy node counting
- ✅ GPS integration with OpenStreetMap links
- ✅ Clickable usernames for location viewing
- ✅ Enhanced table styling and responsiveness

### Phase 4: Weather Integration (AI-Powered Predictions)
- ✅ OpenWeatherMap API integration
- ✅ Solar energy calculation algorithms
- ✅ Weather-based battery forecasting
- ✅ 6h/12h/24h prediction timeline
- ✅ Visual trend indicators and smart fallbacks

## 🛠️ Technical Implementation

### Key Technologies
- **Bash scripting** for system integration
- **Meshtastic CLI** for device communication
- **jq** for JSON processing
- **bc** for mathematical calculations
- **HTML/CSS/JavaScript** for dashboard
- **OpenWeatherMap API** for weather data

### Data Flow
```
Meshtastic Nodes → CLI Requests → CSV Logging → Weather API → 
Prediction Engine → JSON Output → HTML Dashboard → Browser Display
```

### Error Handling
- **Timeout management** for unresponsive nodes
- **Retry logic** with exponential backoff
- **Graceful degradation** when weather data unavailable
- **Input validation** for coordinates and battery values
- **Comprehensive logging** to error.log

## 🚀 Next Steps & Future Enhancements

### Short-term Improvements (Next Iteration)
1. **Real-time Updates**
   - WebSocket integration for live dashboard updates
   - Auto-refresh functionality without page reload
   - Push notifications for critical battery levels

2. **Enhanced Weather Features**
   - Multiple weather provider support (AccuWeather, Weather.gov)
   - Seasonal solar angle calculations
   - Temperature impact on battery performance
   - Historical weather pattern analysis

3. **Advanced Analytics**
   - Machine learning for battery prediction accuracy
   - Network topology mapping
   - Signal strength correlation analysis
   - Predictive maintenance alerts

### Medium-term Features (Future Releases)
1. **Database Integration**
   - SQLite backend for better data management
   - Historical trend visualization
   - Data export capabilities
   - Backup and restore functionality

2. **Mobile Application**
   - React Native or Flutter mobile app
   - Push notifications for alerts
   - Offline capability
   - GPS tracking for mobile nodes

3. **Multi-Network Support**
   - Support for multiple Meshtastic networks
   - Cross-network communication analysis
   - Regional network health dashboards
   - Mesh routing optimization

### Long-term Vision (Advanced Features)
1. **AI-Powered Optimization**
   - Neural network battery prediction models
   - Automatic solar panel angle recommendations
   - Intelligent retry algorithms
   - Anomaly detection and alerts

2. **Enterprise Features**
   - Multi-user authentication and roles
   - API endpoints for third-party integration
   - Custom alerting and notification systems
   - Advanced reporting and analytics

3. **IoT Integration**
   - Smart home integration (Home Assistant, etc.)
   - Environmental sensor correlation
   - Automated solar panel positioning
   - Remote node management capabilities

## 🧹 Maintenance & Cleanup

### Log Management
```bash
# Rotate logs when they get too large
if [ $(stat -f%z telemetry_log.csv 2>/dev/null || stat -c%s telemetry_log.csv) -gt 10485760 ]; then
    mv telemetry_log.csv telemetry_log_backup.csv
fi
```

### Cache Cleanup
```bash
# Clean old weather cache files
find weather_cache/ -name "*.json" -mtime +1 -delete
```

### Performance Optimization
- Monitor CSV file sizes and implement rotation
- Clean up temporary files in /tmp
- Optimize weather cache hit rates
- Profile script execution times

## 📝 Contributing

### Development Guidelines
1. **Follow existing code style** and commenting patterns
2. **Test with mock data** before implementing API calls
3. **Maintain backward compatibility** with existing CSV formats
4. **Document new features** in README and code comments
5. **Use meaningful commit messages** describing changes

### Bug Reports
Include the following information:
- Meshtastic CLI version
- Operating system and shell version
- Error logs from error.log
- Steps to reproduce the issue
- Expected vs actual behavior

## 📄 License

This project is open source. Please check the repository for license details.

## 🙏 Acknowledgments

- **Meshtastic Project** for the excellent mesh networking platform
- **OpenWeatherMap** for weather API services
- **Community Contributors** for feature requests and testing

---

**Happy Meshing!** 📡🌐

*For support and questions, please check the issues section of the repository.*
- `stats.html` - Statistics and last results
- `error.log` - Any errors encountered

## Customization

- Add more addresses to the `ADDRESSES` array
- Adjust interval as desired

## License

MIT