# Configuration Setup Instructions

## First Time Setup

1. **Copy the example configuration:**
   ```bash
   cp .env.example .env
   ```

2. **Edit the configuration file:**
   ```bash
   nano .env
   ```

3. **Essential Settings to Configure:**

   ### Weather API (Optional but Recommended)
   - Get a free API key from https://openweathermap.org/api
   - Set `WEATHER_API_KEY=your_actual_api_key_here`

   ### Monitored Nodes
   - Replace the example node IDs with your actual node IDs:
   ```
   MONITORED_NODES="!your_node1,!your_node2,!your_node3"
   ```

   ### Location (for weather/solar calculations)
   - Set your latitude and longitude:
   ```
   DEFAULT_LATITUDE=your_latitude
   DEFAULT_LONGITUDE=your_longitude
   ```

4. **Optional Settings:**
   - `POLLING_INTERVAL`: How often to collect data (seconds)
   - `TELEMETRY_TIMEOUT`: Timeout for telemetry requests (seconds)
   - `DEBUG_MODE`: Set to `true` for verbose output
   - `ML_ENABLED`: Set to `false` to disable machine learning

## Security Notes

- The `.env` file is excluded from git commits automatically
- Never commit API keys or sensitive configuration to version control
- Keep your `.env` file permissions secure: `chmod 600 .env`

## Running the Logger

After configuration, run the logger as usual:
```bash
./meshtastic-telemetry-logger.sh
```

The script will automatically load settings from `.env` and use sensible defaults for any missing values.
