# Enhanced Chart Labels with Averages

## Overview

The meshtastic telemetry charts now use **short node names** with **real-time averages** displayed as text behind each node name in the chart legends.

## Short Name Extraction

The charts now show concise node identifiers instead of full names:

| Full Node Name | Short Name | Source |
|---------------|------------|---------|
| `Schwabsburg Funklochfueller 0410 solar (BURG)` | **BURG** | From parentheses |
| `Meshtastic 092b mobile node (092b)` | **092b** | From parentheses |
| `Ondas_fix_Nierstein_RLP (Ond1)` | **Ond1** | From parentheses |
| `DL0TRZ Trutzturm Oppenheim (TRZT)` | **TRZT** | From parentheses |
| `EinmachglasV2 (EMG2)` | **EMG2** | From parentheses |
| `TRUTZTURM Solar (TRZS)` | **TRZS** | From parentheses |

## Average Values Display

Each chart legend now shows **real-time averages** for **3h, 12h, and 24h** periods:

### Example Chart Labels

**Battery Level Chart:**
- `BURG (3h:88% | 12h:86% | 24h:84%)`
- `092b (3h:91% | 12h:89% | 24h:87%)`
- `TRZT (3h:100% | 12h:98% | 24h:96%)`

**Voltage Chart:**
- `BURG (3h:4.0V | 12h:3.9V | 24h:3.8V)`
- `092b (3h:4.1V | 12h:4.0V | 24h:3.9V)`

**Channel Utilization Chart:**
- `BURG (3h:12.5% | 12h:14.2% | 24h:16.8%)`
- `Ond1 (3h:20.1% | 12h:22.3% | 24h:25.1%)`

**Transmission Utilization Chart:**
- `BURG (3h:2.8% | 12h:3.1% | 24h:3.4%)`
- `EMG2 (3h:5.2% | 12h:4.9% | 24h:4.7%)`

## Chart Enhancements

### 1. **Comprehensive Telemetry Chart** (`multi_node_telemetry_chart.png`)
- **5 subplots**: Battery Level, Voltage, Channel Utilization, TX Utilization, Uptime
- **Short names**: BURG, 092b, Ond1, TRZT, EMG2, TRZS
- **Dynamic averages**: Shows 3h, 12h, 24h trends for each metric
- **Real-time data**: Updates with every telemetry collection

### 2. **Utilization Chart** (`multi_node_utilization_chart.png`)
- **2 subplots**: Channel Utilization, Transmission Utilization
- **Network focus**: Emphasizes mesh network performance
- **Trend analysis**: Averages help identify usage patterns
- **Comparative view**: Easy comparison between nodes

## Benefits

✅ **Cleaner Display**: Short names reduce visual clutter  
✅ **Trend Analysis**: Immediate access to recent averages  
✅ **Real Values**: Current actual measurements prominently displayed  
✅ **Time Context**: 3h/12h/24h periods provide temporal perspective  
✅ **Auto-Generated**: Updates automatically with each telemetry run  

## Technical Implementation

### Average Calculation Logic
```python
def calculate_recent_averages(timestamps, values, metric_name):
    periods = {'3h': 3, '12h': 12, '24h': 24}
    for period_name, hours in periods.items():
        cutoff_time = now - timedelta(hours=hours)
        recent_values = [v for t, v in zip(timestamps, values) 
                        if v is not None and t >= cutoff_time]
        if recent_values:
            avg = statistics.mean(recent_values)
            # Format based on metric type (%, V, etc.)
```

### Short Name Extraction
```python
def extract_short_name(full_name):
    # Priority 1: Extract from parentheses
    if '(' in full_name and ')' in full_name:
        return text_between_parentheses
    # Fallback: Use first 4 chars of last word
    return words[-1][:4].upper()
```

## Chart Legend Format

The enhanced labels follow this pattern:
```
{SHORT_NAME} ({3h_avg} | {12h_avg} | {24h_avg})
```

Examples:
- `TRZT (3h:100% | 12h:98% | 24h:96%)` - Battery levels
- `BURG (3h:4.0V | 12h:3.9V | 24h:3.8V)` - Voltage values  
- `Ond1 (3h:20.1% | 12h:22.3% | 24h:25.1%)` - Utilization percentages

## Automatic Updates

The enhanced charts automatically regenerate with:
- **Every telemetry collection cycle**
- **Updated averages based on latest data**
- **Real-time node status and metrics**
- **Automatic web deployment to `/var/www/html/`**

## Web Access

View the enhanced charts at:
- **Dashboard**: `http://your-server/` (embedded in HTML)
- **Direct PNG**: `http://your-server/multi_node_telemetry_chart.png`
- **Vector SVG**: `http://your-server/multi_node_telemetry_chart.svg`