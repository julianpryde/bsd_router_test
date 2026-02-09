#!/usr/bin/env python3
"""
Device Detection Module
Detects IoT devices on the network and matches them to profiles
"""

import subprocess
import re
from typing import Dict, List, Optional, Tuple
from datetime import datetime


class DeviceDetector:
    """
    Detects IoT devices on the network
    Uses ARP, DHCP logs, and packet capture for detection
    """
    
    def __init__(self):
        self.detected_devices: Dict[str, Dict] = {}
    
    def scan_arp_table(self) -> List[Dict]:
        """
        Scan ARP table for connected devices
        
        Returns:
            List of devices with MAC and IP addresses
        """
        devices = []
        
        try:
            # Run arp command (works on both FreeBSD and Linux)
            result = subprocess.run(['arp', '-an'], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                # Parse ARP output
                # Format: ? (192.168.1.10) at aa:bb:cc:dd:ee:ff on em1 expires in 1199 seconds [ethernet]
                for line in result.stdout.splitlines():
                    match = re.search(r'\(([0-9.]+)\)\s+at\s+([0-9a-f:]+)', line, re.IGNORECASE)
                    if match:
                        ip_address = match.group(1)
                        mac_address = match.group(2).lower()
                        
                        # Extract interface name if present
                        interface = None
                        if_match = re.search(r'on\s+(\w+)', line)
                        if if_match:
                            interface = if_match.group(1)
                        
                        devices.append({
                            'mac_address': mac_address,
                            'ip_address': ip_address,
                            'interface': interface,
                            'detected_timestamp': datetime.utcnow().isoformat(),
                            'detection_method': 'arp'
                        })
        
        except Exception as e:
            print(f"Error scanning ARP table: {e}")
        
        return devices
    
    def parse_dhcp_leases(self, dhcp_leases_file: str = '/var/db/dnsmasq.leases') -> List[Dict]:
        """
        Parse DHCP leases file for device information
        
        Args:
            dhcp_leases_file: Path to dnsmasq leases file
        
        Returns:
            List of devices with DHCP information
        """
        devices = []
        
        try:
            with open(dhcp_leases_file, 'r') as f:
                for line in f:
                    # dnsmasq lease format: timestamp mac_address ip_address hostname client_id
                    parts = line.strip().split()
                    if len(parts) >= 4:
                        timestamp = parts[0]
                        mac_address = parts[1].lower()
                        ip_address = parts[2]
                        hostname = parts[3] if parts[3] != '*' else None
                        
                        devices.append({
                            'mac_address': mac_address,
                            'ip_address': ip_address,
                            'hostname': hostname,
                            'lease_timestamp': timestamp,
                            'detected_timestamp': datetime.utcnow().isoformat(),
                            'detection_method': 'dhcp'
                        })
        
        except FileNotFoundError:
            print(f"DHCP leases file not found: {dhcp_leases_file}")
        except Exception as e:
            print(f"Error parsing DHCP leases: {e}")
        
        return devices
    
    def get_manufacturer_from_mac(self, mac_address: str) -> Optional[str]:
        """
        Get manufacturer from MAC address OUI
        
        Args:
            mac_address: MAC address
        
        Returns:
            Manufacturer name or None if not found
        """
        # OUI (first 3 octets) to manufacturer mapping
        # This is a simplified version - in production, use IEEE OUI database
        oui_map = {
            '00:50:f2': 'Microsoft',
            '00:17:88': 'Philips Hue',
            '00:0c:29': 'VMware',
            'b8:27:eb': 'Raspberry Pi',
            'dc:a6:32': 'Raspberry Pi',
            '98:01:a7': 'Apple',
            '00:1e:c2': 'Apple',
            'ac:bc:32': 'Apple',
            '00:e0:4c': 'Realtek',
            '28:6d:97': 'Espressif (IoT)',
            '5c:cf:7f': 'Espressif (IoT)',
            'a4:cf:12': 'Espressif (IoT)',
        }
        
        # Get OUI (first 8 characters in format aa:bb:cc)
        mac_normalized = mac_address.replace('-', ':').replace('.', ':').lower()
        oui = ':'.join(mac_normalized.split(':')[:3])
        
        return oui_map.get(oui)
    
    def detect_devices(self, dhcp_leases_file: str = '/var/db/dnsmasq.leases') -> List[Dict]:
        """
        Detect all devices using available methods
        
        Args:
            dhcp_leases_file: Path to DHCP leases file
        
        Returns:
            List of detected devices with all available information
        """
        # Scan using different methods
        arp_devices = self.scan_arp_table()
        dhcp_devices = self.parse_dhcp_leases(dhcp_leases_file)
        
        # Merge device information by MAC address
        device_map = {}
        
        for device in arp_devices + dhcp_devices:
            mac = device['mac_address']
            if mac not in device_map:
                device_map[mac] = device
            else:
                # Merge information
                device_map[mac].update(device)
        
        # Add manufacturer information
        for mac, device in device_map.items():
            if 'manufacturer' not in device:
                manufacturer = self.get_manufacturer_from_mac(mac)
                if manufacturer:
                    device['manufacturer'] = manufacturer
        
        return list(device_map.values())
    
    def is_iot_device(self, device: Dict) -> Tuple[bool, float]:
        """
        Heuristic to determine if a device is likely an IoT device
        
        Args:
            device: Device information dictionary
        
        Returns:
            Tuple of (is_iot, confidence_score)
        """
        score = 0.0
        
        # Check manufacturer
        iot_manufacturers = ['philips hue', 'espressif', 'tuya', 'sonoff', 'nest', 'ring', 
                            'wyze', 'tp-link', 'xiaomi', 'amazon', 'google']
        manufacturer = device.get('manufacturer', '').lower()
        for iot_mfg in iot_manufacturers:
            if iot_mfg in manufacturer:
                score += 0.4
                break
        
        # Check hostname patterns
        hostname = device.get('hostname', '').lower()
        iot_patterns = ['bulb', 'light', 'cam', 'sensor', 'thermostat', 'plug', 
                       'switch', 'hub', 'bridge', 'speaker', 'alexa', 'echo']
        for pattern in iot_patterns:
            if pattern in hostname:
                score += 0.3
                break
        
        # IoT devices typically don't have common computer patterns
        computer_patterns = ['pc', 'desktop', 'laptop', 'macbook', 'iphone', 'ipad', 'android']
        is_computer = any(p in hostname for p in computer_patterns)
        
        if not is_computer:
            score += 0.2
        else:
            score -= 0.3
        
        # Confidence clipping
        confidence = max(0.0, min(1.0, score))
        is_iot = confidence >= 0.5
        
        return is_iot, confidence
