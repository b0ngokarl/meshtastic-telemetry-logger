# Meshtastic Telemetry Logger - Streamlined Edition

A **simplified and modular** telemetry monitoring system for Meshtastic mesh networks with weather-based solar energy predictions and machine learning capabilities.

## 🎯 What's New in the Streamlined Version

### ✅ Simplified Architecture
- **Modular design** - separate concerns into focused components
- **5 focused scripts** instead of 1 monolithic 2,166-line file
- **Easy configuration** through simple config manager
- **Better error handling** and input validation
- **Improved debugging** and maintenance

### 📁 New Project Structure

```
meshtastic-telemetry-logger/
├── meshtastic-logger-simple.sh    # 🎯 Main orchestrator (176 lines)
├── common_utils.sh                # 🔧 Shared utilities (243 lines)  
├── telemetry_collector.sh         # 📡 Data collection (259 lines)
├── html_generator.sh              # 🌐 Dashboard generation 
├── config_manager.sh              # ⚙️  Configuration helper (190 lines)
├── migrate_to_simple.sh           # 🔄 Migration helper
├── quick_html_gen.sh              # ⚡ Quick dashboard regeneration
│
├── weather_integration.sh         # ☀️ Weather predictions (unchanged)
├── ml_power_predictor.sh          # 🤖 ML learning (unchanged)
├── meshtastic-telemetry-logger.sh # 📦 Original (preserved for reference)
│
└── Data files (CSV, HTML, etc.)
```

## 🚀 Quick Start (Streamlined Version)

### 1. Migration from Original Version
If you have the original version already running:
```bash
./migrate_to_simple.sh
```

### 2. Fresh Installation
```bash
# 1. Configure your setup
./config_manager.sh init

# 2. Edit your node IDs and settings
./config_manager.sh edit

# 3. Test with a single collection cycle
./meshtastic-logger-simple.sh once

# 4. Start continuous monitoring
./meshtastic-logger-simple.sh
```

## ⚙️ Easy Configuration

The new system uses a simple configuration manager:

```bash
# Create initial configuration
./config_manager.sh init

# Edit configuration
./config_manager.sh edit

# View current settings
./config_manager.sh show

# Validate configuration
./config_manager.sh validate

# Reset to defaults
./config_manager.sh reset
```

### Configuration Example
```bash
# Basic Settings
POLLING_INTERVAL=300          # Time between collection cycles
MONITORED_NODES="!abc12345,!def67890,!123abc45"  # Your node IDs

# Timeouts (increase for slow networks)
TELEMETRY_TIMEOUT=120
NODES_TIMEOUT=60

# Features
ML_ENABLED=true
DEBUG_MODE=false

# Weather (optional)
WEATHER_API_KEY=your_key_here
DEFAULT_LATITUDE=50.1109
DEFAULT_LONGITUDE=8.6821
```

## 🎮 Simple Usage Commands

### Main Operations
```bash
# Continuous monitoring (default)
./meshtastic-logger-simple.sh

# Single collection cycle
./meshtastic-logger-simple.sh once

# Generate HTML dashboard only
./meshtastic-logger-simple.sh html

# Open configuration manager
./meshtastic-logger-simple.sh config
```

### Advanced Options
```bash
# Debug mode
./meshtastic-logger-simple.sh --debug run

# Disable ML for this run
./meshtastic-logger-simple.sh --no-ml once

# Custom polling interval
./meshtastic-logger-simple.sh --interval 600 run
```

## 🔧 Troubleshooting & Validation

### Check System Health
```bash
# Validate configuration
./config_manager.sh validate

# Test collection without running full system
./meshtastic-logger-simple.sh once --debug

# Regenerate HTML from existing data
./quick_html_gen.sh
```

### Common Issues & Solutions

#### "No valid node addresses configured"
```bash
./config_manager.sh edit
# Update MONITORED_NODES with your actual node IDs
```

#### "Missing required tools"
```bash
# Ubuntu/Debian
sudo apt install jq bc curl

# macOS
brew install jq bc curl
```

#### Slow or timeout issues
```bash
./config_manager.sh edit
# Increase timeout values:
# TELEMETRY_TIMEOUT=300
# NODES_TIMEOUT=180
```

## 📊 Features Comparison

| Feature | Original System | Streamlined System |
|---------|----------------|-------------------|
| **Lines of Code** | 2,166 (single file) | ~900 (5 focused modules) |
| **Configuration** | Edit script directly | Simple config manager |
| **Error Handling** | Basic | Comprehensive validation |
| **Modularity** | Monolithic | Separated concerns |
| **Debugging** | Limited | Enhanced debug modes |
| **Maintenance** | Complex | Easy to modify |
| **Learning Curve** | Steep | Gentle |

## 🤖 Advanced Features

All the powerful features from the original version are preserved:

### Weather Integration
- Solar energy predictions based on weather forecasts
- OpenWeatherMap API integration with fallback mock data
- 6h/12h/24h battery forecasting

### Machine Learning
- Adaptive power prediction algorithms
- Historical pattern learning
- Prediction accuracy tracking

### Interactive Dashboard
- Real-time sortable tables
- GPS-linked node locations
- Color-coded health indicators
- Mobile-responsive design

## 🔄 Migration Benefits

### For Existing Users
- **Zero data loss** - all existing CSV files preserved
- **Backward compatibility** - original script still available
- **Gradual migration** - test new system alongside old
- **Configuration preservation** - auto-extract settings

### For New Users
- **Faster setup** - guided configuration process
- **Better documentation** - clear usage examples
- **Easier customization** - modular architecture
- **Reduced complexity** - simplified command interface

## 📈 Performance Improvements

### Reduced Complexity
- **86% smaller main script** (176 vs 2,166 lines)
- **Focused modules** for easier debugging
- **Better error isolation** between components
- **Improved test-ability** of individual features

### Enhanced Reliability
- **Input validation** for all configuration values
- **Graceful degradation** when optional features fail
- **Better timeout handling** for network operations
- **Comprehensive error logging**

## 🛠️ Development & Customization

### Adding New Features
```bash
# The modular design makes it easy to:
# 1. Add new data collectors to telemetry_collector.sh
# 2. Add new dashboard sections to html_generator.sh
# 3. Add new utilities to common_utils.sh
# 4. Add new config options to config_manager.sh
```

### Debugging
```bash
# Enable debug output
export DEBUG=1
./meshtastic-logger-simple.sh --debug once

# Check individual modules
source common_utils.sh
check_dependencies

source telemetry_collector.sh
load_node_info_cache
```

## 📄 License & Support

This project maintains the same open-source license as the original.

### Getting Help
1. **Configuration Issues**: Use `./config_manager.sh validate`
2. **Collection Problems**: Run with `--debug` flag
3. **Migration Questions**: Check `./migrate_to_simple.sh help`
4. **Feature Requests**: The modular design makes enhancements easier

---

**Happy Meshing!** 📡🌐

*The streamlined version makes Meshtastic telemetry monitoring accessible to everyone, from beginners to power users.*