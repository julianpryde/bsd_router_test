#!/usr/bin/env python3
"""
CLI Interface for IoT Device Management
Simple command-line interface for reviewing alerts and managing devices
"""

import argparse
import sys
import os
from typing import List
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from iot_manager.device_database import DeviceDatabase
from iot_manager.device_profiles import DeviceProfileDatabase
from iot_manager.alerts import AlertManager, AlertLevel, AlertType
from iot_manager.detection import DeviceDetector


# Default paths (can be overridden via config or environment)
DEFAULT_DB_PATH = '/var/db/iot_manager/devices.json'
DEFAULT_ALERTS_PATH = '/var/db/iot_manager/alerts.json'
DEFAULT_PROFILES_DIR = '/var/db/iot_manager/profiles'


class IoTCLI:
    """Command-line interface for IoT management"""
    
    def __init__(self, db_path: str = None, alerts_path: str = None, profiles_dir: str = None):
        self.db_path = db_path or os.environ.get('IOT_DB_PATH', DEFAULT_DB_PATH)
        self.alerts_path = alerts_path or os.environ.get('IOT_ALERTS_PATH', DEFAULT_ALERTS_PATH)
        self.profiles_dir = profiles_dir or os.environ.get('IOT_PROFILES_DIR', DEFAULT_PROFILES_DIR)
        
        self.device_db = DeviceDatabase(self.db_path)
        self.alert_mgr = AlertManager(self.alerts_path)
        self.profile_db = DeviceProfileDatabase(self.profiles_dir)
        self.detector = DeviceDetector()
    
    def cmd_list_devices(self, args):
        """List all devices"""
        devices = self.device_db.list_devices(quarantined_only=args.quarantined_only)
        
        if not devices:
            print("No devices found.")
            return
        
        # Print header
        print(f"{'MAC Address':<20} {'Name':<25} {'VLAN':<6} {'Status':<12} {'Manufacturer':<20}")
        print("-" * 90)
        
        # Print devices
        for device in devices:
            mac = device.get('mac_address', 'N/A')
            name = device.get('name', 'Unknown')[:24]
            vlan = device.get('vlan_id', 'N/A')
            status = 'QUARANTINED' if device.get('quarantined') else 'Active'
            manufacturer = device.get('manufacturer', 'Unknown')[:19]
            
            print(f"{mac:<20} {name:<25} {vlan:<6} {status:<12} {manufacturer:<20}")
        
        # Print statistics
        stats = self.device_db.get_statistics()
        print(f"\nTotal: {stats['total_devices']} | Active: {stats['active_devices']} | " +
              f"Quarantined: {stats['quarantined_devices']} | Available VLANs: {stats['available_vlans']}")
    
    def cmd_show_device(self, args):
        """Show detailed device information"""
        device = self.device_db.get_device(args.mac_address)
        
        if not device:
            print(f"Device {args.mac_address} not found.")
            return 1
        
        print(f"\nDevice Information:")
        print(f"  MAC Address:    {device.get('mac_address')}")
        print(f"  Name:           {device.get('name', 'Unknown')}")
        print(f"  Manufacturer:   {device.get('manufacturer', 'Unknown')}")
        print(f"  Model:          {device.get('model', 'Unknown')}")
        print(f"  VLAN ID:        {device.get('vlan_id')}")
        print(f"  Status:         {'QUARANTINED' if device.get('quarantined') else 'Active'}")
        print(f"  Added:          {device.get('added_timestamp', 'Unknown')}")
        
        if device.get('quarantined'):
            print(f"  Quarantine Reason: {device.get('quarantine_reason', 'N/A')}")
            print(f"  Quarantined At:    {device.get('quarantine_timestamp', 'N/A')}")
        
        if device.get('profile_name'):
            print(f"  Profile:        {device.get('profile_name')}")
    
    def cmd_list_alerts(self, args):
        """List alerts"""
        alerts = self.alert_mgr.get_alerts(
            alert_type=args.type,
            level=args.level,
            unresolved_only=args.unresolved_only,
            limit=args.limit
        )
        
        if not alerts:
            print("No alerts found.")
            return
        
        # Print header
        print(f"{'ID':<16} {'Time':<20} {'Level':<10} {'Type':<20} {'Message':<50}")
        print("-" * 120)
        
        # Print alerts
        for alert in alerts:
            alert_id = alert.id[:14]
            timestamp = alert.timestamp[:19].replace('T', ' ')
            level = alert.level.upper()
            alert_type = alert.alert_type
            message = alert.message[:49]
            
            # Color coding (if terminal supports it)
            if level == 'CRITICAL':
                level_str = f"\033[91m{level}\033[0m"  # Red
            elif level == 'WARNING':
                level_str = f"\033[93m{level}\033[0m"  # Yellow
            else:
                level_str = level
            
            status = ''
            if alert.resolved:
                status = ' [RESOLVED]'
            elif alert.acknowledged:
                status = ' [ACK]'
            
            print(f"{alert_id:<16} {timestamp:<20} {level_str:<10} {alert_type:<20} {message:<50}{status}")
        
        # Print statistics
        stats = self.alert_mgr.get_statistics()
        print(f"\nTotal: {stats['total_alerts']} | Unresolved: {stats['unresolved_alerts']} | " +
              f"Unacknowledged: {stats['unacknowledged_alerts']}")
    
    def cmd_show_alert(self, args):
        """Show detailed alert information"""
        alerts = self.alert_mgr.get_alerts()
        
        # Find alert by ID (allow partial match)
        matching_alert = None
        for alert in alerts:
            if alert.id.startswith(args.alert_id):
                matching_alert = alert
                break
        
        if not matching_alert:
            print(f"Alert {args.alert_id} not found.")
            return 1
        
        print(f"\nAlert Details:")
        print(f"  ID:           {matching_alert.id}")
        print(f"  Timestamp:    {matching_alert.timestamp}")
        print(f"  Type:         {matching_alert.alert_type}")
        print(f"  Level:        {matching_alert.level.upper()}")
        print(f"  Message:      {matching_alert.message}")
        print(f"  Acknowledged: {'Yes' if matching_alert.acknowledged else 'No'}")
        print(f"  Resolved:     {'Yes' if matching_alert.resolved else 'No'}")
        
        if matching_alert.device_mac:
            print(f"  Device MAC:   {matching_alert.device_mac}")
        
        if matching_alert.metadata:
            print(f"  Metadata:")
            for key, value in matching_alert.metadata.items():
                print(f"    {key}: {value}")
    
    def cmd_acknowledge_alert(self, args):
        """Acknowledge an alert"""
        if self.alert_mgr.acknowledge_alert(args.alert_id):
            print(f"Alert {args.alert_id} acknowledged.")
        else:
            print(f"Alert {args.alert_id} not found.")
            return 1
    
    def cmd_resolve_alert(self, args):
        """Resolve an alert"""
        if self.alert_mgr.resolve_alert(args.alert_id):
            print(f"Alert {args.alert_id} resolved.")
        else:
            print(f"Alert {args.alert_id} not found.")
            return 1
    
    def cmd_quarantine(self, args):
        """Quarantine a device"""
        try:
            self.device_db.quarantine_device(args.mac_address, args.reason)
            print(f"Device {args.mac_address} quarantined.")
        except KeyError as e:
            print(f"Error: {e}")
            return 1
    
    def cmd_unquarantine(self, args):
        """Remove device from quarantine"""
        try:
            self.device_db.unquarantine_device(args.mac_address)
            print(f"Device {args.mac_address} removed from quarantine.")
        except KeyError as e:
            print(f"Error: {e}")
            return 1
    
    def cmd_detect(self, args):
        """Detect new devices on network"""
        print("Scanning for devices...")
        devices = self.detector.detect_devices()
        
        print(f"\nFound {len(devices)} device(s):")
        
        new_devices = []
        for device in devices:
            mac = device['mac_address']
            existing = self.device_db.get_device(mac)
            
            if not existing:
                # Check if it's an IoT device
                is_iot, confidence = self.detector.is_iot_device(device)
                
                if is_iot or args.all:
                    new_devices.append(device)
                    
                    status = "NEW IoT device" if is_iot else "NEW device"
                    print(f"  {mac} - {device.get('hostname', 'Unknown')} - {status} (confidence: {confidence:.2f})")
        
        if new_devices and not args.dry_run:
            print(f"\nAdding {len(new_devices)} new device(s) to database...")
            for device in new_devices:
                mac = device['mac_address']
                
                # Match to profile
                profile = self.profile_db.match_device(
                    mac,
                    device.get('hostname'),
                    device.get('dhcp_fingerprint')
                )
                
                device_info = {
                    'name': device.get('hostname', f"Device-{mac[-8:]}"),
                    'detected_timestamp': device['detected_timestamp'],
                    'manufacturer': device.get('manufacturer', 'Unknown'),
                    'ip_address': device.get('ip_address'),
                }
                
                if profile:
                    device_info['profile_name'] = profile.name
                    device_info['model'] = profile.model
                    device_info['category'] = profile.category
                
                vlan = self.device_db.add_device(mac, device_info)
                print(f"  Added {mac} to VLAN {vlan}")
        
        elif new_devices and args.dry_run:
            print(f"\n(Dry run - not adding devices to database)")
    
    def cmd_stats(self, args):
        """Show system statistics"""
        device_stats = self.device_db.get_statistics()
        alert_stats = self.alert_mgr.get_statistics()
        
        print("\n=== Device Statistics ===")
        print(f"  Total Devices:       {device_stats['total_devices']}")
        print(f"  Active Devices:      {device_stats['active_devices']}")
        print(f"  Quarantined:         {device_stats['quarantined_devices']}")
        print(f"  Available VLANs:     {device_stats['available_vlans']}")
        print(f"  Maximum Devices:     {device_stats['max_devices']}")
        
        print("\n=== Alert Statistics ===")
        print(f"  Total Alerts:        {alert_stats['total_alerts']}")
        print(f"  Unresolved:          {alert_stats['unresolved_alerts']}")
        print(f"  Unacknowledged:      {alert_stats['unacknowledged_alerts']}")
        
        if alert_stats['alerts_by_level']:
            print("\n  By Level:")
            for level, count in alert_stats['alerts_by_level'].items():
                print(f"    {level.upper():<12} {count}")
        
        if alert_stats['alerts_by_type']:
            print("\n  By Type:")
            for atype, count in alert_stats['alerts_by_type'].items():
                print(f"    {atype:<20} {count}")


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(description='IoT Device Management CLI')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Device commands
    devices_parser = subparsers.add_parser('devices', aliases=['dev'], help='List devices')
    devices_parser.add_argument('--quarantined-only', action='store_true', 
                               help='Show only quarantined devices')
    
    show_device_parser = subparsers.add_parser('show-device', aliases=['show'], help='Show device details')
    show_device_parser.add_argument('mac_address', help='Device MAC address')
    
    # Alert commands
    alerts_parser = subparsers.add_parser('alerts', help='List alerts')
    alerts_parser.add_argument('--type', help='Filter by alert type')
    alerts_parser.add_argument('--level', help='Filter by alert level')
    alerts_parser.add_argument('--unresolved-only', action='store_true', 
                              help='Show only unresolved alerts')
    alerts_parser.add_argument('--limit', type=int, default=50, help='Maximum alerts to show')
    
    show_alert_parser = subparsers.add_parser('show-alert', help='Show alert details')
    show_alert_parser.add_argument('alert_id', help='Alert ID (or prefix)')
    
    ack_parser = subparsers.add_parser('ack', help='Acknowledge alert')
    ack_parser.add_argument('alert_id', help='Alert ID')
    
    resolve_parser = subparsers.add_parser('resolve', help='Resolve alert')
    resolve_parser.add_argument('alert_id', help='Alert ID')
    
    # Quarantine commands
    quarantine_parser = subparsers.add_parser('quarantine', help='Quarantine device')
    quarantine_parser.add_argument('mac_address', help='Device MAC address')
    quarantine_parser.add_argument('--reason', help='Reason for quarantine')
    
    unquarantine_parser = subparsers.add_parser('unquarantine', help='Remove device from quarantine')
    unquarantine_parser.add_argument('mac_address', help='Device MAC address')
    
    # Detection commands
    detect_parser = subparsers.add_parser('detect', aliases=['scan'], help='Detect devices on network')
    detect_parser.add_argument('--all', action='store_true', 
                              help='Detect all devices, not just IoT')
    detect_parser.add_argument('--dry-run', action='store_true', 
                              help='Show devices but do not add to database')
    
    # Statistics
    stats_parser = subparsers.add_parser('stats', help='Show statistics')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 0
    
    # Initialize CLI
    cli = IoTCLI()
    
    # Execute command
    command_map = {
        'devices': cli.cmd_list_devices,
        'dev': cli.cmd_list_devices,
        'show-device': cli.cmd_show_device,
        'show': cli.cmd_show_device,
        'alerts': cli.cmd_list_alerts,
        'show-alert': cli.cmd_show_alert,
        'ack': cli.cmd_acknowledge_alert,
        'resolve': cli.cmd_resolve_alert,
        'quarantine': cli.cmd_quarantine,
        'unquarantine': cli.cmd_unquarantine,
        'detect': cli.cmd_detect,
        'scan': cli.cmd_detect,
        'stats': cli.cmd_stats,
    }
    
    command_func = command_map.get(args.command)
    if command_func:
        return command_func(args) or 0
    else:
        print(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
