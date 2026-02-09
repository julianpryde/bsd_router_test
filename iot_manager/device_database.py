#!/usr/bin/env python3
"""
IoT Device Database Module
Manages device registry and VLAN assignments
"""

import json
import os
from datetime import datetime
from typing import Dict, List, Optional, Set


class DeviceDatabase:
    """
    Manages IoT device registry with VLAN assignments
    Supports up to 234 devices (VLAN 20-254, excluding VLAN 255 for quarantine)
    """
    
    VLAN_START = 20
    VLAN_END = 254
    QUARANTINE_VLAN = 255
    MAX_DEVICES = VLAN_END - VLAN_START + 1  # 235 VLANs (20-254)
    
    def __init__(self, db_path: str = None):
        """
        Initialize device database
        
        Args:
            db_path: Path to database file (JSON format)
                    If None, uses in-memory only (no persistence)
        """
        self.db_path = db_path
        self.devices: Dict[str, Dict] = {}  # MAC address -> device info
        self.vlan_assignments: Dict[str, int] = {}  # MAC address -> VLAN ID
        self.available_vlans: Set[int] = set(range(self.VLAN_START, self.VLAN_END + 1))
        
        if db_path and os.path.exists(db_path):
            self.load()
    
    def add_device(self, mac_address: str, device_info: Dict) -> Optional[int]:
        """
        Add a new device to the database and assign a VLAN
        
        Args:
            mac_address: MAC address of device (normalized format)
            device_info: Dictionary containing device details
                        Required fields: name, detected_timestamp
                        Optional fields: manufacturer, model, profile_name, etc.
        
        Returns:
            Assigned VLAN ID, or None if no VLANs available
        """
        mac_address = self._normalize_mac(mac_address)
        
        # Check if device already exists
        if mac_address in self.devices:
            return self.vlan_assignments.get(mac_address)
        
        # Check if we can support more devices
        if len(self.devices) >= self.MAX_DEVICES:
            raise ValueError(f"Maximum device limit ({self.MAX_DEVICES}) reached")
        
        # Assign a VLAN
        if not self.available_vlans:
            return None
        
        vlan_id = min(self.available_vlans)
        self.available_vlans.remove(vlan_id)
        
        # Add device info with metadata
        device_info['mac_address'] = mac_address
        device_info['vlan_id'] = vlan_id
        device_info['added_timestamp'] = datetime.utcnow().isoformat()
        device_info['quarantined'] = False
        
        self.devices[mac_address] = device_info
        self.vlan_assignments[mac_address] = vlan_id
        
        if self.db_path:
            self.save()
        
        return vlan_id
    
    def quarantine_device(self, mac_address: str, reason: str = None):
        """
        Move device to quarantine VLAN
        
        Args:
            mac_address: MAC address of device
            reason: Optional reason for quarantine
        """
        mac_address = self._normalize_mac(mac_address)
        
        if mac_address not in self.devices:
            raise KeyError(f"Device {mac_address} not found")
        
        # Save original VLAN
        original_vlan = self.vlan_assignments[mac_address]
        
        # Update to quarantine
        self.devices[mac_address]['quarantined'] = True
        self.devices[mac_address]['quarantine_timestamp'] = datetime.utcnow().isoformat()
        self.devices[mac_address]['original_vlan'] = original_vlan
        
        if reason:
            self.devices[mac_address]['quarantine_reason'] = reason
        
        self.vlan_assignments[mac_address] = self.QUARANTINE_VLAN
        
        if self.db_path:
            self.save()
    
    def unquarantine_device(self, mac_address: str):
        """
        Remove device from quarantine, restore to original VLAN
        
        Args:
            mac_address: MAC address of device
        """
        mac_address = self._normalize_mac(mac_address)
        
        if mac_address not in self.devices:
            raise KeyError(f"Device {mac_address} not found")
        
        if not self.devices[mac_address].get('quarantined'):
            return  # Already not quarantined
        
        # Restore original VLAN
        original_vlan = self.devices[mac_address].get('original_vlan')
        if original_vlan:
            self.vlan_assignments[mac_address] = original_vlan
        
        self.devices[mac_address]['quarantined'] = False
        self.devices[mac_address]['unquarantine_timestamp'] = datetime.utcnow().isoformat()
        
        if self.db_path:
            self.save()
    
    def get_device(self, mac_address: str) -> Optional[Dict]:
        """Get device information"""
        mac_address = self._normalize_mac(mac_address)
        return self.devices.get(mac_address)
    
    def get_vlan(self, mac_address: str) -> Optional[int]:
        """Get VLAN assignment for device"""
        mac_address = self._normalize_mac(mac_address)
        return self.vlan_assignments.get(mac_address)
    
    def list_devices(self, quarantined_only: bool = False) -> List[Dict]:
        """
        List all devices
        
        Args:
            quarantined_only: If True, only return quarantined devices
        
        Returns:
            List of device information dictionaries
        """
        devices = list(self.devices.values())
        
        if quarantined_only:
            devices = [d for d in devices if d.get('quarantined', False)]
        
        return devices
    
    def remove_device(self, mac_address: str):
        """
        Remove device from database and free its VLAN
        
        Args:
            mac_address: MAC address of device
        """
        mac_address = self._normalize_mac(mac_address)
        
        if mac_address not in self.devices:
            raise KeyError(f"Device {mac_address} not found")
        
        # Free the VLAN
        vlan_id = self.vlan_assignments[mac_address]
        if vlan_id != self.QUARANTINE_VLAN:
            self.available_vlans.add(vlan_id)
        
        # Remove device
        del self.devices[mac_address]
        del self.vlan_assignments[mac_address]
        
        if self.db_path:
            self.save()
    
    def save(self):
        """Save database to file"""
        if not self.db_path:
            return
        
        data = {
            'devices': self.devices,
            'vlan_assignments': self.vlan_assignments,
            'available_vlans': list(self.available_vlans),
            'last_updated': datetime.utcnow().isoformat()
        }
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        # Write atomically
        temp_path = self.db_path + '.tmp'
        with open(temp_path, 'w') as f:
            json.dump(data, f, indent=2)
        
        os.replace(temp_path, self.db_path)
    
    def load(self):
        """Load database from file"""
        if not self.db_path or not os.path.exists(self.db_path):
            return
        
        # Check if file is empty
        if os.path.getsize(self.db_path) == 0:
            return
        
        with open(self.db_path, 'r') as f:
            data = json.load(f)
        
        self.devices = data.get('devices', {})
        self.vlan_assignments = {k: int(v) for k, v in data.get('vlan_assignments', {}).items()}
        self.available_vlans = set(data.get('available_vlans', 
                                           range(self.VLAN_START, self.VLAN_END + 1)))
    
    def _normalize_mac(self, mac_address: str) -> str:
        """
        Normalize MAC address to lowercase, colon-separated format
        
        Args:
            mac_address: MAC address in any common format
        
        Returns:
            Normalized MAC address (e.g., "aa:bb:cc:dd:ee:ff")
        """
        # Remove common separators
        mac = mac_address.replace(':', '').replace('-', '').replace('.', '').lower()
        
        # Validate length
        if len(mac) != 12:
            raise ValueError(f"Invalid MAC address: {mac_address}")
        
        # Format with colons
        return ':'.join([mac[i:i+2] for i in range(0, 12, 2)])
    
    def get_statistics(self) -> Dict:
        """Get database statistics"""
        quarantined_count = sum(1 for d in self.devices.values() if d.get('quarantined', False))
        
        return {
            'total_devices': len(self.devices),
            'active_devices': len(self.devices) - quarantined_count,
            'quarantined_devices': quarantined_count,
            'available_vlans': len(self.available_vlans),
            'used_vlans': len(self.vlan_assignments) - quarantined_count,
            'max_devices': self.MAX_DEVICES
        }
