#!/usr/bin/env python3
"""
Resource Monitoring Module
Monitors router and system resources, generates alerts when thresholds exceeded
"""

import subprocess
import re
from typing import Dict, Optional
from datetime import datetime


class ResourceMonitor:
    """
    Monitor system resources (CPU, memory, network)
    """
    
    def __init__(self, cpu_threshold: float = 80.0, 
                 memory_threshold: float = 85.0,
                 network_threshold_mbps: float = 90.0):
        """
        Initialize resource monitor
        
        Args:
            cpu_threshold: CPU usage threshold percentage
            memory_threshold: Memory usage threshold percentage  
            network_threshold_mbps: Network usage threshold in Mbps
        """
        self.cpu_threshold = cpu_threshold
        self.memory_threshold = memory_threshold
        self.network_threshold_mbps = network_threshold_mbps
    
    def get_cpu_usage(self) -> Optional[float]:
        """
        Get current CPU usage percentage
        
        Returns:
            CPU usage as percentage (0-100) or None if unable to determine
        """
        try:
            # Try FreeBSD's top command
            result = subprocess.run(['top', '-d', '1'], capture_output=True, 
                                  text=True, timeout=5)
            
            if result.returncode == 0:
                # Parse top output for CPU idle percentage
                # Look for line like: "CPU:  1.2% user,  0.0% nice,  2.3% system,  0.8% interrupt, 95.7% idle"
                for line in result.stdout.splitlines():
                    if 'CPU:' in line or 'idle' in line.lower():
                        idle_match = re.search(r'(\d+\.?\d*)%\s+idle', line)
                        if idle_match:
                            idle_pct = float(idle_match.group(1))
                            return 100.0 - idle_pct
        
        except Exception as e:
            print(f"Error getting CPU usage: {e}")
        
        return None
    
    def get_memory_usage(self) -> Optional[float]:
        """
        Get current memory usage percentage
        
        Returns:
            Memory usage as percentage (0-100) or None if unable to determine
        """
        try:
            # Try sysctl for FreeBSD
            result = subprocess.run(['sysctl', 'hw.physmem', 'vm.stats.vm.v_free_count', 
                                   'vm.stats.vm.v_page_size'],
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                physmem = None
                free_count = None
                page_size = None
                
                for line in result.stdout.splitlines():
                    if 'hw.physmem' in line:
                        physmem = int(line.split(':')[1].strip())
                    elif 'v_free_count' in line:
                        free_count = int(line.split(':')[1].strip())
                    elif 'v_page_size' in line:
                        page_size = int(line.split(':')[1].strip())
                
                if physmem and free_count is not None and page_size:
                    free_mem = free_count * page_size
                    used_mem = physmem - free_mem
                    usage_pct = (used_mem / physmem) * 100.0
                    return usage_pct
        
        except Exception as e:
            print(f"Error getting memory usage: {e}")
        
        return None
    
    def get_network_stats(self, interface: str = 'em0') -> Optional[Dict]:
        """
        Get network interface statistics
        
        Args:
            interface: Network interface name (default: em0 for WAN)
        
        Returns:
            Dictionary with network stats or None if unable to determine
        """
        try:
            # Use netstat for interface statistics
            result = subprocess.run(['netstat', '-I', interface, '-b'],
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                lines = result.stdout.splitlines()
                if len(lines) >= 2:
                    # Parse the data line (skip header)
                    parts = lines[1].split()
                    if len(parts) >= 10:
                        return {
                            'interface': interface,
                            'rx_bytes': int(parts[6]),
                            'tx_bytes': int(parts[9]),
                            'timestamp': datetime.utcnow().isoformat()
                        }
        
        except Exception as e:
            print(f"Error getting network stats: {e}")
        
        return None
    
    def check_resources(self, hostname: str = 'router') -> Dict:
        """
        Check all resources and return status
        
        Args:
            hostname: Hostname for reporting
        
        Returns:
            Dictionary with resource checks and alert flags
        """
        results = {
            'hostname': hostname,
            'timestamp': datetime.utcnow().isoformat(),
            'checks': {},
            'alerts': []
        }
        
        # Check CPU
        cpu_usage = self.get_cpu_usage()
        if cpu_usage is not None:
            results['checks']['cpu'] = {
                'value': cpu_usage,
                'threshold': self.cpu_threshold,
                'exceeded': cpu_usage > self.cpu_threshold
            }
            if cpu_usage > self.cpu_threshold:
                results['alerts'].append({
                    'resource': 'cpu',
                    'value': cpu_usage,
                    'threshold': self.cpu_threshold
                })
        
        # Check memory
        memory_usage = self.get_memory_usage()
        if memory_usage is not None:
            results['checks']['memory'] = {
                'value': memory_usage,
                'threshold': self.memory_threshold,
                'exceeded': memory_usage > self.memory_threshold
            }
            if memory_usage > self.memory_threshold:
                results['alerts'].append({
                    'resource': 'memory',
                    'value': memory_usage,
                    'threshold': self.memory_threshold
                })
        
        # Check network (would need baseline comparison for actual alerting)
        network_stats = self.get_network_stats()
        if network_stats:
            results['checks']['network'] = network_stats
        
        return results
