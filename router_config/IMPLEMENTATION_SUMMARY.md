# Implementation Summary: IoT VLAN Isolation with DoH and Pi-hole Blocklists

## Overview

Completed implementation of a dual-VLAN network architecture with DNS interception, DoH forwarding, and Pi-hole compatible ad/malware filtering for improved network security and IoT isolation.

## Changes Made

### Configuration Files Modified

#### 1. `/etc/rc.conf`
**Purpose**: System startup configuration

**Changes**:
- **Added VLAN interface configuration**:
  - `cloned_interfaces="vlan10 vlan11"` - Create Xbox and Hue VLANs on boot
  - VLAN10 configuration: 192.168.10.1/24 (2001:db8:10::1/64)
  - VLAN11 configuration: 192.168.11.1/24 (2001:db8:11::1/64)
  - Both configured with IPv4 and IPv6 addresses
  - Updated `interface_wait` to include vlan10 and vlan11

- **Replaced BIND9 with dnscrypt-proxy2**:
  - Changed `named_enable="YES"` to `named_enable="NO"`
  - Added `dnscrypt_proxy_enable="YES"`
  - Added `dnscrypt_proxy_config="/usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml"`

#### 2. `/usr/local/etc/dnsmasq.conf`
**Purpose**: DHCP and DNS caching/forwarding

**Changes**:
- **Updated interface listening**:
  - Added `interface=vlan10` (Xbox VLAN)
  - Added `interface=vlan11` (Hue VLAN)
  - Kept em1 (main LAN)
  - Kept except-interface rules for em0, em2

- **Changed DNS upstream**:
  - Changed from `server=127.0.0.1#53` (BIND9) to `server=127.0.0.1#5353` (dnscrypt-proxy2)

- **Added DHCP configuration for all subnets**:
  - **Main LAN**: 192.168.1.100-254 with DNS/gateway 192.168.1.1
  - **Xbox VLAN**: 192.168.10.100-254 with DNS/gateway 192.168.10.1
  - **Hue VLAN**: 192.168.11.100-254 with DNS/gateway 192.168.11.1

- **Added DHCP reservations**:
  - iPhone1: 192.168.1.10 (MAC: FF:FF:FF:FF:FF:01)
  - iPhone2: 192.168.1.11 (MAC: FF:FF:FF:FF:FF:02)
  - Hue Bridge: 192.168.11.50 (MAC: FF:FF:FF:FF:FF:10)
  - Xbox: 192.168.10.50 (MAC: FF:FF:FF:FF:FF:20)

- **Added IPv6 SLAAC**:
  - Constructor-based IPv6 for em1, vlan10, vlan11
  - Enables stateless address autoconfiguration

#### 3. `/etc/pf.conf`
**Purpose**: Firewall rules and NAT

**Changes**:
- **Added new macros** for VLAN management:
  ```
  xbox_vlan = "vlan10"
  hue_vlan = "vlan11"
  xbox_net = "192.168.10.0/24"
  xbox_net6 = "2001:db8:10::/64"
  xbox_ip = "192.168.10.50"
  hue_net = "192.168.11.0/24"
  hue_net6 = "2001:db8:11::/64"
  hue_bridge_ip = "192.168.11.50"
  iphone_net / iphone_net6 = main LAN subnets
  xbox_ports macros for gaming
  ```

- **Added NAT rules** for VLAN traffic:
  - NAT Xbox VLAN IPv4 to WAN
  - NAT Hue VLAN IPv4 to WAN

- **Section 4: Xbox VLAN Rules**:
  - ICMP/ICMPv6 for diagnostics
  - DNS redirection (transparent proxy): `rdr pass ... port 53 -> 127.0.0.1:5353`
  - DHCPv4 pass rules
  - **Outbound restrictions**:
    - HTTPS (443) for updates/games
    - Xbox Live (3074 TCP/UDP) with `keep state`
    - Multiplayer (3078-3079 UDP) with `keep state`
    - NTP (123 UDP) for time sync
  - Block direct DoH/DoT (443, 853) from Xbox VLAN
  - **Isolation**: Block Xbox↔LAN, Xbox↔Hue, Xbox↔mgmt

- **Section 5: Hue VLAN Rules**:
  - ICMP/ICMPv6, DNS redirection, DHCPv4 (same as Xbox)
  - HTTPS outbound for Hue updates
  - Block direct DoH/DoT
  - **Isolation**: Block Hue↔LAN, Hue↔Xbox, Hue↔mgmt

- **Section 6: Cross-VLAN Access (iPhone→Hue)**:
  - SSDP discovery (UDP 1900)
  - mDNS (UDP 5353)
  - HTTP/HTTPS API (TCP 80/443)
  - Entertainment API (UDP 2100)
  - All with `keep state` for bidirectional communication

- **Section 7: Outbound Internet**:
  - Added NAT and forwarding for both new VLANs
  - Maintained IPv4 NAT + IPv6 native routing model

### New Configuration Files Created

#### 4. `dnscrypt-proxy.toml`
**Location**: `/usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml`
**Purpose**: DoH DNS proxy configuration

**Features**:
- Listens on `127.0.0.1:5353` (redirected by pf from port 53)
- Upstream: Cloudflare DoH endpoints (1.1.1.1)
- Loads blocklist from `blocklist.txt` (domain-only format)
- Query logging to `/var/log/dnscrypt-proxy/query.log`
- Blocked domain logging to `/var/log/dnscrypt-proxy/blocked.log`
- Caching with configurable TTL
- IPv6 disabled to prefer IPv4
- DNSSEC validation disabled (compatibility with blocklists)

#### 5. `update_blocklists.sh`
**Location**: `/usr/local/etc/dnscrypt-proxy/update_blocklists.sh`
**Purpose**: Automated blocklist download and conversion

**Features**:
- Downloads Pi-hole compatible blocklists:
  - Steven Black's hosts (comprehensive ad/malware list)
  - Peter Lowe's Ad Server list
  - MVPS hosts
- Converts hosts format (IP + domain) to domain-only format
- Deduplicates and sorts final blocklist
- Logs to `/var/log/dnscrypt-proxy/blocklist-update.log`
- Reloads dnscrypt-proxy2 after update
- Suitable for daily cron job execution

#### 6. `blocklist.txt`
**Location**: `/usr/local/etc/dnscrypt-proxy/blocklist.txt`
**Purpose**: Initial blocklist with common ad/malware domains

**Contents**:
- Seeded with common ad networks (doubleclick.net, googlesyndication.com, etc.)
- Updated by `update_blocklists.sh` script
- Format: One domain per line

#### 7. `VLAN_DNS_CONFIG.md`
**Location**: `/home/julian/homelab/bsd_router_test/router_config/VLAN_DNS_CONFIG.md`
**Purpose**: Comprehensive deployment and troubleshooting guide

**Sections**:
- Summary of changes
- File-by-file modifications
- Network architecture and subnets
- DNS resolution flow diagram
- Deployment instructions (7 phases)
- Verification checklist
- Testing procedures
- Monitoring and maintenance
- Troubleshooting guide
- Security notes

#### 8. `IMPLEMENTATION_CHECKLIST.md`
**Location**: `/home/julian/homelab/bsd_router_test/IMPLEMENTATION_CHECKLIST.md`
**Purpose**: Quick reference checklist for deployment

**Sections**:
- Configuration files status
- Network architecture summary
- DNS resolution flow
- Security features implemented
- Deployment steps (6 phases)
- Verification checklist
- Testing procedures
- Monitoring commands
- Known issues and resolutions
- Rollback plan
- Success criteria
- File summary

## Architecture Summary

### Network Layout
```
┌─────────────────────────────────────────────────────────────────┐
│                          WAN (em0)                              │
│                      DHCP to ISP/NAT                           │
└────────────────────┬────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
    ┌───┴───────────────────┐  ┌──┴──────────┐
    │  Main LAN (em1)       │  │ Mgmt (em2)  │
    │ 192.168.1.0/24        │  │ 192.168.100 │
    │ 2001:db8:1::/64       │  └─────────────┘
    │                       │        │
    │ ├─ iPhone1 (1.10)    │   Raspberry Pi
    │ ├─ iPhone2 (1.11)    │   (PXE Boot)
    │ └─ DHCP: 1.100-254   │
    │                       │
    │  VLAN10 (Xbox)       │
    │  192.168.10.0/24     │
    │  2001:db8:10::/64    │
    │  ├─ Xbox (10.50)     │
    │  └─ DHCP: 10.100-254 │
    │                       │
    │  VLAN11 (Hue)        │
    │  192.168.11.0/24     │
    │  2001:db8:11::/64    │
    │  ├─ Hue Bridge (11.50)
    │  └─ DHCP: 11.100-254 │
    └───────────────────────┘
```

### DNS Resolution Path
```
Client → dnsmasq (cached) → dnscrypt-proxy2 → Cloudflare DoH (1.1.1.1)
                                ↓
                          Check blocklist
                          Log query
                          Return response
```

## Security Improvements

1. **DoH Encryption**: All DNS queries encrypted to Cloudflare, preventing ISP/network snooping
2. **Ad/Malware Filtering**: Pi-hole blocklists (100k+ domains) block tracking/malware
3. **IoT Isolation**: Xbox and Hue VLANs isolated from trusted LAN
4. **Gaming Restrictions**: Xbox limited to essential ports only (3074, 3078-3079, 443, 123)
5. **DNS Interception**: Transparent proxy prevents DNS bypass attempts
6. **Observability**: Complete query/block logging for anomaly detection
7. **Cross-VLAN Control**: Selective access allows iPhone→Hue without exposing Xbox
8. **Stateful Firewall**: Connection tracking prevents spoofed packets

## Removed Dependencies

- **BIND9 (named)**: Fully replaced by dnscrypt-proxy2
  - BIND9 was doing DNS caching and forwarding
  - dnscrypt-proxy2 adds DoH encryption and blocklist support
  - Simpler configuration for this use case

## Installation Requirements

To deploy this configuration, you need:
- FreeBSD 12.x or later
- `pkg install dnscrypt-proxy2`
- Internet connectivity for DoH upstream
- About 50MB disk space for logs (with rotation)

## Next Steps

1. **Deploy**: Follow VLAN_DNS_CONFIG.md deployment section
2. **Test**: Use IMPLEMENTATION_CHECKLIST.md verification section
3. **Monitor**: Check logs daily for first week: `tail -f /var/log/dnscrypt-proxy/*.log`
4. **Adjust**: Fine-tune blocklist based on legitimate domain blocks
5. **Maintain**: Run `update_blocklists.sh` daily via cron

## File Inventory

**Modified Files** (3):
- `/etc/rc.conf`
- `/usr/local/etc/dnsmasq.conf`
- `/etc/pf.conf`

**New Files** (5):
- `/usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml`
- `/usr/local/etc/dnscrypt-proxy/update_blocklists.sh`
- `/usr/local/etc/dnscrypt-proxy/blocklist.txt`
- `/home/julian/homelab/bsd_router_test/router_config/VLAN_DNS_CONFIG.md`
- `/home/julian/homelab/bsd_router_test/IMPLEMENTATION_CHECKLIST.md`

**Deprecated Files** (1):
- `/usr/local/etc/namedb/named.conf` (can be deleted)

## Verification Commands

```bash
# Check VLAN creation
ifconfig vlan10 && ifconfig vlan11

# Check DNS upstream
pgrep dnscrypt-proxy && echo "OK"

# Test DNS from Xbox VLAN
nslookup google.com 192.168.10.1

# View live query log
tail -f /var/log/dnscrypt-proxy/query.log

# View live blocked domains
tail -f /var/log/dnscrypt-proxy/blocked.log

# Check blocklist size
wc -l /usr/local/etc/dnscrypt-proxy/blocklist.txt
```

## Support

Refer to:
- **Deployment**: `router_config/VLAN_DNS_CONFIG.md`
- **Quick Check**: `IMPLEMENTATION_CHECKLIST.md`
- **Troubleshooting**: `VLAN_DNS_CONFIG.md` - Troubleshooting section

---

**Status**: Ready for deployment ✓
**Last Updated**: February 7, 2026
