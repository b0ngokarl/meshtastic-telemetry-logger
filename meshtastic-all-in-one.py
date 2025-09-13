#!/usr/bin/env python3

"""
Meshtastic Telemetry Logger - All-in-One Python Script
Comprehensive telemetry monitoring system for Meshtastic mesh networks
Consolidates all functionality into a single optimized Python script
"""

import os
import sys
import time
import json
import csv
import subprocess
import argparse
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import urllib.request
import urllib.parse
import math

class MeshtasticTelemetryLogger:
    """Main telemetry logger class with all functionality consolidated"""
    
    def __init__(self, config_file: str = ".env"):
        """Initialize the logger with configuration"""
        self.script_dir = Path(__file__).parent.absolute()
        self.config = self.load_config(config_file)
        self.setup_logging()
        self.node_cache = {}
        self.cache_timestamp = 0
        
    def load_config(self, config_file: str) -> Dict:
        """Load configuration from environment file"""
        config = {
            'POLLING_INTERVAL': 300,
            'DEBUG_MODE': False,
            'TELEMETRY_TIMEOUT': 120,
            'NODES_TIMEOUT': 60,
            'WEATHER_TIMEOUT': 30,
            'ML_ENABLED': True,
            'MONITORED_NODES': '!9eed0410,!2c9e092b,!849c4818',
            'TELEMETRY_CSV': 'telemetry_log.csv',
            'NODES_CSV': 'nodes_log.csv',
            'HTML_OUTPUT': 'stats.html',
            'ERROR_LOG': 'error.log',
            'WEATHER_API_KEY': '',
            'DEFAULT_LATITUDE': 50.1109,
            'DEFAULT_LONGITUDE': 8.6821,
            'WEATHER_CACHE_DIR': 'weather_cache',
            'WEATHER_CACHE_TTL': 3600
        }
        
        env_file = self.script_dir / config_file
        if env_file.exists():
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip().strip('"\'')
                        
                        # Type conversion
                        if value.lower() in ('true', 'false'):
                            config[key] = value.lower() == 'true'
                        elif value.isdigit():
                            config[key] = int(value)
                        elif value.replace('.', '').isdigit():
                            config[key] = float(value)
                        else:
                            config[key] = value
        
        # Parse monitored nodes
        if isinstance(config['MONITORED_NODES'], str):
            config['MONITORED_NODES'] = [
                addr.strip().strip('"\'') 
                for addr in config['MONITORED_NODES'].split(',')
                if addr.strip()
            ]
        
        return config
    
    def setup_logging(self):
        """Setup logging configuration"""
        level = logging.DEBUG if self.config['DEBUG_MODE'] else logging.INFO
        logging.basicConfig(
            level=level,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.config['ERROR_LOG']),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def run_command(self, cmd: List[str], timeout: int = 30) -> Tuple[bool, str]:
        """Run a shell command with timeout"""
        try:
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=timeout,
                cwd=self.script_dir
            )
            return result.returncode == 0, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            return False, "Command timed out"
        except Exception as e:
            return False, str(e)
    
    def check_dependencies(self) -> bool:
        """Check if required dependencies are installed"""
        dependencies = ['meshtastic', 'jq', 'bc', 'curl']
        missing = []
        
        for dep in dependencies:
            success, _ = self.run_command(['which', dep])
            if not success:
                missing.append(dep)
        
        if missing:
            self.logger.error(f"Missing dependencies: {', '.join(missing)}")
            print("Please install missing dependencies:")
            for dep in missing:
                if dep == 'meshtastic':
                    print("  pip install meshtastic")
                else:
                    print(f"  # Install {dep} using your package manager")
            return False
        
        return True
    
    def init_files(self):
        """Initialize CSV files and directories"""
        # Create telemetry CSV
        telemetry_file = self.script_dir / self.config['TELEMETRY_CSV']
        if not telemetry_file.exists():
            with open(telemetry_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['timestamp', 'address', 'status', 'battery', 'voltage', 'channel_util', 'tx_util', 'uptime'])
        
        # Create nodes CSV
        nodes_file = self.script_dir / self.config['NODES_CSV']
        if not nodes_file.exists():
            with open(nodes_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['User', 'ID', 'AKA', 'Hardware', 'Pubkey', 'Role', 'Latitude', 'Longitude', 'Altitude', 'Battery', 'Channel_util', 'Tx_air_util', 'SNR', 'Hops', 'Channel', 'LastHeard', 'Since'])
        
        # Create weather cache directory
        cache_dir = self.script_dir / self.config['WEATHER_CACHE_DIR']
        cache_dir.mkdir(exist_ok=True)
        
        # Create other required files
        for log_file in ['power_predictions.csv', 'prediction_accuracy.csv']:
            file_path = self.script_dir / log_file
            if not file_path.exists():
                file_path.touch()
    
    def get_telemetry(self, address: str) -> Dict:
        """Get telemetry data from a specific node"""
        self.logger.debug(f"Requesting telemetry for {address}")
        
        success, output = self.run_command(
            ['meshtastic', '--request-telemetry', '--dest', address],
            timeout=self.config['TELEMETRY_TIMEOUT']
        )
        
        result = {
            'timestamp': datetime.now().isoformat(),
            'address': address,
            'status': 'unknown',
            'battery': '',
            'voltage': '',
            'channel_util': '',
            'tx_util': '',
            'uptime': ''
        }
        
        if not success:
            result['status'] = 'timeout' if 'timed out' in output.lower() else 'error'
            self.logger.warning(f"Telemetry failed for {address}: {output}")
        elif 'Telemetry received:' in output:
            result['status'] = 'success'
            
            # Parse telemetry data
            lines = output.split('\n')
            for line in lines:
                if 'Battery level:' in line:
                    try:
                        result['battery'] = ''.join(filter(str.isdigit, line.split(':')[1]))
                    except:
                        pass
                elif 'Voltage:' in line:
                    try:
                        result['voltage'] = ''.join(c for c in line.split(':')[1] if c.isdigit() or c == '.')
                    except:
                        pass
                elif 'Total channel utilization:' in line:
                    try:
                        result['channel_util'] = ''.join(filter(str.isdigit, line.split(':')[1]))
                    except:
                        pass
                elif 'Transmit air utilization:' in line:
                    try:
                        result['tx_util'] = ''.join(filter(str.isdigit, line.split(':')[1]))
                    except:
                        pass
                elif 'Uptime:' in line:
                    try:
                        result['uptime'] = ''.join(c for c in line.split(':')[1] if c.isdigit() or c == '.')
                    except:
                        pass
            
            self.logger.debug(f"Telemetry success for {address}: battery={result['battery']}%")
        else:
            result['status'] = 'error'
            self.logger.warning(f"Unexpected telemetry response for {address}")
        
        return result
    
    def collect_telemetry(self) -> List[Dict]:
        """Collect telemetry from all monitored nodes"""
        results = []
        
        for address in self.config['MONITORED_NODES']:
            result = self.get_telemetry(address)
            results.append(result)
            
            # Save to CSV
            telemetry_file = self.script_dir / self.config['TELEMETRY_CSV']
            with open(telemetry_file, 'a', newline='') as f:
                writer = csv.writer(f)
                writer.writerow([
                    result['timestamp'], result['address'], result['status'],
                    result['battery'], result['voltage'], result['channel_util'],
                    result['tx_util'], result['uptime']
                ])
        
        return results
    
    def update_nodes(self):
        """Update node discovery data"""
        self.logger.debug("Updating node list")
        
        success, output = self.run_command(
            ['meshtastic', '--nodes'],
            timeout=self.config['NODES_TIMEOUT']
        )
        
        if success:
            # Save raw output to log
            nodes_log = self.script_dir / 'nodes_log.txt'
            with open(nodes_log, 'a') as f:
                f.write(f"\n===== {datetime.now().isoformat()} =====\n")
                f.write(output)
            
            # Parse and update CSV (simplified parsing)
            self.parse_nodes_output(output)
        else:
            self.logger.error(f"Failed to update nodes: {output}")
    
    def parse_nodes_output(self, output: str):
        """Parse nodes output and update CSV"""
        # This is a simplified version - in production you'd want more robust parsing
        lines = output.split('\n')
        nodes_data = []
        
        for line in lines:
            if '│' in line and 'User' not in line and '─' not in line:
                # Basic parsing - split by │ and clean up
                parts = [part.strip() for part in line.split('│')]
                if len(parts) >= 10:
                    nodes_data.append(parts[1:])  # Skip first empty part
        
        if nodes_data:
            nodes_file = self.script_dir / self.config['NODES_CSV']
            # For simplicity, we'll append new data (in production, you'd deduplicate)
            with open(nodes_file, 'a', newline='') as f:
                writer = csv.writer(f)
                for node_data in nodes_data:
                    if len(node_data) >= 10:
                        writer.writerow(node_data[:17])  # Limit to expected columns
    
    def get_weather_data(self, lat: float, lon: float) -> Dict:
        """Get weather data for predictions"""
        cache_file = self.script_dir / self.config['WEATHER_CACHE_DIR'] / f"weather_{lat}_{lon}.json"
        
        # Check cache
        if cache_file.exists():
            cache_age = time.time() - cache_file.stat().st_mtime
            if cache_age < self.config['WEATHER_CACHE_TTL']:
                with open(cache_file, 'r') as f:
                    return json.load(f)
        
        # Fetch from API if key available
        if self.config['WEATHER_API_KEY']:
            try:
                url = f"https://api.openweathermap.org/data/2.5/forecast?lat={lat}&lon={lon}&appid={self.config['WEATHER_API_KEY']}&units=metric"
                with urllib.request.urlopen(url, timeout=10) as response:
                    data = json.load(response)
                    
                # Cache the data
                with open(cache_file, 'w') as f:
                    json.dump(data, f)
                    
                return data
            except Exception as e:
                self.logger.warning(f"Weather API failed: {e}")
        
        # Return mock data as fallback
        mock_data = {
            "list": [{
                "dt": int(time.time()),
                "weather": [{"main": "Clear", "description": "clear sky"}],
                "clouds": {"all": 20},
                "main": {"temp": 15}
            }]
        }
        
        with open(cache_file, 'w') as f:
            json.dump(mock_data, f)
        
        return mock_data
    
    def generate_html_dashboard(self):
        """Generate HTML dashboard"""
        self.logger.debug("Generating HTML dashboard")
        
        # Read telemetry data
        telemetry_data = []
        telemetry_file = self.script_dir / self.config['TELEMETRY_CSV']
        if telemetry_file.exists():
            with open(telemetry_file, 'r') as f:
                reader = csv.DictReader(f)
                telemetry_data = list(reader)
        
        # Read nodes data
        nodes_data = []
        nodes_file = self.script_dir / self.config['NODES_CSV']
        if nodes_file.exists():
            with open(nodes_file, 'r') as f:
                reader = csv.DictReader(f)
                nodes_data = list(reader)
        
        # Generate HTML
        html_content = self.create_html_content(telemetry_data, nodes_data)
        
        # Write to file
        html_file = self.script_dir / self.config['HTML_OUTPUT']
        with open(html_file, 'w') as f:
            f.write(html_content)
        
        self.logger.info(f"Dashboard generated: {html_file}")
    
    def create_html_content(self, telemetry_data: List[Dict], nodes_data: List[Dict]) -> str:
        """Create HTML dashboard content"""
        return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meshtastic Telemetry Dashboard</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; margin-bottom: 30px; }}
        .stats-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0; }}
        .stat-card {{ background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }}
        .stat-value {{ font-size: 2em; font-weight: bold; color: #333; }}
        .stat-label {{ color: #666; margin-top: 5px; }}
        table {{ border-collapse: collapse; width: 100%; margin: 20px 0; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }}
        th, td {{ border: 1px solid #ddd; padding: 12px 8px; text-align: left; }}
        th {{ background: linear-gradient(135deg, #f8f9fa, #e9ecef); font-weight: bold; }}
        tr:nth-child(even) {{ background-color: #f9f9f9; }}
        tr:hover {{ background-color: #fff3cd !important; }}
        .timestamp {{ font-family: monospace; font-size: 0.9em; }}
        .number {{ text-align: right; }}
        .address {{ font-weight: bold; }}
        .good {{ background-color: #e8f5e8; color: #1b5e20; font-weight: bold; }}
        .warning {{ background-color: #fff3e0; color: #ef6c00; font-weight: bold; }}
        .critical {{ background-color: #ffebee; color: #c62828; font-weight: bold; }}
        .battery-low {{ background-color: #ffe0b2; color: #ef6c00; }}
        .battery-critical {{ background-color: #ffcdd2; color: #c62828; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🌐 Meshtastic Telemetry Dashboard</h1>
        <p>Last updated: <strong>{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</strong></p>
    </div>
    
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value">{len(self.config['MONITORED_NODES'])}</div>
            <div class="stat-label">Monitored Nodes</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">{len(telemetry_data)}</div>
            <div class="stat-label">Total Records</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">{len([r for r in telemetry_data if r.get('status') == 'success'])}</div>
            <div class="stat-label">Successful</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">{len(nodes_data)}</div>
            <div class="stat-label">Discovered Nodes</div>
        </div>
    </div>
    
    <h2>📊 Monitored Node Status</h2>
    <table>
        <thead>
            <tr>
                <th>#</th><th>Address</th><th>Last Status</th><th>Battery (%)</th>
                <th>Voltage (V)</th><th>Channel Util (%)</th><th>TX Util (%)</th><th>Last Seen</th>
            </tr>
        </thead>
        <tbody>
            {self.create_monitored_nodes_rows(telemetry_data)}
        </tbody>
    </table>
    
    <h2>📈 Recent Telemetry Data</h2>
    <table>
        <thead>
            <tr>
                <th>Timestamp</th><th>Address</th><th>Status</th><th>Battery (%)</th>
                <th>Voltage (V)</th><th>Channel Util (%)</th><th>TX Util (%)</th>
            </tr>
        </thead>
        <tbody>
            {self.create_recent_telemetry_rows(telemetry_data)}
        </tbody>
    </table>
    
    <h2>📡 Discovered Nodes</h2>
    <table>
        <thead>
            <tr>
                <th>#</th><th>User</th><th>ID</th><th>Hardware</th><th>Last Heard</th>
            </tr>
        </thead>
        <tbody>
            {self.create_nodes_rows(nodes_data)}
        </tbody>
    </table>
    
    <div style="margin-top: 40px; padding: 20px; background: white; border-radius: 8px; text-align: center; color: #666;">
        <p>Generated by Meshtastic All-in-One Telemetry Logger</p>
        <p>Next update in {self.config['POLLING_INTERVAL']} seconds</p>
    </div>
</body>
</html>"""
    
    def create_monitored_nodes_rows(self, telemetry_data: List[Dict]) -> str:
        """Create HTML rows for monitored nodes"""
        rows = []
        
        for i, address in enumerate(self.config['MONITORED_NODES'], 1):
            # Get latest data for this node
            node_data = [r for r in telemetry_data if r.get('address') == address]
            latest = node_data[-1] if node_data else {}
            
            battery = latest.get('battery', 'N/A')
            voltage = latest.get('voltage', 'N/A')
            channel_util = latest.get('channel_util', 'N/A')
            tx_util = latest.get('tx_util', 'N/A')
            status = latest.get('status', 'unknown')
            timestamp = latest.get('timestamp', 'Never')
            
            # Apply CSS classes
            status_class = {'success': 'good', 'timeout': 'warning', 'error': 'critical'}.get(status, '')
            battery_class = ''
            if battery and battery != 'N/A':
                try:
                    battery_val = float(battery)
                    if battery_val <= 10:
                        battery_class = 'battery-critical'
                    elif battery_val <= 25:
                        battery_class = 'battery-low'
                except:
                    pass
            
            # Format timestamp
            try:
                if timestamp and timestamp != 'Never':
                    dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                    timestamp = dt.strftime('%Y-%m-%d %H:%M')
            except:
                pass
            
            rows.append(f"""
                <tr>
                    <td class="number">{i}</td>
                    <td class="address">{address}</td>
                    <td class="{status_class}">{status}</td>
                    <td class="number {battery_class}">{battery}</td>
                    <td class="number">{voltage}</td>
                    <td class="number">{channel_util}</td>
                    <td class="number">{tx_util}</td>
                    <td class="timestamp">{timestamp}</td>
                </tr>
            """)
        
        return ''.join(rows)
    
    def create_recent_telemetry_rows(self, telemetry_data: List[Dict]) -> str:
        """Create HTML rows for recent telemetry"""
        rows = []
        recent_data = telemetry_data[-20:] if len(telemetry_data) > 20 else telemetry_data
        
        for record in reversed(recent_data):
            address = record.get('address', '')
            status = record.get('status', 'unknown')
            battery = record.get('battery', 'N/A')
            voltage = record.get('voltage', 'N/A')
            channel_util = record.get('channel_util', 'N/A')
            tx_util = record.get('tx_util', 'N/A')
            timestamp = record.get('timestamp', '')
            
            # Apply CSS classes
            status_class = {'success': 'good', 'timeout': 'warning', 'error': 'critical'}.get(status, '')
            
            # Format timestamp
            try:
                if timestamp:
                    dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                    timestamp = dt.strftime('%Y-%m-%d %H:%M')
            except:
                pass
            
            rows.append(f"""
                <tr>
                    <td class="timestamp">{timestamp}</td>
                    <td class="address">{address}</td>
                    <td class="{status_class}">{status}</td>
                    <td class="number">{battery}</td>
                    <td class="number">{voltage}</td>
                    <td class="number">{channel_util}</td>
                    <td class="number">{tx_util}</td>
                </tr>
            """)
        
        return ''.join(rows)
    
    def create_nodes_rows(self, nodes_data: List[Dict]) -> str:
        """Create HTML rows for discovered nodes"""
        rows = []
        
        for i, node in enumerate(nodes_data[:50], 1):  # Limit to 50 most recent
            user = node.get('User', 'N/A')
            node_id = node.get('ID', 'N/A')
            hardware = node.get('Hardware', 'N/A')
            last_heard = node.get('LastHeard', 'N/A')
            
            # Format timestamp
            try:
                if last_heard and last_heard != 'N/A':
                    # Try to parse various timestamp formats
                    dt = datetime.fromisoformat(last_heard.replace('Z', '+00:00'))
                    last_heard = dt.strftime('%Y-%m-%d %H:%M')
            except:
                pass
            
            rows.append(f"""
                <tr>
                    <td class="number">{i}</td>
                    <td>{user}</td>
                    <td class="address">{node_id}</td>
                    <td>{hardware}</td>
                    <td class="timestamp">{last_heard}</td>
                </tr>
            """)
        
        return ''.join(rows)
    
    def run_collection_cycle(self):
        """Run a single data collection cycle"""
        self.logger.info("🔄 Starting telemetry collection cycle")
        
        try:
            # 1. Collect telemetry
            self.logger.info(f"📡 Collecting telemetry from {len(self.config['MONITORED_NODES'])} nodes")
            telemetry_results = self.collect_telemetry()
            successful = len([r for r in telemetry_results if r['status'] == 'success'])
            self.logger.info(f"📊 Collected: {successful}/{len(telemetry_results)} successful")
            
            # 2. Update node list
            self.logger.info("🔍 Updating node discovery data")
            self.update_nodes()
            
            # 3. Generate dashboard
            self.logger.info("📈 Generating HTML dashboard")
            self.generate_html_dashboard()
            
            self.logger.info("✅ Collection cycle completed successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Collection cycle failed: {e}")
            return False
    
    def run_continuous(self):
        """Run continuous telemetry collection"""
        self.logger.info("🚀 Starting continuous telemetry collection")
        self.logger.info(f"📊 Monitoring {len(self.config['MONITORED_NODES'])} nodes")
        self.logger.info(f"⏱️ Polling interval: {self.config['POLLING_INTERVAL']} seconds")
        self.logger.info("🛑 Press Ctrl+C to stop")
        
        try:
            while True:
                success = self.run_collection_cycle()
                
                if success:
                    next_time = datetime.now() + timedelta(seconds=self.config['POLLING_INTERVAL'])
                    self.logger.info(f"😴 Sleeping until {next_time.strftime('%H:%M:%S')}")
                else:
                    self.logger.warning("⚠️ Collection cycle failed, retrying in 60 seconds")
                    time.sleep(60)
                    continue
                
                time.sleep(self.config['POLLING_INTERVAL'])
                
        except KeyboardInterrupt:
            self.logger.info("🛑 Shutting down gracefully")
        except Exception as e:
            self.logger.error(f"💥 Fatal error: {e}")
            sys.exit(1)
    
    def create_default_config(self):
        """Create default configuration file"""
        config_content = """# Meshtastic Telemetry Logger Configuration

# Basic Settings
POLLING_INTERVAL=300          # Time between collection cycles (seconds)
DEBUG_MODE=false              # Enable debug output (true/false)

# Timeouts (seconds)
TELEMETRY_TIMEOUT=120         # Timeout for individual telemetry requests
NODES_TIMEOUT=60              # Timeout for node discovery
WEATHER_TIMEOUT=30            # Timeout for weather API calls

# Node Monitoring - Replace with your actual node IDs
MONITORED_NODES="!9eed0410,!2c9e092b,!849c4818"

# Weather & Location (optional)
WEATHER_API_KEY=              # OpenWeatherMap API key (leave empty for mock data)
DEFAULT_LATITUDE=50.1109      # Your location latitude
DEFAULT_LONGITUDE=8.6821      # Your location longitude

# Machine Learning Features
ML_ENABLED=true               # Enable ML power predictions

# File Paths (usually don't need to change)
TELEMETRY_CSV=telemetry_log.csv
NODES_CSV=nodes_log.csv
HTML_OUTPUT=stats.html
"""
        
        config_file = self.script_dir / ".env"
        with open(config_file, 'w') as f:
            f.write(config_content)
        
        print(f"✅ Created default configuration: {config_file}")
        print("📝 Edit the .env file to customize your settings")
        print("🎯 Update MONITORED_NODES with your actual node addresses")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Meshtastic All-in-One Telemetry Logger",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Run continuous collection
  %(prog)s once               # Single collection cycle  
  %(prog)s html               # Generate dashboard only
  %(prog)s config             # Create configuration file
  %(prog)s --debug run        # Run with debug output
        """
    )
    
    parser.add_argument(
        'command', 
        nargs='?', 
        default='run',
        choices=['run', 'once', 'html', 'config'],
        help='Command to execute (default: run)'
    )
    
    parser.add_argument(
        '--debug', 
        action='store_true',
        help='Enable debug output'
    )
    
    parser.add_argument(
        '--interval', 
        type=int,
        help='Override polling interval (seconds)'
    )
    
    args = parser.parse_args()
    
    # Create logger instance
    logger = MeshtasticTelemetryLogger()
    
    # Apply command line overrides
    if args.debug:
        logger.config['DEBUG_MODE'] = True
        logger.setup_logging()
    
    if args.interval:
        logger.config['POLLING_INTERVAL'] = args.interval
    
    # Execute command
    if args.command == 'config':
        logger.create_default_config()
    
    elif args.command == 'html':
        print("🎨 Generating HTML dashboard from existing data...")
        if not (logger.script_dir / logger.config['TELEMETRY_CSV']).exists():
            print("❌ No telemetry data found. Run a collection cycle first.")
            sys.exit(1)
        logger.generate_html_dashboard()
        print(f"✅ Dashboard generated: {logger.config['HTML_OUTPUT']}")
    
    elif args.command == 'once':
        print("🎯 Running single collection cycle...")
        if not logger.check_dependencies():
            sys.exit(1)
        logger.init_files()
        success = logger.run_collection_cycle()
        if success:
            print(f"✅ Cycle completed! Dashboard: {logger.config['HTML_OUTPUT']}")
        else:
            print("❌ Collection cycle failed")
            sys.exit(1)
    
    elif args.command == 'run':
        if not logger.check_dependencies():
            sys.exit(1)
        logger.init_files()
        logger.run_continuous()
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()