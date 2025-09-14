# Network Activity News Feature

The Meshtastic Telemetry Logger now includes a **Network Activity News** section that tracks changes in your mesh network over time.

## Features

The news section monitors and reports:

- 🆕 **New nodes**: Nodes that have appeared in the network
- 📵 **Lost nodes**: Nodes that are no longer reachable
- 🏷️ **Name changes**: Nodes that have changed their display name (AKA)
- 🔐 **Public key changes**: Nodes that have updated their encryption keys
- ⚙️ **Role changes**: Nodes that have switched modes (CLIENT ↔ ROUTER, etc.)
- 🔧 **Hardware changes**: Nodes that have updated their hardware type

## Configuration

Add these settings to your `.env` file:

```bash
# Network Activity News Settings
NEWS_ENABLED=true              # Enable network activity news section
NEWS_TIME_WINDOW=24            # Time window for news in hours (24 = last 24 hours)
NEWS_MAX_HOPS=2                # Maximum hops to include in news (0=direct, 1=1 hop, 2=2 hops, etc.)
```

### Configuration Options

- **NEWS_ENABLED**: Set to `true` to enable the news feature, `false` to disable
- **NEWS_TIME_WINDOW**: Time window in hours for tracking changes (default: 24 hours)
- **NEWS_MAX_HOPS**: Maximum hop distance to include in news
  - `0`: Only direct connections (0 hops)
  - `1`: Direct connections and 1-hop neighbors
  - `2`: Up to 2 hops away (recommended for most networks)
  - Higher values will include more distant nodes but may be less relevant

## How It Works

1. **State Tracking**: The system maintains a snapshot of the network state in `network_state.json`
2. **Change Detection**: On each run, it compares the current network state with the previous state
3. **News Generation**: Changes are categorized and formatted into an HTML news section
4. **Dashboard Integration**: The news is automatically embedded into the web dashboard

## Manual Usage

You can manually generate network news:

```bash
# Generate network activity news
python network_news_analyzer.py

# Embed news into HTML dashboard
python network_news_embedder.py
```

## Automatic Integration

When enabled, network news is automatically:
- Generated after each telemetry collection cycle
- Embedded into the HTML dashboard
- Updated with the latest network changes

## Understanding the News

### Summary Statistics
- **Active nodes**: Total number of nodes active within the time window and hop limit
- **New**: Nodes that appeared since the last check
- **Lost**: Nodes that were previously active but are no longer reachable
- **Changed**: Nodes that have changed their properties (name, role, hardware, etc.)

### Node Information
Each news item shows:
- **Node ID**: The unique identifier (e.g., `!a0cc8008`)
- **Name**: The display name or AKA
- **Hardware**: Device type (e.g., HELTEC_V3, RAK4631)
- **Hops**: Distance from your node (0 = direct connection)
- **Timestamp**: When the change was detected

## Troubleshooting

### No News Displayed
- Check that `NEWS_ENABLED=true` in your `.env` file
- Ensure the news scripts are present: `network_news_analyzer.py` and `network_news_embedder.py`
- Verify that `nodes_log.csv` contains current data

### Too Many "New" Nodes
This is normal on the first run, as all nodes appear as "new". Subsequent runs will show actual changes.

### Missing Changes
- Increase `NEWS_TIME_WINDOW` to capture changes over a longer period
- Increase `NEWS_MAX_HOPS` to include more distant nodes
- Ensure your telemetry collection is running regularly

## Files Created

The news feature creates these files:
- `network_news.html`: Generated news HTML
- `network_state.json`: Previous network state for comparison

These files are automatically managed and don't need manual intervention.