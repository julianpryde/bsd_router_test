# Testing the PXE Boot Setup

## Prerequisites
1. FreeBSD router VM with 3 network interfaces (em0, em1, em2)
2. Debian VM (or Raspberry Pi) with 1 network interface
3. em2 on router connected to eth0 on Debian VM (same network segment)

## Setup Steps

### On the Debian VM

1. **Deploy configuration files**:
   ```bash
   cd debian-pxe-boot
   sudo ./setup.sh
   ```

2. **Verify network configuration**:
   ```bash
   ip addr show eth0
   # Should show: 192.168.100.1/24
   ```

3. **Check dnsmasq is running**:
   ```bash
   sudo systemctl status dnsmasq
   sudo journalctl -u dnsmasq -f  # Monitor logs
   ```

4. **Verify TFTP directory**:
   ```bash
   ls -la /srv/tftp/
   # Should contain: pxelinux.0, *.c32 files, pxelinux.cfg/
   ```

### On the FreeBSD Router

1. **Apply configuration files**:
   ```bash
   # Copy files from this repository to router
   scp rc.conf root@router:/etc/rc.conf
   scp pf.conf root@router:/etc/pf.conf
   ```

2. **Restart networking** (or reboot):
   ```bash
   service netif restart
   service routing restart
   ```

3. **Verify em2 interface**:
   ```bash
   ifconfig em2
   # Should show: inet 192.168.100.2 netmask 0xffffff00
   ```

4. **Test connectivity to boot server**:
   ```bash
   ping -c 3 192.168.100.1
   ```

## Testing PXE Boot

### Method 1: Test DHCP (without rebooting)

On the router:
```bash
# Request DHCP lease on em2
dhclient em2

# Check assigned IP
ifconfig em2
# Should show DHCP-assigned 192.168.100.2

# Release lease
dhclient -r em2
```

On Debian VM, watch dnsmasq logs:
```bash
sudo journalctl -u dnsmasq -f
```
You should see DHCP discover/offer/request/ack messages.

### Method 2: Test TFTP

On the router:
```bash
# Install tftp client if needed
pkg install tftp

# Test TFTP download
tftp 192.168.100.1
tftp> get pxelinux.0
tftp> quit

# Verify file was downloaded
ls -l pxelinux.0
```

### Method 3: Full PXE Boot Test

**IMPORTANT**: This requires FreeBSD boot files in `/srv/tftp/` on the Debian VM.

1. **Configure router BIOS/UEFI**:
   - Set boot order: Network boot first
   - Ensure BIOS mode (not UEFI)
   - Select em2 as boot interface

2. **Reboot router**:
   ```bash
   shutdown -r now
   ```

3. **Watch boot process**:
   - Router should send DHCP discover on em2
   - Debian VM responds with IP and boot file
   - Router downloads pxelinux.0 via TFTP
   - PXE boot menu appears

4. **Monitor Debian VM**:
   ```bash
   sudo journalctl -u dnsmasq -f
   sudo tcpdump -i eth0 port 69  # Watch TFTP traffic
   ```

## Expected Behavior

### Successful DHCP Test
```
# On Debian VM logs:
dnsmasq-dhcp[PID]: DHCPDISCOVER(eth0) 00:xx:xx:xx:xx:xx
dnsmasq-dhcp[PID]: DHCPOFFER(eth0) 192.168.100.2 00:xx:xx:xx:xx:xx
dnsmasq-dhcp[PID]: DHCPREQUEST(eth0) 192.168.100.2 00:xx:xx:xx:xx:xx
dnsmasq-dhcp[PID]: DHCPACK(eth0) 192.168.100.2 00:xx:xx:xx:xx:xx
```

### Successful TFTP Test
```
# On Debian VM logs:
dnsmasq-tftp[PID]: sent /srv/tftp/pxelinux.0 to 192.168.100.2
```

## Troubleshooting

### Router can't reach 192.168.100.1
- Check physical connection between em2 and Debian VM
- Verify Debian VM has IP: `ip addr show eth0`
- Check pf firewall: `pfctl -sr | grep em2`

### No DHCP response
- Check dnsmasq is running: `systemctl status dnsmasq`
- Verify dnsmasq is listening: `netstat -uln | grep 67`
- Check dnsmasq config: `dnsmasq --test`

### TFTP not working
- Verify TFTP is enabled in dnsmasq.conf
- Check file permissions: `ls -la /srv/tftp/`
- Test with tftp client first before PXE boot

### PXE boot fails
- Ensure BIOS mode (not UEFI) - config is for BIOS only
- Verify boot files are in /srv/tftp/
- Check pxelinux.cfg/default syntax
- Monitor both DHCP and TFTP logs during boot

## Next Steps

After successful testing:
1. Add FreeBSD boot files to `/srv/tftp/`
2. Configure `pxelinux.cfg/default` for FreeBSD boot
3. Test full network boot
4. Deploy to production Raspberry Pi hardware
