# DNS and DHCP Configuration Update

## Summary of Changes

This update separates IoT and gaming devices into isolated VLANs with enforced DNS over HTTPS (DoH) forwarding through Cloudflare's 1.1.1.1, with ad and malware domain filtering using Pi-hole compatible blocklists.

### Major Changes:

1. **Removed BIND9 (named)** - Replaced with `dnscrypt-proxy2` for DoH DNS forwarding
2. **Created two new VLANs:**
   - `vlan10` (192.168.10.0/24): Xbox gaming console
   - `vlan11` (192.168.11.0/24): Philips Hue bulbs and other IoT devices
3. **DNS Interception:** All DNS queries from VLANs are transparently redirected to `dnscrypt-proxy2` listening on `127.0.0.1:5353`
4. **Ad/Malware Filtering:** Using Pi-hole compatible blocklists (Steven Black's hosts, Peter Lowe's list, MVPS)
5. **Firewall Isolation:** VLANs are isolated from each other and from the main LAN, with selective cross-VLAN access for iPhone → Hue Bridge control
6. **Xbox Restrictions:** Xbox can only access HTTPS (443) and gaming ports (3074, 3078-3079), NTP (123) for time sync
7. **Query Logging:** All DNS queries and blocked domains are logged for monitoring

## File Changes

### rc.conf
- Added VLAN interface configuration (`vlan10` and `vlan11` on `em1`)
- Replaced `named_enable="YES"` with `dnscrypt_proxy_enable="YES"`
- Updated `interface_wait` to include new VLAN interfaces

### dnsmasq.conf
- Added `vlan10` and `vlan11` to listening interfaces
- Added DHCP ranges for both VLANs
- Added DHCP reservations for iPhones, Hue Bridge, and Xbox
- Changed upstream DNS from `server=127.0.0.1#53` (named) to `server=127.0.0.1#5353` (dnscrypt-proxy2)
- Added DHCPv4 options for each VLAN to set DNS servers and gateways

### pf.conf
- Added macros for VLAN interfaces, networks, and IP addresses
- Added NAT rules for Xbox and Hue VLANs
- Added DNS redirection rules (transparent proxy on port 5353)
- Added firewall rules for each VLAN:
  - **Xbox VLAN**: Restricted outbound access (HTTPS, gaming ports, NTP)
  - **Hue VLAN**: Restricted outbound with HTTPS for updates
  - **Cross-VLAN**: iPhone → Hue Bridge allowed (discovery, API, entertainment)
- Isolated VLANs from each other and main LAN by default
- Used `keep state` on Xbox gaming ports for stateful connection tracking

### New Files Created

#### dnscrypt-proxy.toml
Configuration for `dnscrypt-proxy2`:
- Listens on `127.0.0.1:5353`
- Forwards to Cloudflare DoH endpoints (1.1.1.1)
- Loads blocklist from `/usr/local/etc/dnscrypt-proxy/blocklist.txt`
- Logs all queries to `/var/log/dnscrypt-proxy/query.log`
- Logs blocked domains to `/var/log/dnscrypt-proxy/blocked.log`

#### update_blocklists.sh
Automated script to download and convert Pi-hole blocklists:
- Downloads Steven Black's hosts file
- Downloads Peter Lowe's Ad Server list
- Downloads MVPS hosts
- Converts hosts format (IP + domain) to domain-only format
- Deduplicates and sorts final blocklist
- Reloads `dnscrypt-proxy2` after update

#### blocklist.txt
Initial blocklist file with common ad networks and trackers. This file is overwritten by `update_blocklists.sh`.

## Deployment Instructions

### 1. Copy Configuration Files
```bash
cp rc.conf /etc/rc.conf
cp dnsmasq.conf /usr/local/etc/dnsmasq.conf
cp pf.conf /etc/pf.conf
cp dnscrypt-proxy.toml /usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml
cp update_blocklists.sh /usr/local/etc/dnscrypt-proxy/update_blocklists.sh
cp blocklist.txt /usr/local/etc/dnscrypt-proxy/blocklist.txt
chmod 755 /usr/local/etc/dnscrypt-proxy/update_blocklists.sh
```

### 2. Install dnscrypt-proxy2
```bash
pkg install dnscrypt-proxy2
```

### 3. Create Log Directory
```bash
mkdir -p /var/log/dnscrypt-proxy
chown _dnscrypt-proxy:_dnscrypt-proxy /var/log/dnscrypt-proxy
```

### 4. Update Blocklists
```bash
/usr/local/etc/dnscrypt-proxy/update_blocklists.sh
```

### 5. Create Log Rotation Configuration
Add to `/etc/newsyslog.conf`:
```
/var/log/dnscrypt-proxy/query.log       644  7  *  @T00  JC
/var/log/dnscrypt-proxy/blocked.log     644  7  *  @T00  JC
/var/log/dnscrypt-proxy/dnscrypt-proxy.log 644  7  *  @T00  JC
/var/log/dnscrypt-proxy/blocklist-update.log 644  7  *  @T00  JC
```

### 6. (Optional) Set Up Cron Job for Blocklist Updates
Add to `/etc/crontab`:
```
# Update DNS blocklists daily at 2 AM
0 2 * * * root /usr/local/etc/dnscrypt-proxy/update_blocklists.sh > /dev/null 2>&1
```

### 7. Create VLAN Interfaces and Restart Services
```bash
service netif restart
service dnsmasq restart
service dnscrypt_proxy start
service pf restart
```

### 8. Verify Services
```bash
# Check VLAN interfaces
ifconfig vlan10
ifconfig vlan11

# Check dnscrypt-proxy is running
pgrep dnscrypt-proxy

# Check pf rules loaded
pfctl -sr | head -20

# Check dnsmasq is listening on all interfaces
sockstat -4 -p 53

# Test DNS resolution
nslookup google.com 127.0.0.1
```

## Testing

### Xbox VLAN Testing
1. Connect Xbox to VLAN 10 network (or assign static IP 192.168.10.50 via DHCP)
2. Verify Xbox receives IP from DHCP range 192.168.10.100-254
3. Verify Xbox can reach internet for game downloads (HTTPS)
4. Verify Xbox Live connectivity (gaming ports)
5. Verify Xbox cannot reach main LAN or Hue VLAN
6. Monitor blocked domains: `tail -f /var/log/dnscrypt-proxy/blocked.log`

### Hue VLAN Testing
1. Connect Hue Bridge to VLAN 11 (or assign DHCP reservation 192.168.11.50)
2. Connect Hue bulbs to Hue Bridge
3. Connect iPhone to main LAN (192.168.1.x)
4. Verify iPhone can discover Hue Bridge
5. Verify iPhone can control Hue bulbs via HTTPS API
6. Verify Hue bulbs cannot reach main LAN or Xbox VLAN

### DNS Filtering Testing
1. Attempt to resolve blocked domain: `nslookup ads.example.com 192.168.10.1`
   - Should be blocked/return empty
2. Check query logs: `tail -f /var/log/dnscrypt-proxy/query.log`
3. Check blocked logs: `tail -f /var/log/dnscrypt-proxy/blocked.log`

## Monitoring

### Query Statistics
```bash
# Top queried domains
awk '{print $3}' /var/log/dnscrypt-proxy/query.log | sort | uniq -c | sort -rn | head -20

# Top blocked domains
awk '{print $3}' /var/log/dnscrypt-proxy/blocked.log | sort | uniq -c | sort -rn | head -20

# Blocked queries by source IP
awk '{print $2}' /var/log/dnscrypt-proxy/blocked.log | sort | uniq -c | sort -rn

# Real-time monitoring
tail -f /var/log/dnscrypt-proxy/query.log
tail -f /var/log/dnscrypt-proxy/blocked.log
```

## Troubleshooting

### VLAN interfaces not created
- Ensure `cloned_interfaces` is set correctly in rc.conf
- Verify `vlandev em1` is the correct parent interface
- Check: `ifconfig vlan10 create`

### DNS not resolving
- Check dnsmasq is listening: `sockstat -4 -p 53`
- Check dnscrypt-proxy is running: `ps aux | grep dnscrypt`
- Check pf rules are loaded: `pfctl -sr | grep "dns\|5353"`
- Test directly: `dig @127.0.0.1 google.com`

### Xbox cannot reach internet
- Verify Xbox has IP in range 192.168.10.100-254
- Check pf rules allow Xbox outbound: `pfctl -sr | grep "192.168.10"`
- Check NAT is working: `pfctl -sn`
- Verify gaming ports: Check pf rules include 3074, 3078-3079

### iPhone cannot reach Hue
- Verify Hue Bridge has static IP 192.168.11.50
- Check cross-VLAN rules in pf: `pfctl -sr | grep "hue\|192.168.11"`
- Verify mDNS (5353) and HTTP (80/443) rules are present
- Test connectivity: `ping -c 1 192.168.11.50` from iPhone network

### Performance issues
- Check blocklist size: `wc -l /usr/local/etc/dnscrypt-proxy/blocklist.txt`
- Monitor CPU/memory: `top -b | head -20`
- Check for DoH upstream latency: `dnscrypt-proxy -show-certs`

## Security Notes

1. **DoH Enforcement**: All DNS queries from Xbox and Hue VLANs are redirected to dnscrypt-proxy2, preventing bypass attempts
2. **Blocklist Updates**: Run `update_blocklists.sh` regularly to stay current with new ad/malware domains
3. **Logging**: All DNS activity is logged for investigation of anomalous behavior
4. **VLAN Isolation**: Network microsegmentation prevents compromised IoT devices from accessing sensitive LAN resources
5. **Stateful Tracking**: Xbox gaming rules use `keep state` to prevent spoofed packets
6. **Direct DoH Block**: Outbound HTTPS/853 from VLANs is blocked except for dnscrypt-proxy process

## Next Steps

1. Test all configurations in staging environment
2. Monitor logs for false positives in blocklist
3. Adjust pf rules if specific gaming/IoT features fail
4. Consider adding additional blocklists based on monitoring data
5. Implement log aggregation to Raspberry Pi for persistent analysis
