# Telemetry Chart Generation

This directory contains two chart generation tools for visualizing Meshtastic node telemetry data:

## 1. generate_node_chart.py
**Purpose**: Generates utilization-focused charts (Channel & Transmission Utilization)
- **Output**: 2-panel charts showing channel and transmission utilization over time
- **Best for**: Network performance analysis, utilization trending

## 2. generate_full_telemetry_chart.py  
**Purpose**: Generates comprehensive telemetry charts with all available metrics
- **Output**: 5-panel charts showing:
  - Battery Level (%)
  - Voltage (V)
  - Channel Utilization (%)
  - Transmission Utilization (%)
  - Uptime (Hours)
- **Best for**: Complete node health monitoring, solar power analysis, long-term trending

## Configuration

Both tools use the same configuration system with **automatic node name detection**:

### .env File Configuration
```bash
# Nodes to include in charts
CHART_NODES=!2df67288,!a0cc8008

# Human-readable names for the nodes (OPTIONAL - auto-generated from nodes_log.csv)
CHART_NODE_NAMES=TRUTZTURM Solar,DL0TRZ Trutzturm

# CSV file containing telemetry data (optional, defaults to telemetry_log.csv)
TELEMETRY_CSV=telemetry_log.csv
```

### ✨ Automatic Node Name Detection
**New Feature**: You no longer need to manually maintain `CHART_NODE_NAMES`!

- **Auto-updates**: Both chart tools automatically read node names from `nodes_log.csv`
- **Smart naming**: Uses AKA (short name) + User name when available
- **Example**: `TRUTZTURM Solar (TRZS)`, `EinmachglasV2 (EMG2)`
- **Fallback**: Uses node ID if name not found in CSV
- **Override**: Command-line `--names` parameter still works for custom names

Simply set `CHART_NODES` with your desired node IDs, and the tools will automatically populate the names!

### Manual Node Name Update
If you need to manually update node names without generating charts:
```bash
python update_chart_names.py
```
This standalone script reads `CHART_NODES` from `.env` and updates `CHART_NODE_NAMES` from `nodes_log.csv`.

### Command Line Usage

#### Basic Usage (uses .env configuration)
```bash
# Generate utilization charts
python generate_node_chart.py

# Generate comprehensive telemetry charts
python generate_full_telemetry_chart.py
```

#### Advanced Usage (override .env settings)
```bash
# Single node comprehensive telemetry (names auto-detected)
python generate_full_telemetry_chart.py --nodes '!2df67288' --output solar_analysis

# Multiple nodes with custom names (override auto-detection)
python generate_node_chart.py --nodes '!2df67288,!a0cc8008' --names 'Solar Node,Main Node' --output comparison

# Custom CSV file (names still auto-detected from nodes_log.csv)
python generate_full_telemetry_chart.py --csv my_telemetry_data.csv --output custom_analysis

# Just change nodes, keep auto-detected names
python generate_node_chart.py --nodes '!2df67288,!849c4818' --output selected_nodes
```

## Output Files

Both tools generate:
- **PNG files**: High-resolution raster images (300 DPI) for reports and documentation
- **SVG files**: Scalable vector graphics for presentations and web display

### File Naming Convention
- **Auto-generated**: Based on node IDs or "multi_node" for multiple nodes
- **Custom**: Use `--output` parameter to specify custom prefix
- **Examples**: 
  - `2df67288_chart.png` (single node, auto-generated)
  - `multi_node_telemetry_chart.png` (multiple nodes)
  - `solar_analysis_chart.svg` (custom prefix)

## Chart Features

### Visual Design
- **Color-coded lines**: Each node gets a unique color for easy identification
- **Different markers**: Each metric uses distinct markers (○, □, △, ◇, ×)
- **Grid lines**: Subtle grid overlay for easier reading
- **Time formatting**: Human-readable timestamps (MM-DD HH:MM)
- **Auto-scaling**: Y-axis automatically scales to data ranges

### Data Handling
- **Missing data**: Gracefully handles missing or invalid telemetry values
- **Time zones**: Preserves timezone information from original data
- **Large datasets**: Efficiently processes hundreds of data points
- **Multiple nodes**: Overlays multiple node data for comparison

## Practical Examples

### Solar Node Monitoring
Monitor battery, voltage, and power efficiency:
```bash
python generate_full_telemetry_chart.py --nodes '!2df67288' --names 'Solar Station' --output solar_health
```

### Network Performance Analysis
Focus on utilization metrics for network optimization:
```bash
python generate_node_chart.py --nodes '!2df67288,!a0cc8008' --output network_performance
```

### Daily Health Check
Generate charts for all monitored nodes using .env configuration:
```bash
python generate_full_telemetry_chart.py --output daily_$(date +%Y%m%d)
```

### Custom Time Period Analysis
Use specific CSV data for focused analysis:
```bash
python generate_full_telemetry_chart.py --csv telemetry_subset.csv --output event_analysis
```

## Troubleshooting

### No Data Found
If you see "No telemetry data found for configured nodes":
1. Check that node IDs in configuration match CSV data exactly
2. Verify CSV file path and permissions
3. Ensure telemetry data contains 'success' status entries

### Missing Metrics
If some metrics don't appear in charts:
- **Battery/Voltage**: Node may not report power metrics
- **Utilization**: Node may not be actively transmitting
- **Uptime**: Some nodes don't report uptime data

### Performance
For large datasets (1000+ points):
- Consider filtering CSV data by date range
- Use `--output` to avoid filename conflicts
- Charts may take 10-30 seconds to generate

## Integration with Dashboard

These chart tools complement the HTML dashboard:
- **Dashboard**: Real-time status monitoring
- **Charts**: Historical trend analysis
- **Combined**: Complete monitoring solution

Both tools read the same CSV data generated by the main telemetry logger, ensuring consistency across all monitoring tools.
