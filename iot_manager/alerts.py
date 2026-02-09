#!/usr/bin/env python3
"""
Alert Management System
Handles firmware update alerts, resource monitoring, and notifications
"""

import json
import os
from datetime import datetime
from typing import Dict, List, Optional
from enum import Enum


class AlertLevel(Enum):
    """Alert severity levels"""
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


class AlertType(Enum):
    """Types of alerts"""
    FIRMWARE_UPDATE = "firmware_update"
    RESOURCE_CPU = "resource_cpu"
    RESOURCE_MEMORY = "resource_memory"
    RESOURCE_NETWORK = "resource_network"
    DEVICE_BEHAVIOR = "device_behavior"
    SECURITY = "security"


class Alert:
    """Represents a single alert"""
    
    def __init__(self, alert_type: AlertType, level: AlertLevel, message: str,
                 device_mac: str = None, metadata: Dict = None):
        self.id = datetime.utcnow().strftime('%Y%m%d%H%M%S%f')
        self.timestamp = datetime.utcnow().isoformat()
        self.alert_type = alert_type.value
        self.level = level.value
        self.message = message
        self.device_mac = device_mac
        self.metadata = metadata or {}
        self.acknowledged = False
        self.resolved = False
    
    def to_dict(self) -> Dict:
        """Convert alert to dictionary"""
        return {
            'id': self.id,
            'timestamp': self.timestamp,
            'alert_type': self.alert_type,
            'level': self.level,
            'message': self.message,
            'device_mac': self.device_mac,
            'metadata': self.metadata,
            'acknowledged': self.acknowledged,
            'resolved': self.resolved
        }
    
    @classmethod
    def from_dict(cls, data: Dict) -> 'Alert':
        """Create alert from dictionary"""
        alert = cls(
            AlertType(data['alert_type']),
            AlertLevel(data['level']),
            data['message'],
            data.get('device_mac'),
            data.get('metadata', {})
        )
        alert.id = data['id']
        alert.timestamp = data['timestamp']
        alert.acknowledged = data.get('acknowledged', False)
        alert.resolved = data.get('resolved', False)
        return alert


class AlertManager:
    """
    Manages alerts for IoT device management system
    Stores alerts remotely (not on Raspberry Pi)
    """
    
    def __init__(self, storage_path: str = None):
        """
        Initialize alert manager
        
        Args:
            storage_path: Path to alert storage file (JSON format)
                         Should be on network storage, not local Raspberry Pi
        """
        self.storage_path = storage_path
        self.alerts: List[Alert] = []
        
        if storage_path and os.path.exists(storage_path):
            self.load()
    
    def create_alert(self, alert_type: AlertType, level: AlertLevel, message: str,
                    device_mac: str = None, metadata: Dict = None) -> Alert:
        """
        Create a new alert
        
        Args:
            alert_type: Type of alert
            level: Severity level
            message: Alert message
            device_mac: Optional MAC address of affected device
            metadata: Optional additional information
        
        Returns:
            Created alert object
        """
        alert = Alert(alert_type, level, message, device_mac, metadata)
        self.alerts.append(alert)
        
        if self.storage_path:
            self.save()
        
        return alert
    
    def create_firmware_alert(self, device_mac: str, device_name: str, 
                             firmware_info: Dict) -> Alert:
        """
        Create a firmware update alert
        
        Args:
            device_mac: Device MAC address
            device_name: Device name
            firmware_info: Dictionary with 'current_version', 'new_version', etc.
        """
        message = f"Firmware update available for {device_name}"
        return self.create_alert(
            AlertType.FIRMWARE_UPDATE,
            AlertLevel.WARNING,
            message,
            device_mac,
            firmware_info
        )
    
    def create_resource_alert(self, resource_type: str, value: float, 
                             threshold: float, hostname: str) -> Alert:
        """
        Create a resource monitoring alert
        
        Args:
            resource_type: Type of resource (cpu, memory, network)
            value: Current value
            threshold: Threshold that was exceeded
            hostname: Affected hostname
        """
        message = f"{resource_type.upper()} usage at {value:.1f}% (threshold: {threshold}%) on {hostname}"
        
        alert_type_map = {
            'cpu': AlertType.RESOURCE_CPU,
            'memory': AlertType.RESOURCE_MEMORY,
            'network': AlertType.RESOURCE_NETWORK
        }
        
        level = AlertLevel.WARNING if value < threshold * 1.2 else AlertLevel.CRITICAL
        
        return self.create_alert(
            alert_type_map.get(resource_type, AlertType.RESOURCE_CPU),
            level,
            message,
            metadata={'resource_type': resource_type, 'value': value, 'threshold': threshold, 'hostname': hostname}
        )
    
    def get_alerts(self, alert_type: str = None, level: str = None,
                   device_mac: str = None, unresolved_only: bool = False,
                   limit: int = None) -> List[Alert]:
        """
        Get alerts with optional filtering
        
        Args:
            alert_type: Filter by alert type
            level: Filter by severity level
            device_mac: Filter by device MAC address
            unresolved_only: Only return unresolved alerts
            limit: Maximum number of alerts to return
        
        Returns:
            List of matching alerts
        """
        results = self.alerts
        
        if alert_type:
            results = [a for a in results if a.alert_type == alert_type]
        
        if level:
            results = [a for a in results if a.level == level]
        
        if device_mac:
            results = [a for a in results if a.device_mac == device_mac]
        
        if unresolved_only:
            results = [a for a in results if not a.resolved]
        
        # Sort by timestamp (newest first)
        results.sort(key=lambda a: a.timestamp, reverse=True)
        
        if limit:
            results = results[:limit]
        
        return results
    
    def acknowledge_alert(self, alert_id: str):
        """Mark an alert as acknowledged"""
        for alert in self.alerts:
            if alert.id == alert_id:
                alert.acknowledged = True
                if self.storage_path:
                    self.save()
                return True
        return False
    
    def resolve_alert(self, alert_id: str):
        """Mark an alert as resolved"""
        for alert in self.alerts:
            if alert.id == alert_id:
                alert.resolved = True
                if self.storage_path:
                    self.save()
                return True
        return False
    
    def get_statistics(self) -> Dict:
        """Get alert statistics"""
        total = len(self.alerts)
        unresolved = sum(1 for a in self.alerts if not a.resolved)
        unacknowledged = sum(1 for a in self.alerts if not a.acknowledged)
        
        by_level = {}
        by_type = {}
        
        for alert in self.alerts:
            if not alert.resolved:
                by_level[alert.level] = by_level.get(alert.level, 0) + 1
                by_type[alert.alert_type] = by_type.get(alert.alert_type, 0) + 1
        
        return {
            'total_alerts': total,
            'unresolved_alerts': unresolved,
            'unacknowledged_alerts': unacknowledged,
            'alerts_by_level': by_level,
            'alerts_by_type': by_type
        }
    
    def save(self):
        """Save alerts to storage"""
        if not self.storage_path:
            return
        
        data = {
            'alerts': [a.to_dict() for a in self.alerts],
            'last_updated': datetime.utcnow().isoformat()
        }
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
        
        # Write atomically
        temp_path = self.storage_path + '.tmp'
        with open(temp_path, 'w') as f:
            json.dump(data, f, indent=2)
        
        os.replace(temp_path, self.storage_path)
    
    def load(self):
        """Load alerts from storage"""
        if not self.storage_path or not os.path.exists(self.storage_path):
            return
        
        # Check if file is empty
        if os.path.getsize(self.storage_path) == 0:
            return
        
        with open(self.storage_path, 'r') as f:
            data = json.load(f)
        
        self.alerts = [Alert.from_dict(a) for a in data.get('alerts', [])]
