# Network Topology

## Overview
```
                   Internet
                      |
                  [VMNet NAT]
                      |
                   em0 (WAN)
                      |
        ┌─────────────┴─────────────┐
        │   FreeBSD Router          │
        │   (routertest)            │
        │                           │
        │   em0: DHCP from VMNet    │
        │   em1: 192.168.1.1/24     │
        │   em2: 192.168.100.2/24   │
        └─────────┬─────────┬───────┘
                  │         │
            em1 (LAN)   em2 (mgmt)
                  │         │
         [192.168.1.0/24]   │
         [2001:db8:1::/64]  │
                  │         │
            [Kali Linux]    │
            192.168.1.x     │
                            │
                [Debian PXE Boot Server]
                [Raspberry Pi in prod]
                192.168.100.1
```

## Network Segments

### 1. WAN (em0)
- **Purpose**: Internet connectivity via VMWare NAT
- **Configuration**: DHCP client (IPv4 and IPv6)
- **Services**: Outbound internet access for router and LAN clients

### 2. LAN (em1)
- **Purpose**: Dual-stack client network
- **IPv4**: 192.168.1.0/24
  - Router: 192.168.1.1
  - DHCP range: Managed by dnsmasq
- **IPv6**: 2001:db8:1::/64
  - Router: 2001:db8:1::1
  - SLAAC for clients
- **Services**:
  - DHCPv4
  - DNS (forwarding)
  - IPv6 Router Advertisements
  - NAT for IPv4, native routing for IPv6

### 3. Management (em2)
- **Purpose**: PXE boot network for router
- **Network**: 192.168.100.0/24
  - Debian VM: 192.168.100.1 (boot server)
  - Router: 192.168.100.2 (boot client)
- **Services**:
  - DHCP (for PXE)
  - TFTP (for boot files)
  - BIOS PXE only
- **Security**: pf firewall restricts em2 to only communicate with 192.168.100.1

## Traffic Flow

### Internet Access (LAN → WAN)
1. **IPv4**: Client → Router (NAT) → Internet
2. **IPv6**: Client → Router (native routing) → Internet

### PXE Boot (em2)
1. Router broadcasts DHCP discover on em2
2. Debian VM responds with IP (192.168.100.2) and boot file
3. Router downloads boot files via TFTP from 192.168.100.1
4. Router boots FreeBSD from network

### Isolation
- Management network (em2) is isolated - no routing to LAN or WAN
- Only boot-related traffic allowed on em2
- All production services run on WAN/LAN interfaces

## IP Assignments

| Device | Interface | IPv4 | IPv6 |
|--------|-----------|------|------|
| Router | em0 (WAN) | DHCP | DHCP |
| Router | em1 (LAN) | 192.168.1.1/24 | 2001:db8:1::1/64 |
| Router | em2 (mgmt) | 192.168.100.2/24 | - |
| Debian VM | eth0 | 192.168.100.1/24 | - |
| Kali Linux | eth0 | 192.168.1.x/24 (DHCP) | 2001:db8:1::x/64 (SLAAC) |
