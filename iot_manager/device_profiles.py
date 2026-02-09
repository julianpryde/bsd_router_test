#!/usr/bin/env python3
"""
Device Profile Management
Stores and matches device profiles from various data sources
"""

import json
import os
from typing import Dict, List, Optional


class DeviceProfile:
    """Represents a known IoT device profile"""
    
    def __init__(self, profile_data: Dict):
        self.name = profile_data.get('name', 'Unknown Device')
        self.manufacturer = profile_data.get('manufacturer', 'Unknown')
        self.model = profile_data.get('model')
        self.category = profile_data.get('category', 'iot')
        self.mac_prefixes = profile_data.get('mac_prefixes', [])
        self.hostnames = profile_data.get('hostnames', [])
        self.dhcp_fingerprints = profile_data.get('dhcp_fingerprints', [])
        self.allowed_domains = profile_data.get('allowed_domains', [])
        self.required_ports = profile_data.get('required_ports', [])
        self.data_source = profile_data.get('data_source', 'manual')
        self.confidence = profile_data.get('confidence', 0.5)
        self.metadata = profile_data.get('metadata', {})
    
    def to_dict(self) -> Dict:
        """Convert profile to dictionary"""
        return {
            'name': self.name,
            'manufacturer': self.manufacturer,
            'model': self.model,
            'category': self.category,
            'mac_prefixes': self.mac_prefixes,
            'hostnames': self.hostnames,
            'dhcp_fingerprints': self.dhcp_fingerprints,
            'allowed_domains': self.allowed_domains,
            'required_ports': self.required_ports,
            'data_source': self.data_source,
            'confidence': self.confidence,
            'metadata': self.metadata
        }


class DeviceProfileDatabase:
    """
    Manages device profiles from multiple data sources
    Priority: manually curated > wireshark captures > crowdsourced > iot-inspector
    """
    
    DATA_SOURCE_PRIORITY = {
        'manual': 4,
        'wireshark': 3,
        'crowdsourced': 2,
        'iot-inspector': 1
    }
    
    def __init__(self, profiles_dir: str = None):
        """
        Initialize profile database
        
        Args:
            profiles_dir: Directory containing profile JSON files
        """
        self.profiles_dir = profiles_dir
        self.profiles: List[DeviceProfile] = []
        
        if profiles_dir and os.path.exists(profiles_dir):
            self.load_profiles()
    
    def load_profiles(self):
        """Load all profile files from profiles directory"""
        if not self.profiles_dir or not os.path.exists(self.profiles_dir):
            return
        
        for filename in os.listdir(self.profiles_dir):
            if filename.endswith('.json'):
                filepath = os.path.join(self.profiles_dir, filename)
                try:
                    with open(filepath, 'r') as f:
                        data = json.load(f)
                        
                        # Handle both single profile and array of profiles
                        if isinstance(data, list):
                            for profile_data in data:
                                self.profiles.append(DeviceProfile(profile_data))
                        else:
                            self.profiles.append(DeviceProfile(data))
                except Exception as e:
                    print(f"Error loading profile {filepath}: {e}")
    
    def add_profile(self, profile: DeviceProfile):
        """Add a profile to the database"""
        self.profiles.append(profile)
    
    def match_device(self, mac_address: str, hostname: str = None, 
                    dhcp_fingerprint: str = None) -> Optional[DeviceProfile]:
        """
        Match a device to a profile based on available information
        
        Args:
            mac_address: Device MAC address
            hostname: Optional device hostname from DHCP
            dhcp_fingerprint: Optional DHCP fingerprint
        
        Returns:
            Best matching profile, or None if no match found
        """
        matches = []
        
        # Get OUI (first 6 characters of MAC)
        mac_prefix = mac_address.replace(':', '')[:6].upper()
        
        for profile in self.profiles:
            score = 0
            
            # Check MAC prefix match
            for prefix in profile.mac_prefixes:
                if mac_prefix.startswith(prefix.upper()):
                    score += 10
                    break
            
            # Check hostname match
            if hostname and profile.hostnames:
                hostname_lower = hostname.lower()
                for pattern in profile.hostnames:
                    if pattern.lower() in hostname_lower:
                        score += 5
                        break
            
            # Check DHCP fingerprint
            if dhcp_fingerprint and profile.dhcp_fingerprints:
                if dhcp_fingerprint in profile.dhcp_fingerprints:
                    score += 8
            
            # Weight by data source priority and confidence
            source_priority = self.DATA_SOURCE_PRIORITY.get(profile.data_source, 1)
            weighted_score = score * source_priority * profile.confidence
            
            if weighted_score > 0:
                matches.append((weighted_score, profile))
        
        # Return best match
        if matches:
            matches.sort(reverse=True, key=lambda x: x[0])
            return matches[0][1]
        
        return None
    
    def get_profile_by_name(self, name: str) -> Optional[DeviceProfile]:
        """Get profile by device name"""
        for profile in self.profiles:
            if profile.name.lower() == name.lower():
                return profile
        return None
    
    def list_profiles(self, data_source: str = None, category: str = None) -> List[DeviceProfile]:
        """
        List profiles with optional filtering
        
        Args:
            data_source: Filter by data source
            category: Filter by category
        
        Returns:
            List of matching profiles
        """
        results = self.profiles
        
        if data_source:
            results = [p for p in results if p.data_source == data_source]
        
        if category:
            results = [p for p in results if p.category == category]
        
        return results
    
    def save_profile(self, profile: DeviceProfile, filename: str = None):
        """
        Save a profile to disk
        
        Args:
            profile: Profile to save
            filename: Optional filename, defaults to {manufacturer}_{model}.json
        """
        if not self.profiles_dir:
            raise ValueError("No profiles directory configured")
        
        os.makedirs(self.profiles_dir, exist_ok=True)
        
        if not filename:
            safe_name = f"{profile.manufacturer}_{profile.model}".replace(' ', '_').lower()
            filename = f"{safe_name}.json"
        
        filepath = os.path.join(self.profiles_dir, filename)
        
        with open(filepath, 'w') as f:
            json.dump(profile.to_dict(), f, indent=2)
