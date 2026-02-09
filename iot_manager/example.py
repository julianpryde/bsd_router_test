#!/usr/bin/env python3
"""
Example usage of IoT Manager components
Demonstrates basic functionality without requiring actual network scanning
"""

import sys
import os
import tempfile

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from iot_manager.device_database import DeviceDatabase
from iot_manager.device_profiles import DeviceProfileDatabase, DeviceProfile
from iot_manager.alerts import AlertManager, AlertType, AlertLevel


def example_device_management():
    """Example: Device database management"""
    print("=== Device Database Example ===\n")
    
    # Create temporary database
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as f:
        db_path = f.name
    
    try:
        # Initialize database
        db = DeviceDatabase(db_path)
        
        # Add some devices
        print("Adding devices...")
        devices = [
            {
                'mac': 'aa:bb:cc:dd:ee:01',
                'info': {
                    'name': 'Philips Hue Bridge',
                    'manufacturer': 'Philips',
                    'model': 'Hue Bridge v2',
                    'detected_timestamp': '2026-02-09T12:00:00'
                }
            },
            {
                'mac': 'aa:bb:cc:dd:ee:02',
                'info': {
                    'name': 'Google Home',
                    'manufacturer': 'Google',
                    'model': 'Google Home',
                    'detected_timestamp': '2026-02-09T12:01:00'
                }
            },
            {
                'mac': 'aa:bb:cc:dd:ee:03',
                'info': {
                    'name': 'Amazon Echo',
                    'manufacturer': 'Amazon',
                    'model': 'Echo Dot',
                    'detected_timestamp': '2026-02-09T12:02:00'
                }
            }
        ]
        
        for device in devices:
            vlan = db.add_device(device['mac'], device['info'])
            print(f"  Added {device['info']['name']} to VLAN {vlan}")
        
        # List devices
        print("\nAll devices:")
        for device in db.list_devices():
            print(f"  {device['mac_address']}: {device['name']} (VLAN {device['vlan_id']})")
        
        # Quarantine a device
        print("\nQuarantining device...")
        db.quarantine_device('aa:bb:cc:dd:ee:02', 'Suspicious traffic detected')
        
        # Show statistics
        stats = db.get_statistics()
        print(f"\nStatistics:")
        print(f"  Total devices: {stats['total_devices']}")
        print(f"  Active devices: {stats['active_devices']}")
        print(f"  Quarantined: {stats['quarantined_devices']}")
        print(f"  Available VLANs: {stats['available_vlans']}")
        
    finally:
        # Cleanup
        if os.path.exists(db_path):
            os.unlink(db_path)


def example_profile_matching():
    """Example: Device profile matching"""
    print("\n=== Device Profile Matching Example ===\n")
    
    # Create profile database with default profiles
    profiles_dir = os.path.join(os.path.dirname(__file__), 'profiles')
    profile_db = DeviceProfileDatabase(profiles_dir)
    
    print(f"Loaded {len(profile_db.profiles)} device profiles")
    
    # Test device matching
    test_devices = [
        {
            'mac': '00:17:88:aa:bb:cc',
            'hostname': 'philips-hue',
            'expected': 'Philips Hue Bridge'
        },
        {
            'mac': 'f4:f5:d8:11:22:33',
            'hostname': 'google-home',
            'expected': 'Google Home Speaker'
        },
        {
            'mac': '28:6d:97:44:55:66',
            'hostname': 'esp-sensor',
            'expected': 'ESP8266 IoT Device'
        }
    ]
    
    print("\nMatching test devices:")
    for device in test_devices:
        profile = profile_db.match_device(
            device['mac'],
            device.get('hostname')
        )
        
        if profile:
            match_status = "✓" if profile.name == device['expected'] else "✗"
            print(f"  {match_status} {device['mac']} → {profile.name} " +
                  f"(confidence: {profile.confidence:.2f})")
        else:
            print(f"  ✗ {device['mac']} → No match found")


def example_alert_management():
    """Example: Alert management"""
    print("\n=== Alert Management Example ===\n")
    
    # Create temporary alerts file
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as f:
        alerts_path = f.name
    
    try:
        # Initialize alert manager
        alert_mgr = AlertManager(alerts_path)
        
        # Create some alerts
        print("Creating alerts...")
        
        # Firmware update alert
        alert1 = alert_mgr.create_firmware_alert(
            'aa:bb:cc:dd:ee:01',
            'Philips Hue Bridge',
            {
                'current_version': '1.50.0',
                'new_version': '1.51.0',
                'release_notes_url': 'https://www.meethue.com/updates'
            }
        )
        print(f"  Created firmware alert: {alert1.id}")
        
        # Resource alert
        alert2 = alert_mgr.create_resource_alert(
            'cpu',
            85.5,
            80.0,
            'router'
        )
        print(f"  Created CPU alert: {alert2.id}")
        
        alert3 = alert_mgr.create_resource_alert(
            'memory',
            92.1,
            85.0,
            'router'
        )
        print(f"  Created memory alert: {alert3.id}")
        
        # List unresolved alerts
        print("\nUnresolved alerts:")
        for alert in alert_mgr.get_alerts(unresolved_only=True):
            level_icon = "🔴" if alert.level == "critical" else "⚠️"
            print(f"  {level_icon} [{alert.level.upper()}] {alert.message}")
        
        # Acknowledge and resolve
        print("\nAcknowledging alerts...")
        alert_mgr.acknowledge_alert(alert1.id)
        alert_mgr.resolve_alert(alert1.id)
        
        # Show statistics
        stats = alert_mgr.get_statistics()
        print(f"\nAlert Statistics:")
        print(f"  Total alerts: {stats['total_alerts']}")
        print(f"  Unresolved: {stats['unresolved_alerts']}")
        print(f"  Unacknowledged: {stats['unacknowledged_alerts']}")
        
        if stats['alerts_by_level']:
            print("  By level:")
            for level, count in stats['alerts_by_level'].items():
                print(f"    {level.upper()}: {count}")
    
    finally:
        # Cleanup
        if os.path.exists(alerts_path):
            os.unlink(alerts_path)


def main():
    """Run all examples"""
    print("IoT Manager - Example Usage\n")
    print("=" * 60)
    
    try:
        example_device_management()
        example_profile_matching()
        example_alert_management()
        
        print("\n" + "=" * 60)
        print("\n✓ All examples completed successfully!")
        print("\nTo use the CLI:")
        print("  ./iot_manager/cli.py --help")
        print("  ./iot_manager/cli.py devices")
        print("  ./iot_manager/cli.py alerts")
        
    except Exception as e:
        print(f"\n✗ Error running examples: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
