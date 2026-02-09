#!/bin/sh
# IoT Manager Deployment Script for FreeBSD
# This script installs and configures the IoT device management system

set -e

# Configuration
INSTALL_DIR="/usr/local/share/iot_manager"
BIN_DIR="/usr/local/bin"
SBIN_DIR="/usr/local/sbin"
CONFIG_DIR="/usr/local/etc/iot_manager"
STORAGE_PATH="/mnt/network_storage/iot_manager"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 is required but not installed"
        print_info "Install with: pkg install python3"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
    print_info "Found Python $PYTHON_VERSION"
}

create_directories() {
    print_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$STORAGE_PATH"
    mkdir -p "$STORAGE_PATH/profiles/manual"
    mkdir -p "$STORAGE_PATH/profiles/wireshark"
    mkdir -p "$STORAGE_PATH/profiles/crowdsourced"
    mkdir -p "$STORAGE_PATH/profiles/iot-inspector"
    
    print_info "Directories created"
}

install_files() {
    print_info "Installing IoT Manager files..."
    
    # Determine source directory
    SCRIPT_DIR=$(dirname "$0")
    SOURCE_DIR="$SCRIPT_DIR/.."
    
    # Copy Python modules
    cp "$SOURCE_DIR"/*.py "$INSTALL_DIR/" 2>/dev/null || true
    
    # Copy documentation
    cp "$SOURCE_DIR"/README.md "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SOURCE_DIR"/INTEGRATION.md "$INSTALL_DIR/" 2>/dev/null || true
    
    # Copy profiles
    if [ -d "$SOURCE_DIR/profiles" ]; then
        cp "$SOURCE_DIR/profiles/default_profiles.json" "$STORAGE_PATH/profiles/" 2>/dev/null || true
    fi
    
    # Make CLI executable
    chmod +x "$INSTALL_DIR/cli.py"
    
    # Create symlink
    ln -sf "$INSTALL_DIR/cli.py" "$BIN_DIR/iot-mgr"
    
    print_info "Files installed"
}

create_config() {
    print_info "Creating configuration file..."
    
    cat > "$CONFIG_DIR/config.env" << EOF
# IoT Manager Configuration
IOT_DB_PATH="$STORAGE_PATH/devices.json"
IOT_ALERTS_PATH="$STORAGE_PATH/alerts.json"
IOT_PROFILES_DIR="$STORAGE_PATH/profiles"

# Scan interval (seconds)
IOT_SCAN_INTERVAL=300

# Resource monitoring thresholds
IOT_CPU_THRESHOLD=80
IOT_MEMORY_THRESHOLD=85

# Export for scripts
export IOT_DB_PATH
export IOT_ALERTS_PATH
export IOT_PROFILES_DIR
export IOT_SCAN_INTERVAL
export IOT_CPU_THRESHOLD
export IOT_MEMORY_THRESHOLD
EOF
    
    print_info "Configuration created at $CONFIG_DIR/config.env"
}

create_detection_service() {
    print_info "Creating detection service..."
    
    cat > "$SBIN_DIR/iot_detect_daemon.py" << 'EOF'
#!/usr/bin/env python3
"""IoT Device Detection Daemon"""
import sys
import time
import os

sys.path.insert(0, '/usr/local/share/iot_manager')

from device_database import DeviceDatabase
from device_profiles import DeviceProfileDatabase
from detection import DeviceDetector
from alerts import AlertManager, AlertType, AlertLevel

DB_PATH = os.environ.get('IOT_DB_PATH', '/mnt/network_storage/iot_manager/devices.json')
ALERTS_PATH = os.environ.get('IOT_ALERTS_PATH', '/mnt/network_storage/iot_manager/alerts.json')
PROFILES_DIR = os.environ.get('IOT_PROFILES_DIR', '/mnt/network_storage/iot_manager/profiles')
SCAN_INTERVAL = int(os.environ.get('IOT_SCAN_INTERVAL', '300'))

def main():
    device_db = DeviceDatabase(DB_PATH)
    profile_db = DeviceProfileDatabase(PROFILES_DIR)
    detector = DeviceDetector()
    alert_mgr = AlertManager(ALERTS_PATH)
    
    print(f"IoT Detection Daemon started (interval: {SCAN_INTERVAL}s)")
    
    while True:
        try:
            devices = detector.detect_devices()
            
            for device in devices:
                mac = device['mac_address']
                existing = device_db.get_device(mac)
                
                if not existing:
                    is_iot, confidence = detector.is_iot_device(device)
                    
                    if is_iot and confidence >= 0.6:
                        profile = profile_db.match_device(
                            mac, device.get('hostname'), device.get('dhcp_fingerprint')
                        )
                        
                        device_info = {
                            'name': device.get('hostname', f"Device-{mac[-8:]}"),
                            'detected_timestamp': device['detected_timestamp'],
                            'manufacturer': device.get('manufacturer', 'Unknown'),
                            'ip_address': device.get('ip_address'),
                        }
                        
                        if profile:
                            device_info.update({
                                'profile_name': profile.name,
                                'model': profile.model,
                                'category': profile.category
                            })
                        
                        vlan = device_db.add_device(mac, device_info)
                        
                        alert_mgr.create_alert(
                            AlertType.DEVICE_BEHAVIOR, AlertLevel.INFO,
                            f"New IoT device detected: {device_info['name']}",
                            mac, {'vlan_id': vlan, 'confidence': confidence}
                        )
                        
                        print(f"Added: {mac} -> VLAN {vlan}")
            
        except Exception as e:
            print(f"Error: {e}")
        
        time.sleep(SCAN_INTERVAL)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "$SBIN_DIR/iot_detect_daemon.py"
    print_info "Detection daemon created"
}

create_monitoring_script() {
    print_info "Creating monitoring script..."
    
    cat > "$SBIN_DIR/iot_monitor.sh" << 'EOF'
#!/bin/sh
. /usr/local/etc/iot_manager/config.env

/usr/bin/env python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/usr/local/share/iot_manager')

from monitoring import ResourceMonitor
from alerts import AlertManager
import os

monitor = ResourceMonitor(
    cpu_threshold=float(os.environ.get('IOT_CPU_THRESHOLD', '80')),
    memory_threshold=float(os.environ.get('IOT_MEMORY_THRESHOLD', '85'))
)
alert_mgr = AlertManager(os.environ.get('IOT_ALERTS_PATH'))

results = monitor.check_resources(hostname='router')

for alert_info in results.get('alerts', []):
    alert_mgr.create_resource_alert(
        alert_info['resource'], alert_info['value'],
        alert_info['threshold'], 'router'
    )
PYTHON_SCRIPT
EOF
    
    chmod +x "$SBIN_DIR/iot_monitor.sh"
    print_info "Monitoring script created"
}

setup_cron() {
    print_info "Cron job suggestions..."
    echo ""
    echo "Add these lines to /etc/crontab:"
    echo "# IoT Device Management"
    echo "*/5 * * * * root . /usr/local/etc/iot_manager/config.env && /usr/local/sbin/iot_detect_daemon.py >> /var/log/iot_detect.log 2>&1 &"
    echo "*/15 * * * * root . /usr/local/etc/iot_manager/config.env && /usr/local/sbin/iot_monitor.sh >> /var/log/iot_monitor.log 2>&1"
    echo ""
}

print_summary() {
    echo ""
    print_info "============================================"
    print_info "IoT Manager Installation Complete!"
    print_info "============================================"
    echo ""
    print_info "Configuration: $CONFIG_DIR/config.env"
    print_info "Storage: $STORAGE_PATH"
    print_info "CLI: iot-mgr"
    echo ""
    print_info "Next steps:"
    echo "  1. Ensure network storage mounted at $STORAGE_PATH"
    echo "  2. Edit $CONFIG_DIR/config.env if needed"
    echo "  3. Add cron jobs (see above)"
    echo "  4. Test: iot-mgr detect --dry-run"
    echo "  5. View: iot-mgr stats"
    echo ""
}

# Main
main() {
    print_info "IoT Manager Deployment"
    print_info "======================"
    echo ""
    
    check_root
    check_python
    create_directories
    install_files
    create_config
    create_detection_service
    create_monitoring_script
    setup_cron
    print_summary
}

main
