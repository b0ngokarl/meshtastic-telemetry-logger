# Meshtastic Telemetry Logger (Pure Bash)

A simple Bash-based logger for Meshtastic node telemetry.

## Features

- Configurable list of node addresses (`ADDRESSES` in script)
- Adjustable polling interval (`INTERVAL` in script)
- Logs telemetry to CSV with timestamp and status
- Logs node table snapshots
- Generates a basic HTML statistics page

## Usage

1. Edit `meshtastic-telemetry-logger.sh` and set your node addresses and interval at the top.
2. Run the script:
   ```bash
   bash meshtastic-telemetry-logger.sh
   ```
3. CSV logs, node logs, and stats HTML will be updated automatically.

## Requirements

- Bash (tested on Linux)
- `meshtastic` CLI installed and configured
- Standard Unix tools: `awk`, `grep`, etc.

## Output Files

- `telemetry_log.csv` - Telemetry results
- `nodes_log.txt` - Node table snapshots
- `stats.html` - Statistics and last results
- `error.log` - Any errors encountered

## Customization

- Add more addresses to the `ADDRESSES` array
- Adjust interval as desired

## License

MIT