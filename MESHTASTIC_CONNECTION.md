# Meshtastic Connection Configuration

The Meshtastic Telemetry Logger now supports multiple connection methods to communicate with your Meshtastic device. You can configure the connection method through the `.env` file.

## Connection Types

### 1. Serial Connection (Default)
Connect via USB serial port (most common method).

```env
MESHTASTIC_CONNECTION_TYPE=serial
MESHTASTIC_SERIAL_PORT=auto        # auto-detect or specific port like /dev/ttyUSB0
```

**Examples:**
- `auto` - Let meshtastic CLI auto-detect the serial port
- `/dev/ttyUSB0` - Specific USB serial device on Linux
- `/dev/ttyACM0` - Alternative USB serial device on Linux
- `COM3` - Serial port on Windows

### 2. TCP Connection
Connect via WiFi/Ethernet to a Meshtastic device with network connectivity.

```env
MESHTASTIC_CONNECTION_TYPE=tcp
MESHTASTIC_TCP_HOST=192.168.1.100  # IP address of your Meshtastic device
MESHTASTIC_TCP_PORT=4403           # Port (default: 4403)
```

**Use Cases:**
- Meshtastic device connected to WiFi
- Device with Ethernet module
- Remote monitoring over network

### 3. Bluetooth Low Energy (BLE)
Connect via Bluetooth to a Meshtastic device.

```env
MESHTASTIC_CONNECTION_TYPE=ble
MESHTASTIC_BLE_ADDRESS=12:34:56:78:9A:BC  # MAC address of your device
```

**Finding BLE MAC Address:**
```bash
# Scan for Meshtastic devices
meshtastic --ble-scan

# Or use system Bluetooth tools
bluetoothctl
scan on
```

## Configuration Examples

### Example 1: Auto-detect Serial (Default)
```env
MESHTASTIC_CONNECTION_TYPE=serial
MESHTASTIC_SERIAL_PORT=auto
```

### Example 2: Specific Serial Port
```env
MESHTASTIC_CONNECTION_TYPE=serial
MESHTASTIC_SERIAL_PORT=/dev/ttyUSB0
```

### Example 3: WiFi Connected Device
```env
MESHTASTIC_CONNECTION_TYPE=tcp
MESHTASTIC_TCP_HOST=192.168.1.50
MESHTASTIC_TCP_PORT=4403
```

### Example 4: Bluetooth Connection
```env
MESHTASTIC_CONNECTION_TYPE=ble
MESHTASTIC_BLE_ADDRESS=AA:BB:CC:DD:EE:FF
```

## Switching Connection Methods

1. Edit your `.env` file
2. Change the `MESHTASTIC_CONNECTION_TYPE` and related settings
3. Restart the telemetry logger

The logger will automatically use the new connection method for all Meshtastic communications.

## Troubleshooting

### Serial Connection Issues
- Check that the device is connected via USB
- Verify the correct port with `ls /dev/tty*` (Linux) or Device Manager (Windows)
- Ensure proper permissions: `sudo usermod -a -G dialout $USER`

### TCP Connection Issues
- Verify the device IP address: `ping 192.168.1.100`
- Check that port 4403 is open
- Ensure the device has network connectivity

### BLE Connection Issues
- Make sure Bluetooth is enabled on your system
- Verify the MAC address with a BLE scan
- Check that the device is in pairing/discoverable mode

## Command Generation

The system automatically builds the appropriate meshtastic command based on your configuration:

- **Serial**: `meshtastic --port /dev/ttyUSB0 --request-telemetry`
- **TCP**: `meshtastic --host 192.168.1.100:4403 --request-telemetry`
- **BLE**: `meshtastic --ble AA:BB:CC:DD:EE:FF --request-telemetry`

All timeout and retry logic remains the same regardless of connection type.