# GitHub Copilot Instructions for Meshtastic Telemetry Logger

## Project Overview

This is a comprehensive **Meshtastic telemetry monitoring system** that collects device data, integrates weather forecasting for solar power predictions, generates interactive visualizations, and provides network topology analysis. The system is built with modular bash scripts, Python analytics engines, and modern HTML dashboards.

### Core Architecture

```
Meshtastic Devices → CLI Commands → Data Collection → Analysis → Visualization
                                        ↓
                     CSV Logs ← Weather API ← ML Predictions → HTML Dashboard
```

## Development Philosophy & Patterns

### 1. Modular Design
- **Core principle**: Each script has a single responsibility
- **Common utilities**: Shared functions live in `common_utils.sh` 
- **Sourcing pattern**: Scripts source dependencies with `source "$SCRIPT_DIR/common_utils.sh"`
- **Function isolation**: Major features get their own modules (e.g., `weather_integration.sh`, `html_generator.sh`)

### 2. Configuration Management
- **Single source**: All configuration in `.env` file
- **Environment variables**: Use `${VAR_NAME:-default_value}` pattern consistently
- **Config loading**: Use `load_config()` function from `common_utils.sh`
- **Security**: Never commit `.env` files; always use `.env.example` templates

### 3. Data Flow Patterns
- **CSV as primary storage**: Append-only logs with consistent headers
- **Sequential processing**: Meshtastic CLI requires exclusive access - no parallel commands
- **Caching strategies**: Node info cached to reduce API calls
- **Error handling**: Always check command success and provide fallbacks

## Essential Knowledge for AI Agents

### Critical Files & Their Purposes

#### Core Scripts
- **`meshtastic-telemetry-logger.sh`** (885 lines) - Main orchestrator with sequential telemetry collection
- **`common_utils.sh`** (301 lines) - Shared utility functions (debug, formatting, validation)
- **`html_generator.sh`** (2425 lines) - HTML dashboard generation with modern responsive design
- **`traceroute_collector.sh`** (283 lines) - Network topology mapping with bidirectional routes

#### Configuration & Management
- **`.env`** - Single configuration file for all settings
- **`config_manager.sh`** - Interactive configuration helper
- **`CONFIGURATION.md`** - Setup documentation with security guidelines

#### Analytics & Visualization
- **`weather_integration.sh`** (487 lines) - Solar power predictions with astronomical calculations
- **`network_news_analyzer.py`** (442 lines) - Network change detection and activity reporting
- **`generate_full_telemetry_chart.py`** - Comprehensive charting with multiple visualizations
- **`auto_chart_embedder.py`** - Automatic chart embedding in HTML dashboards

### Key Data Structures

#### CSV Schema Patterns
```bash
# Telemetry CSV: timestamp,node_id,status,battery,voltage,channel_util,air_util,uptime,lat,lon,alt,sats,last_heard
# Nodes CSV: NodeID,ShortName,LongName,AKA,LastHeard,Since,Role,Position,Battery,Voltage,Hops
# Traceroute CSV: timestamp,from_node,to_node,route_path,signal_strengths,total_hops
```

#### Configuration Variables
```bash
# Essential variables every script should respect:
MONITORED_NODES="!node1,!node2"     # Comma-separated node IDs
POLLING_INTERVAL=300                 # Collection frequency
DEBUG_MODE=false                     # Verbose logging
WEATHER_API_KEY=xxx                  # For solar predictions
ML_ENABLED=true                      # Machine learning features
```

### Meshtastic CLI Integration

#### Critical Constraints
- **Exclusive access required**: Never run parallel `meshtastic` commands
- **Connection types**: `--serial`, `--tcp`, `--ble-url` (mutually exclusive)
- **Command patterns**: Always check exit codes and parse JSON output
- **Timeout handling**: Use `timeout` command wrapper for reliability

#### Common Command Patterns
```bash
# Telemetry collection
meshtastic --info --json | jq -r '.nodes[]'

# Node information
meshtastic --nodes --json

# Traceroute (requires node ID without quotes)
meshtastic --traceroute ${node_id}
```

### Function Architecture

#### Naming Conventions
- **Utilities**: `snake_case` with descriptive verbs (`load_node_info_cache`, `parse_traceroute_output`)
- **Generators**: `generate_*` for output creation (`generate_stats_html`, `generate_network_topology`)
- **Processors**: `run_*` for main execution (`run_telemetry_sequential`, `run_traceroute`)
- **Helpers**: `get_*` and `compute_*` for data retrieval (`get_ml_predictions`, `compute_telemetry_stats`)

#### Error Handling Patterns
```bash
# Standard error checking
if ! command_that_might_fail; then
    debug_log "ERROR: Command failed"
    return 1
fi

# Timeout wrapper for external commands
if ! timeout 30 meshtastic --info; then
    log_error "Meshtastic command timed out"
fi
```

#### Debug & Logging Standards
```bash
# Use debug_log for troubleshooting (controlled by DEBUG_MODE)
debug_log "Processing node: $node_id"

# Use log_error for actual problems
log_error "Failed to parse weather data for $location"

# Timestamp everything
echo "$(iso8601_date): Status update" >> "$LOG_FILE"
```

### Data Processing Patterns

#### CSV Manipulation
```bash
# Always handle headers properly
echo "timestamp,node_id,status,data" > "$CSV_FILE"

# Use awk for complex processing
awk -F',' 'NR>1 {process_data($0)}' "$CSV_FILE"

# Validate before writing
if is_valid_node_id "$node_id"; then
    echo "$data" >> "$CSV_FILE"
fi
```

#### Node Name Resolution
```bash
# Priority order: AKA → LongName → ShortName → NodeID
get_node_display_name() {
    local node_id="$1"
    # Check AKA field first (user-friendly names)
    # Fall back to LongName, then ShortName
    # Last resort: show NodeID
}
```

### Weather Integration & ML

#### Solar Power Prediction Flow
1. **Node coordinates** → **Weather API** → **Solar efficiency calculations**
2. **Historical battery data** → **ML model** → **Power consumption predictions**
3. **Combined data** → **6h/12h/24h forecasts** → **Dashboard visualization**

#### Weather API Patterns
```bash
# Cache weather data (1-hour TTL)
WEATHER_CACHE_DIR="/tmp/weather_cache"
weather_cache_file="weather_${lat}_${lon}.json"

# Always validate coordinates
if ! is_valid_coordinate "$lat" "$lon"; then
    use_default_location
fi
```

## Development Workflows

### Adding New Features

1. **Create modular script** in project root
2. **Add common utilities** sourcing: `source "$SCRIPT_DIR/common_utils.sh"`
3. **Update configuration** in `.env.example` with new variables
4. **Integrate with main loop** in `meshtastic-telemetry-logger.sh`
5. **Add HTML visualization** in `html_generator.sh`
6. **Update documentation** in relevant `.md` files

### Testing & Validation

```bash
# Test configuration
./config_manager.sh

# Test individual components
DEBUG_MODE=true ./weather_integration.sh

# Test full pipeline
./meshtastic-telemetry-logger.sh --once
```

### Common Debugging Approaches

1. **Enable debug mode**: `DEBUG_MODE=true` in `.env`
2. **Check CSV outputs**: Validate data format and completeness
3. **Monitor meshtastic CLI**: Ensure commands execute without conflicts
4. **Verify HTML generation**: Check for JavaScript errors in dashboard
5. **Weather API validation**: Confirm API key and rate limits

## Project-Specific Best Practices

### Security Considerations
- **API keys**: Always use environment variables, never hardcode
- **File permissions**: Set `chmod 600 .env` for sensitive configs
- **Git exclusions**: Ensure `.env` is in `.gitignore`

### Performance Optimization
- **Sequential execution**: Required for Meshtastic CLI stability
- **Efficient CSV processing**: Use awk instead of multiple grep/sed calls
- **Weather caching**: Respect API rate limits with local caching
- **HTML generation**: Cache expensive computations, update incrementally

### Extensibility Patterns
- **Plugin architecture**: New analyzers follow `*_analyzer.py` pattern
- **Chart generation**: Use consistent base64 embedding for SVG charts
- **Dashboard modules**: Add new sections to `html_generator.sh` with CSS classes
- **Configuration**: Extend `.env` variables with sensible defaults

## Quick Reference for AI Agents

### Most Important Files to Understand
1. `common_utils.sh` - Understand all utility functions
2. `meshtastic-telemetry-logger.sh` - Main execution flow
3. `.env.example` - All configuration options
4. `html_generator.sh` - Dashboard generation patterns

### Common Tasks & Approaches
- **Adding new data collection**: Extend `run_telemetry_sequential()`
- **New visualizations**: Add chart generation to Python scripts, embed in HTML
- **Configuration changes**: Update `.env.example` and `config_manager.sh`
- **Error handling**: Use established debug and logging patterns

### Critical Integration Points
- **Meshtastic CLI**: Always sequential, always validate JSON output
- **Weather API**: Cache responses, handle rate limits gracefully
- **CSV data**: Maintain schema consistency, validate before writing
- **HTML dashboard**: Use established CSS classes and JavaScript patterns

This system prioritizes **reliability, modularity, and user experience** over complexity. When extending functionality, follow established patterns and maintain the clear separation of concerns that makes this codebase maintainable.