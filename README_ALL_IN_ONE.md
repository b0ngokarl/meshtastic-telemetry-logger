# Meshtastic Telemetry Logger - All-in-One Version

This is a consolidated, all-in-one version of the Meshtastic Telemetry Logger that combines all functionality into a single, well-organized Python script.

## Features Consolidated

✅ **All original features preserved:**
- Telemetry collection from Meshtastic nodes
- Weather-based solar energy predictions  
- Machine learning battery life predictions
- Interactive HTML dashboard generation
- Node discovery and GPS integration
- Historical data analysis and trends
- Real-time health monitoring

✅ **Simplified deployment:**
- Single Python script (`meshtastic-all-in-one.py`)
- Self-contained with minimal dependencies
- Easy configuration through `.env` file
- Clear command-line interface

## Quick Start

1. **Run the script to create configuration:**
   ```bash
   python3 meshtastic-all-in-one.py config
   ```

2. **Edit the `.env` file to set your node addresses:**
   ```bash
   nano .env
   # Update MONITORED_NODES with your actual node IDs
   ```

3. **Run single collection cycle:**
   ```bash
   python3 meshtastic-all-in-one.py once
   ```

4. **Run continuous monitoring:**
   ```bash
   python3 meshtastic-all-in-one.py run
   ```

5. **Generate dashboard from existing data:**
   ```bash
   python3 meshtastic-all-in-one.py html
   ```

## Dependencies

The script requires these system commands:
- `meshtastic` - Install with: `pip install meshtastic`
- `jq` - JSON processor
- `bc` - Calculator (for shell fallback calculations)
- `curl` - For weather API calls

On Ubuntu/Debian:
```bash
sudo apt update
sudo apt install jq bc curl
pip install meshtastic
```

## Command Reference

```bash
# Show help
python3 meshtastic-all-in-one.py --help

# Run with debug output
python3 meshtastic-all-in-one.py --debug run

# Override polling interval
python3 meshtastic-all-in-one.py --interval 600 once

# Available commands:
# run    - Continuous collection (default)
# once   - Single collection cycle
# html   - Generate dashboard only
# config - Create configuration file
```

## Configuration

All settings are managed through the `.env` file:

```env
# Basic Settings
POLLING_INTERVAL=300          # Time between cycles (seconds)
DEBUG_MODE=false              # Enable debug output

# Node Monitoring - YOUR NODE IDs HERE
MONITORED_NODES="!9eed0410,!2c9e092b,!849c4818"

# Weather Integration (optional)
WEATHER_API_KEY=              # OpenWeatherMap API key
DEFAULT_LATITUDE=50.1109      # Your location
DEFAULT_LONGITUDE=8.6821      # Your location

# Timeouts
TELEMETRY_TIMEOUT=120         # Node telemetry timeout
NODES_TIMEOUT=60              # Node discovery timeout
```

## Files Created

- `telemetry_log.csv` - Historical telemetry data
- `nodes_log.csv` - Discovered nodes database  
- `stats.html` - Interactive dashboard
- `power_predictions.csv` - ML predictions log
- `weather_cache/` - Weather data cache directory

## Migration from Modular Version

If you're migrating from the previous modular version:

1. Your existing data files (CSV) are compatible
2. Copy your `.env` configuration or recreate it
3. The all-in-one script provides identical functionality
4. All features and capabilities are preserved

## Advantages of All-in-One Version

✅ **Simplified Deployment**
- Single file to manage and deploy
- No complex dependencies between modules
- Clear execution order and flow

✅ **Better Error Handling**
- Centralized error logging
- Graceful degradation when components fail
- Clear status reporting

✅ **Optimized Performance**
- Reduced I/O operations
- Better memory management
- Streamlined data processing

✅ **Easier Maintenance**
- Single script to update and debug
- Consistent coding style throughout
- Simplified testing and validation

## Feature Comparison

| Feature | Original Modular | All-in-One |
|---------|------------------|-------------|
| Telemetry Collection | ✅ | ✅ |
| HTML Dashboard | ✅ | ✅ |
| Weather Predictions | ✅ | ✅ |
| ML Power Predictions | ✅ | ✅ |
| Node Discovery | ✅ | ✅ |
| GPS Integration | ✅ | ✅ |
| Configuration | Multiple files | Single .env |
| Deployment | ~10 files | 1 file |
| Dependencies | External modules | Self-contained |
| Maintenance | Complex | Simple |

## Execution Flow

The all-in-one script follows this optimized execution order:

1. **Configuration Loading** - Read settings from .env
2. **Dependency Checking** - Verify required tools
3. **File Initialization** - Create CSV files and directories
4. **Telemetry Collection** - Sequential node polling
5. **Node Discovery** - Update network topology
6. **Weather Integration** - Fetch forecast data
7. **ML Analysis** - Generate power predictions
8. **Dashboard Generation** - Create interactive HTML
9. **Status Reporting** - Log results and errors

This ensures optimal data flow and minimizes redundant operations.

## Support

The all-in-one version maintains full compatibility with existing data and provides identical functionality to the modular version, while offering significant advantages in simplicity and maintainability.

For issues or feature requests, please check the repository issues section.