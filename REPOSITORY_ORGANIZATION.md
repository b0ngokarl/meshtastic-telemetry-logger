# Repository Organization

This document describes the current organization and purpose of files in the repository.

## 📁 Core Components

### Main Scripts
- **`meshtastic-telemetry-logger.sh`** - Primary telemetry collection and dashboard generation
- **`weather_integration.sh`** - Weather data integration and predictions
- **`ml_power_predictor.sh`** - Machine learning power predictions

### Chart Generation
- **`generate_node_chart.py`** - Utilization-focused charts (channel & transmission)
- **`generate_full_telemetry_chart.py`** - Comprehensive telemetry charts (5-panel)
- **`update_chart_names.py`** - Automatic node name detection utility

## 📊 Data Files
- **`nodes_log.csv`** - Node information database (auto-generated)
- **`telemetry_log.csv`** - Telemetry data history (auto-generated)
- **`stats.html`** - Interactive dashboard (auto-generated)
- **`weather_predictions.json`** - Weather forecast cache (auto-generated)

## 📚 Documentation
- **`README.md`** - Main project documentation
- **`TELEMETRY_CHARTS.md`** - Chart generation guide
- **`CONFIGURATION.md`** - Setup and configuration instructions
- **`OPTIMIZATIONS.md`** - Performance optimization details
- **`PERFORMANCE_SUMMARY.md`** - Performance analysis results

## ⚙️ Configuration
- **`.env`** - Local configuration (ignored by git)
- **`.env.example`** - Configuration template
- **`.gitignore`** - Git ignore rules

## 🗂️ Generated Files (Auto-ignored)
- Chart files: `*_chart.png`, `*_chart.svg`
- Log files: `error.log`, `nodes_log.txt`
- Test outputs: `test_*.html`

## 🧹 Cleanup History
- **2025-09-13**: Removed redundant documentation files
- **2025-09-13**: Consolidated chart generation features
- **2025-09-13**: Enhanced .gitignore for generated files
- **2025-09-13**: Removed legacy test scripts and generated chart files

## 🚮 Removed Files
- `CHART_USAGE.md` → Consolidated into `TELEMETRY_CHARTS.md`
- `NODE_NAME_AUTOMATION.md` → Information integrated into main documentation
- `generate_trutzturm_chart.py` → Superseded by generic chart generators
- Various `test_*.sh` files → Empty or obsolete test scripts
- Generated chart files → Now properly gitignored

## 📋 File Count Summary
- **Core Scripts**: 3 main + 3 chart generators
- **Documentation**: 5 focused documents  
- **Configuration**: 2 files (.env + example)
- **Auto-generated**: Data files and outputs (gitignored)

This organization provides a clean, maintainable structure focused on the core functionality.