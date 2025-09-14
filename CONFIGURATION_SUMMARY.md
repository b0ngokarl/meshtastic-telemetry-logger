# Configuration Summary

All configurable options in the Meshtastic Telemetry Logger are now centralized in the `.env` file. This document provides a comprehensive overview of all available configuration options.

## How to Use Configuration

1. **View current configuration**: `./config_manager.sh show`
2. **Edit configuration**: `./config_manager.sh edit`
3. **Initialize default config**: `./config_manager.sh init`

## Configuration Categories

### 📡 Connection Settings
- **MESHTASTIC_CONNECTION_TYPE**: Connection method (serial, tcp, ble)
- **MESHTASTIC_SERIAL_PORT**: Serial port path (auto-detect or specific)
- **MESHTASTIC_TCP_HOST**: TCP/IP address for network connections
- **MESHTASTIC_TCP_PORT**: TCP port (default: 4403)
- **MESHTASTIC_BLE_ADDRESS**: Bluetooth MAC address
- **CONNECTION_TIMEOUT**: Connection timeout in seconds
- **MAX_RETRIES**: Maximum connection retry attempts
- **RETRY_INTERVAL**: Wait time before retrying failed operations

### ⏱️ Timing & Intervals
- **POLLING_INTERVAL**: Time between data collection cycles
- **TELEMETRY_TIMEOUT**: Timeout for telemetry requests
- **NODES_TIMEOUT**: Timeout for node discovery
- **WEATHER_TIMEOUT**: Timeout for weather API calls
- **ML_TIMEOUT**: Timeout for machine learning processing

### 📊 Chart Configuration
- **CHART_FIGSIZE_WIDTH**: Chart width in inches
- **CHART_FIGSIZE_HEIGHT**: Chart height in inches
- **CHART_DPI**: Chart resolution (dots per inch)
- **CHART_SIZE_MULTIPLIER**: Overall size scaling factor

### 🤖 Machine Learning Settings
- **ML_HISTORICAL_WINDOW**: Number of historical records for ML training
- **ML_MIN_DATA_POINTS**: Minimum data points required for predictions
- **ML_LEARNING_RATE**: Learning rate for ML algorithms
- **ML_ENABLED**: Enable/disable ML features

### 🌤️ Weather Integration
- **WEATHER_API_KEY**: OpenWeatherMap API key
- **WEATHER_CACHE_TTL**: Weather data cache time-to-live
- **DEFAULT_LATITUDE**: Default location latitude
- **DEFAULT_LONGITUDE**: Default location longitude

### 📝 Logging & Data Management
- **LOG_LEVEL**: Logging verbosity (DEBUG, INFO, WARNING, ERROR)
- **LOG_TELEMETRY_REQUESTS**: Log individual telemetry requests
- **LOG_TO_FILE**: Enable file logging
- **ERROR_LOG**: Error log filename
- **DEBUG_MODE**: Enable debug output
- **QUIET**: Suppress non-essential output

### 🗂️ Data Retention
- **MAX_TELEMETRY_DAYS**: Maximum age for telemetry data
- **MAX_LOG_SIZE_MB**: Maximum log file size before rotation
- **BACKUP_OLD_DATA**: Enable automatic data backup
- **AUTO_BACKUP**: Enable automatic backups
- **BACKUP_RETENTION_DAYS**: Days to retain backup files

### 📁 File Paths
- **TELEMETRY_LOG**: Telemetry data CSV filename
- **NODES_LOG**: Node information CSV filename
- **STATS_HTML**: Statistics HTML output filename
- **WEATHER_CACHE_DIR**: Weather cache directory

### 🎯 Node Configuration
- **MONITORED_NODES**: List of node IDs to monitor
- **CHART_NODES**: Nodes to include in charts
- **CHART_NODE_NAMES**: Custom names for chart display

## Configuration Migration

All previously hardcoded values have been moved to the `.env` file:

### Scripts Updated
- ✅ `generate_full_telemetry_chart.py` - Chart dimensions and DPI
- ✅ `generate_node_chart.py` - Chart dimensions  
- ✅ `ml_power_predictor.sh` - Historical data window
- ✅ `meshtastic-all-in-one.py` - Timeouts and retry intervals
- ✅ `config_manager.sh` - Enhanced configuration display

### Benefits of Centralized Configuration

1. **Single Source of Truth**: All settings in one file
2. **Easy Customization**: Change behavior without editing code
3. **Environment-Specific**: Different configs for different deployments
4. **Documentation**: All options documented with comments
5. **Validation**: Built-in configuration validation
6. **Version Control**: Easy to track configuration changes

## Configuration Files

- **`.env`**: Active configuration (not in git)
- **`.env.example`**: Template with default values and documentation
- **`config_manager.sh`**: Configuration management utility

## Quick Start

```bash
# Copy example configuration
cp .env.example .env

# Edit configuration for your setup
./config_manager.sh edit

# View current configuration
./config_manager.sh show

# Validate configuration
./config_manager.sh validate
```

All configuration options now use sensible defaults, so the system works out-of-the-box while still being highly customizable for advanced users.