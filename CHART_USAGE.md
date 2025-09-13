# Chart Generation Usage

This repository includes configurable chart generation for visualizing node telemetry data (channel utilization and transmission utilization).

## Files

- `generate_node_chart.py` - Generic chart generator with .env configuration and command-line overrides
- `generate_trutzturm_chart.py` - Original Trutzturm-specific chart generator (maintained for compatibility)

## Configuration

### 1. Using .env file (Recommended)

Add these variables to your `.env` file:

```bash
# Chart generation configuration
CHART_NODES="!2df67288,!a0cc8008"
CHART_NODE_NAMES="TRUTZTURM Solar (TRZS),DL0TRZ Trutzturm Oppenheim (TRZT)"
```

Then run:
```bash
python generate_node_chart.py
```

### 2. Using Command-Line Arguments

Override .env configuration with command-line arguments:

```bash
# Generate chart for specific nodes
python generate_node_chart.py --nodes "!2df67288,!a0cc8008"

# Single node with custom name
python generate_node_chart.py --nodes "!2df67288" --names "My Solar Node"

# Custom output filename
python generate_node_chart.py --nodes "!2df67288" --output "my_node"

# Use different CSV file
python generate_node_chart.py --csv "backup_telemetry.csv"
```

## Output

The script generates:
- **PNG chart**: High-resolution bitmap image (300 DPI)
- **SVG chart**: Vector graphics (scalable)
- **Console statistics**: Data summary with min/max/average values

## Chart Features

- **Dual-panel layout**: Channel Utilization (top) and Transmission Utilization (bottom)
- **Time-series plots**: Shows trends over time with timestamps
- **Multiple node comparison**: Supports 1-8 nodes with different colors
- **Automatic scaling**: Y-axis scales based on data range
- **Grid lines and legends**: Easy to read and interpret

## Requirements

```bash
pip install matplotlib pandas
```

## Examples

### Multiple Nodes Comparison
```bash
python generate_node_chart.py --nodes "!2df67288,!a0cc8008" --names "Solar Node,Base Station"
```

### Single Node Analysis
```bash
python generate_node_chart.py --nodes "!9eed0410" --names "My Gateway" --output "gateway_analysis"
```

### All Monitored Nodes
If `CHART_NODES` is not set in .env, it will fall back to using all `MONITORED_NODES`.

## Troubleshooting

**No data found**: Ensure the node IDs exist in your telemetry_log.csv and have successful readings.

**Import errors**: Install required packages: `pip install matplotlib pandas`

**Configuration errors**: Check that your .env file syntax is correct and node IDs are properly formatted (e.g., `!2df67288`).
