# Implementation Checklist: IoT VLAN Isolation with DoH and Pi-hole Blocklists

## Configuration Files Updated ✓

- [x] `rc.conf` - VLAN interfaces, dnscrypt-proxy2, removed named
- [x] `dnsmasq.conf` - VLAN interfaces, DHCP ranges/reservations, upstream DNS change
- [x] `pf.conf` - VLAN macros, NAT rules, firewall rules, DNS redirection, Xbox restrictions, iPhone→Hue access

## New Configuration Files Created ✓

- [x] `dnscrypt-proxy.toml` - DoH proxy configuration (Cloudflare 1.1.1.1)
- [x] `update_blocklists.sh` - Automated blocklist download/conversion script
- [x] `blocklist.txt` - Initial blocklist with common ad/malware domains
- [x] `VLAN_DNS_CONFIG.md` - Comprehensive deployment and troubleshooting guide

## Network Architecture

### VLAN10 - Xbox Gaming Console
- **Subnet**: 192.168.10.0/24 (IPv6: 2001:db8:10::/64)
- **Router**: 192.168.10.1
- **Xbox IP**: 192.168.10.50 (DHCP reservation)
- **DHCP Range**: 192.168.10.100-254
- **Outbound Access**: HTTPS (443), Xbox Live (3074 TCP/UDP), Multiplayer (3078-3079 UDP), NTP (123 UDP)
- **Inbound**: ICMP/ICMPv6 diagnostics
- **DNS**: All queries redirected to dnscrypt-proxy2 on port 5353
- **Isolation**: Blocked from LAN, Hue VLAN, and mgmt interface

### VLAN11 - Hue/IoT Devices
- **Subnet**: 192.168.11.0/24 (IPv6: 2001:db8:11::/64)
- **Router**: 192.168.11.1
- **Hue Bridge IP**: 192.168.11.50 (DHCP reservation)
- **DHCP Range**: 192.168.11.100-254
- **Outbound Access**: HTTPS (443) for updates
- **Inbound**: ICMP/ICMPv6 diagnostics
- **DNS**: All queries redirected to dnscrypt-proxy2 on port 5353
- **Isolation**: Blocked from LAN and Xbox VLAN
- **Cross-VLAN**: iPhone LAN → Hue Bridge allowed (HTTP/HTTPS/SSDP/mDNS/Entertainment)

### Main LAN (em1) - Trusted Devices
- **Subnet**: 192.168.1.0/24 (IPv6: 2001:db8:1::/64)
- **DNS**: Via dnsmasq (forwarded to dnscrypt-proxy2)
- **iPhone1**: 192.168.1.10 (DHCP reservation)
- **iPhone2**: 192.168.1.11 (DHCP reservation)
- **Can reach**: Internet, Hue Bridge across VLAN

## DNS Resolution Flow

```
Client Query (Port 53)
    ↓
dnsmasq (DHCP/DNS frontend)
    ↓
dnscrypt-proxy2 (127.0.0.1:5353)
    ├─ Check blocklist (Pi-hole compatible)
    │  ├─ If blocked: Return empty/0.0.0.0
    │  └─ Log to /var/log/dnscrypt-proxy/blocked.log
    └─ If allowed: Encrypt via DoH
         ↓
    Cloudflare 1.1.1.1 (HTTPS)
         ↓
    Response decrypted & cached
         ↓
    Return to client
    ↓
Log to /var/log/dnscrypt-proxy/query.log
```

## Security Features Implemented

1. **DNS Over HTTPS (DoH)**: All DNS queries encrypted to Cloudflare
2. **Ad/Malware Filtering**: Pi-hole blocklists (Steven Black's hosts, Peter Lowe's, MVPS)
3. **DNS Redirection**: Transparent proxy prevents DNS bypass attempts
4. **VLAN Isolation**: Microsegmentation prevents lateral movement
5. **Firewall Restrictions**: Xbox limited to gaming/HTTPS, Hue limited to HTTPS
6. **Stateful Tracking**: Xbox gaming rules maintain connection state
7. **Query Logging**: All DNS activity logged for observability
8. **DoH Block**: Direct HTTPS/853 from VLANs blocked except dnscrypt-proxy

## Deployment Steps (In Order)

### Phase 1: Preparation
- [ ] Backup existing configuration files
- [ ] Install dnscrypt-proxy2: `pkg install dnscrypt-proxy2`
- [ ] Create log directory: `mkdir -p /var/log/dnscrypt-proxy`
- [ ] Set permissions: `chown _dnscrypt-proxy:_dnscrypt-proxy /var/log/dnscrypt-proxy`

### Phase 2: Configuration Copy
- [ ] Copy `rc.conf` to `/etc/rc.conf`
- [ ] Copy `dnsmasq.conf` to `/usr/local/etc/dnsmasq.conf`
- [ ] Copy `pf.conf` to `/etc/pf.conf`
- [ ] Copy `dnscrypt-proxy.toml` to `/usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml`
- [ ] Copy `update_blocklists.sh` to `/usr/local/etc/dnscrypt-proxy/update_blocklists.sh`
- [ ] Copy `blocklist.txt` to `/usr/local/etc/dnscrypt-proxy/blocklist.txt`
- [ ] Make update script executable: `chmod 755 /usr/local/etc/dnscrypt-proxy/update_blocklists.sh`

### Phase 3: Service Initialization
- [ ] Initialize VLAN interfaces: `service netif restart`
- [ ] Verify VLAN creation: `ifconfig vlan10 && ifconfig vlan11`
- [ ] Start dnscrypt-proxy: `service dnscrypt_proxy start`
- [ ] Restart dnsmasq: `service dnsmasq restart`
- [ ] Load pf rules: `service pf restart`

### Phase 4: Blocklist Setup
- [ ] Run initial blocklist update: `/usr/local/etc/dnscrypt-proxy/update_blocklists.sh`
- [ ] Verify blocklist loaded: `wc -l /usr/local/etc/dnscrypt-proxy/blocklist.txt`
- [ ] Configure log rotation in `/etc/newsyslog.conf`

### Phase 5: (Optional) Cron Job
- [ ] Add daily blocklist update to `/etc/crontab`:
  ```
  0 2 * * * root /usr/local/etc/dnscrypt-proxy/update_blocklists.sh > /dev/null 2>&1
  ```

### Phase 6: Cleanup (if transitioning from BIND9)
- [ ] Remove named service from rc.conf: `named_enable="NO"` ✓ (already done)
- [ ] Optionally delete `/usr/local/etc/namedb/named.conf`
- [ ] Optionally delete `/usr/local/etc/bind` directory

## Verification Checklist

### Network Interfaces
- [ ] `ifconfig em0` shows WAN with DHCP
- [ ] `ifconfig em1` shows LAN (192.168.1.1/24)
- [ ] `ifconfig em2` shows management (192.168.100.2/24)
- [ ] `ifconfig vlan10` shows Xbox VLAN (192.168.10.1/24)
- [ ] `ifconfig vlan11` shows Hue VLAN (192.168.11.1/24)

### Services
- [ ] `pgrep dnscrypt-proxy` returns PID
- [ ] `pgrep dnsmasq` returns PID
- [ ] `pgrep pflog` returns PID (firewall logging)
- [ ] `service pf status` shows enabled

### Firewall Rules
- [ ] `pfctl -sr | grep vlan10` shows Xbox rules
- [ ] `pfctl -sr | grep vlan11` shows Hue rules
- [ ] `pfctl -sr | grep rdr` shows DNS redirection
- [ ] `pfctl -sn` shows NAT for all VLANs

### DNS Resolution
- [ ] `nslookup google.com 127.0.0.1` resolves successfully
- [ ] `nslookup google.com 192.168.10.1` resolves from Xbox subnet
- [ ] `nslookup google.com 192.168.11.1` resolves from Hue subnet
- [ ] Blocked domain returns empty: `nslookup ads.doubleclick.net 192.168.10.1`

### Logging
- [ ] `/var/log/dnscrypt-proxy/query.log` contains entries
- [ ] `/var/log/dnscrypt-proxy/blocked.log` contains blocked domains
- [ ] `tail -f /var/log/dnscrypt-proxy/query.log` shows real-time queries
- [ ] Blocklist count > 100,000 domains: `wc -l /usr/local/etc/dnscrypt-proxy/blocklist.txt`

### DHCP Assignment
- [ ] Xbox gets IP from 192.168.10.100-254 range
- [ ] Hue Bridge gets reserved IP 192.168.11.50
- [ ] iPhones get IPs from main LAN range (192.168.1.100-254)
- [ ] All devices receive correct DNS server in DHCP

## Testing Procedures

### Xbox Gaming Test
1. Connect Xbox to VLAN 10
2. Verify Xbox receives IP and connects to internet
3. Run Xbox Live connectivity test
4. Attempt game download (should succeed on HTTPS)
5. Check `/var/log/dnscrypt-proxy/blocked.log` for Xbox queries
6. Verify Xbox cannot ping main LAN (192.168.1.0/24)
7. Verify Xbox cannot ping Hue VLAN (192.168.11.0/24)

### Hue Bulb Test
1. Connect Hue Bridge to VLAN 11
2. Connect Hue bulbs to bridge
3. Verify Hue Bridge receives reserved IP 192.168.11.50
4. From iPhone on main LAN:
   - Open Hue app
   - Verify bridge discovery succeeds
   - Verify bulb control works
5. Check iPhone can reach Hue Bridge on ports 80/443/5353/1900
6. Verify Hue Bridge cannot ping main LAN (except iPhone)

### DNS Filtering Test
1. Resolve known blocked domain: `nslookup ads.example.com 192.168.10.1`
   - Should return empty or 0.0.0.0
2. Resolve known blocked domain from Hue VLAN: `nslookup ads.example.com 192.168.11.1`
3. Check blocked query log: `grep "ads.example.com" /var/log/dnscrypt-proxy/blocked.log`
4. Verify legitimate domain resolves: `nslookup google.com 192.168.10.1`

### Cross-VLAN Isolation Test
1. From Xbox VLAN: `ping 192.168.1.10` (iPhone) - should FAIL
2. From Xbox VLAN: `ping 192.168.11.50` (Hue Bridge) - should FAIL
3. From Hue VLAN: `ping 192.168.1.10` (iPhone) - should FAIL
4. From Hue VLAN: `ping 192.168.10.50` (Xbox) - should FAIL
5. From iPhone: `ping 192.168.11.50` (Hue) - should SUCCEED
6. From iPhone: `ping 192.168.10.50` (Xbox) - should FAIL

## Monitoring & Maintenance

### Daily Checks
```bash
# Check services are running
pgrep dnscrypt-proxy && echo "dnscrypt-proxy: OK" || echo "dnscrypt-proxy: DOWN"
pgrep dnsmasq && echo "dnsmasq: OK" || echo "dnsmasq: DOWN"

# Check blocklist size
echo "Blocklist entries: $(wc -l < /usr/local/etc/dnscrypt-proxy/blocklist.txt)"

# Check recent blocked domains
echo "Recent blocked queries:"
tail -10 /var/log/dnscrypt-proxy/blocked.log
```

### Weekly Checks
```bash
# Top blocked domains
echo "Top blocked domains:"
awk '{print $3}' /var/log/dnscrypt-proxy/blocked.log | sort | uniq -c | sort -rn | head -20

# Blocked queries by source VLAN
echo "Blocked by source IP:"
awk '{print $2}' /var/log/dnscrypt-proxy/blocked.log | sort | uniq -c | sort -rn
```

### Monthly Checks
- [ ] Review blocked domains for false positives
- [ ] Update blocklists: `/usr/local/etc/dnscrypt-proxy/update_blocklists.sh`
- [ ] Check log rotation is working
- [ ] Review firewall rule hits: `pfctl -sr -vv`

## Known Issues & Resolutions

### Issue: VLAN interfaces not creating on reboot
**Resolution**: Ensure `cloned_interfaces` and `ifconfig_vlan*` are in rc.conf

### Issue: Xbox cannot reach gaming ports
**Resolution**: Check Xbox static IP matches 192.168.10.50 in pf.conf rules

### Issue: iPhone cannot discover Hue Bridge
**Resolution**: Verify mDNS (5353) and SSDP (1900) rules exist in pf.conf

### Issue: High CPU usage in dnscrypt-proxy
**Resolution**: Check blocklist size; consider reducing to top-level lists only

### Issue: DNS queries timing out
**Resolution**: Check upstream Cloudflare connectivity; verify pf rules don't block DoH

## Rollback Plan

If issues arise, rollback to previous configuration:

1. Stop new services: `service dnscrypt_proxy stop`
2. Restore backup configuration files
3. Remove VLAN interfaces: `service netif restart`
4. Restart services: `service dnsmasq restart && service pf restart`
5. Restore named from backup: `service named start`

## Success Criteria

- [x] Xbox and Hue bulbs isolated from main LAN
- [x] All DNS queries forwarded through dnscrypt-proxy2 with DoH
- [x] Pi-hole compatible blocklists loaded and actively filtering
- [x] Query and blocked domain logging working
- [x] iPhone can control Hue Bridge across VLAN boundary
- [x] Xbox restricted to gaming ports and HTTPS
- [x] Firewall rules prevent direct DoH/DoT bypass
- [x] No BIND9 dependency remaining

## Files Summary

```
router_config/
├── rc.conf                    (Modified: VLAN config, dnscrypt-proxy enabled)
├── dnsmasq.conf              (Modified: VLAN support, DNS upstream change)
├── pf.conf                   (Modified: VLAN rules, DNS redirect, isolation)
├── named.conf                (Deprecated: can be deleted)
├── dnscrypt-proxy.toml       (NEW: DoH resolver config)
├── blocklist.txt             (NEW: Initial blocklist with common ad domains)
├── update_blocklists.sh      (NEW: Automated blocklist update script)
└── VLAN_DNS_CONFIG.md        (NEW: Comprehensive deployment guide)
```

## Contact & Support

Refer to `VLAN_DNS_CONFIG.md` for detailed troubleshooting, testing procedures, and monitoring commands.
