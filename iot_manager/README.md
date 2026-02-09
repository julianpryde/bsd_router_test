# IoT Device Autodetection and Management System

## Overview

This system provides automated IoT device detection, isolation, and management for FreeBSD routers. Each detected IoT device is automatically assigned to its own VLAN (VLAN 20-254) for network microsegmentation, with suspicious devices automatically moved to a quarantine VLAN (VLAN 255).

## Features

- **Automatic Device Detection**: Scans ARP tables and DHCP leases to detect IoT devices
- **Device Profile Matching**: Matches devices to known profiles from multiple data sources
- **Individual VLAN Assignment**: Each device gets its own VLAN (supports up to 235 devices)
- **Quarantine System**: Suspicious devices automatically moved to VLAN 255
- **Alert Management**: Firmware update alerts and resource monitoring
- **Simple CLI**: Command-line interface for device and alert management
- **Remote Storage**: All data stored remotely (not on Raspberry Pi)

## Architecture

### Components

1. **Device Database** (`device_database.py`)
   - Manages device registry and VLAN assignments
   - Tracks up to 234 devices (VLAN 20-254)
   - Handles quarantine operations (VLAN 255)

2. **Device Profiles** (`device_profiles.py`)
   - Stores known device profiles from multiple sources
   - Priority: manual > wireshark > crowdsourced > iot-inspector
   - Matches devices based on MAC prefix, hostname, DHCP fingerprint

3. **Detection Module** (`detection.py`)
   - Scans network for new devices via ARP and DHCP
   - Uses heuristics to identify IoT devices
   - Extracts manufacturer information from MAC OUI

4. **Alert System** (`alerts.py`)
   - Firmware update alerts
   - Resource monitoring alerts (CPU, memory, network)
   - Alert acknowledgement and resolution
   - Remote storage for alert history

5. **Resource Monitor** (`monitoring.py`)
   - Monitors router CPU, memory, and network usage
   - Generates alerts when thresholds exceeded
   - Configurable thresholds

6. **CLI Interface** (`cli.py`)
   - Simple command-line tool for management
   - List and filter devices and alerts
   - Quarantine/unquarantine devices
   - Acknowledge and resolve alerts

## Installation

### Prerequisites

- FreeBSD 12.x or later
- Python 3.7+
- Root/sudo access for network scanning

### Setup

1. **Clone the repository**:
   ```bash
   cd /home/julian/homelab
   git clone https://github.com/julianpryde/bsd_router_test.git
   ```

2. **Configure storage paths** (use network storage, NOT local Raspberry Pi):
   ```bash
   export IOT_DB_PATH="/mnt/network_storage/iot_manager/devices.json"
   export IOT_ALERTS_PATH="/mnt/network_storage/iot_manager/alerts.json"
   export IOT_PROFILES_DIR="/mnt/network_storage/iot_manager/profiles"
   ```

3. **Copy default profiles**:
   ```bash
   mkdir -p /mnt/network_storage/iot_manager/profiles
   cp iot_manager/profiles/default_profiles.json /mnt/network_storage/iot_manager/profiles/
   ```

4. **Make CLI executable**:
   ```bash
   chmod +x iot_manager/cli.py
   ln -s /home/julian/homelab/bsd_router_test/iot_manager/cli.py /usr/local/bin/iot-mgr
   ```

## Usage

### Basic Commands

#### List all devices
```bash
iot-mgr devices
# or just quarantined devices
iot-mgr devices --quarantined-only
```

#### Show device details
```bash
iot-mgr show aa:bb:cc:dd:ee:ff
```

#### Detect new devices
```bash
# Scan for new IoT devices
iot-mgr detect

# Scan for all devices (not just IoT)
iot-mgr detect --all

# Dry run (don't add to database)
iot-mgr detect --dry-run
```

#### Manage quarantine
```bash
# Quarantine a device
iot-mgr quarantine aa:bb:cc:dd:ee:ff --reason "Suspicious traffic detected"

# Remove from quarantine
iot-mgr unquarantine aa:bb:cc:dd:ee:ff
```

#### View alerts
```bash
# List all unresolved alerts
iot-mgr alerts --unresolved-only

# Filter by level
iot-mgr alerts --level critical

# Filter by type
iot-mgr alerts --type firmware_update

# Show alert details
iot-mgr show-alert 20260209123456
```

#### Manage alerts
```bash
# Acknowledge an alert
iot-mgr ack 20260209123456

# Resolve an alert
iot-mgr resolve 20260209123456
```

#### View statistics
```bash
iot-mgr stats
```

### Automated Scanning

Set up cron job for automatic device detection:

```bash
# Add to /etc/crontab
# Scan for new devices every hour
0 * * * * root /usr/local/bin/iot-mgr detect > /dev/null 2>&1
```

### Resource Monitoring

Set up cron job for resource monitoring:

```bash
# Add to /etc/crontab
# Check resources every 15 minutes
*/15 * * * * root /usr/local/bin/iot-monitor > /dev/null 2>&1
```

## VLAN Configuration

### VLAN Ranges

- **VLAN 20-254**: Individual device VLANs (235 VLANs available)
- **VLAN 255**: Quarantine VLAN for suspicious devices

### Example VLAN Setup in rc.conf

```bash
# Enable VLAN support
cloned_interfaces="vlan20 vlan21 vlan22 ... vlan254 vlan255"

# Configure each VLAN
ifconfig_vlan20="inet 192.168.20.1/24 vlan 20 vlandev em1"
ifconfig_vlan21="inet 192.168.21.1/24 vlan 21 vlandev em1"
...
ifconfig_vlan255="inet 192.168.255.1/24 vlan 255 vlandev em1"
```

### Firewall Rules (pf.conf)

```bash
# Quarantine VLAN - very restrictive
pass in on vlan255 proto icmp
block in on vlan255 all

# Individual device VLANs - allow only HTTPS
pass in on vlan20-vlan254 proto { tcp udp } to port 443
pass in on vlan20-vlan254 proto udp to port 53  # DNS
```

## Data Sources

### Priority Order

1. **Manually Curated** (highest priority)
   - Hand-verified device profiles
   - Store in `profiles/manual/`

2. **Wireshark Captures**
   - Device behavior captured via packet analysis
   - Store in `profiles/wireshark/`

3. **Crowdsourced Data**
   - Community-contributed device profiles
   - Store in `profiles/crowdsourced/`

4. **IoT Inspector Datasets** (lowest priority)
   - Academic research datasets
   - Store in `profiles/iot-inspector/`

### Adding Custom Profiles

Create a JSON file in the appropriate profiles directory:

```json
{
  "name": "My Smart Device",
  "manufacturer": "Acme Corp",
  "model": "Smart Thing v2",
  "category": "smart_home",
  "mac_prefixes": ["AABBCC"],
  "hostnames": ["acme-device", "smartthing"],
  "dhcp_fingerprints": [],
  "allowed_domains": ["*.acmecorp.com"],
  "required_ports": [443, 8080],
  "data_source": "manual",
  "confidence": 1.0,
  "metadata": {
    "notes": "Requires cloud connection"
  }
}
```

## Alert Types

### Firmware Update Alerts

Triggered when a device firmware update is detected:
- Level: WARNING
- Type: `firmware_update`
- Includes: current version, new version, device info

### Resource Alerts

Triggered when system resources exceed thresholds:
- **CPU Alert**: Default threshold 80%
- **Memory Alert**: Default threshold 85%
- **Network Alert**: Monitors interface bandwidth

Levels:
- WARNING: Threshold exceeded by up to 20%
- CRITICAL: Threshold exceeded by more than 20%

## Storage Architecture

**IMPORTANT**: Do NOT store data on the Raspberry Pi. All data should be stored on network-attached storage or a remote server.

### Storage Paths

```
/mnt/network_storage/iot_manager/
├── devices.json          # Device registry
├── alerts.json           # Alert history
└── profiles/             # Device profiles
    ├── default_profiles.json
    ├── manual/
    ├── wireshark/
    ├── crowdsourced/
    └── iot-inspector/
```

### Backup Recommendations

- Daily backups of devices.json and alerts.json
- Version control for profile files
- Keep at least 30 days of alert history

## Troubleshooting

### No devices detected

1. Check ARP table: `arp -an`
2. Verify DHCP leases: `cat /var/db/dnsmasq.leases`
3. Ensure network interfaces are up: `ifconfig`

### Device not matching profile

1. Check MAC prefix: First 6 characters of MAC
2. Review hostname in DHCP leases
3. Add custom profile with correct MAC prefix

### Alerts not generating

1. Check storage path is writable
2. Verify resource monitoring is running
3. Review alert thresholds in configuration

### VLAN assignment issues

1. Verify available VLANs: `iot-mgr stats`
2. Check device database: `iot-mgr devices`
3. Ensure VLAN interfaces are configured in rc.conf

## Security Considerations

1. **Storage Security**: Store all data on encrypted network storage
2. **Access Control**: Restrict CLI access to root/admin users only
3. **Quarantine Policy**: Review quarantined devices regularly
4. **Alert Response**: Investigate all critical alerts within 24 hours
5. **Profile Updates**: Keep device profiles updated monthly

## Development

### Running Tests

```bash
cd /home/julian/homelab/bsd_router_test
python3 -m pytest tests/
```

### Project Structure

```
iot_manager/
├── __init__.py
├── alerts.py              # Alert management
├── cli.py                 # CLI interface
├── detection.py           # Device detection
├── device_database.py     # Device registry
├── device_profiles.py     # Profile management
├── monitoring.py          # Resource monitoring
└── profiles/              # Default profiles
    └── default_profiles.json
```

## License

See repository LICENSE file.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add device profiles to appropriate data source directory
4. Submit pull request with description

## Support

For issues and questions:
- Open GitHub issue: https://github.com/julianpryde/bsd_router_test/issues
- Review documentation: See IMPLEMENTATION_CHECKLIST.md and TOPOLOGY.md
