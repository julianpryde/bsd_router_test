# Testing the PXE Boot Setup

## Prerequisites
1. FreeBSD router VM with 3 network interfaces (em0, em1, em2)
2. Debian VM (or Raspberry Pi) with 1 network interface
3. em2 on router connected to ens34 on Debian VM (same network segment)

## Setup Steps

### On the Debian VM

1. **Deploy configuration files**:
   ```bash
   cd debian-pxe-boot
   sudo ./setup.sh <remote_ip>
   ```
   Replace `<remote_ip>` with the IP of the host serving `base.txz` and `kernel.txz` over HTTP on port 8080.

2. **Verify network configuration**:
   ```bash
   ip addr show ens34
   # Should show: 192.168.100.1/24
   ```

3. **Check dnsmasq is running**:
   ```bash
   sudo systemctl status dnsmasq
   sudo journalctl -u dnsmasq -f  # Monitor logs
   ```

4. **Verify TFTP and NFS directories**:
   ```bash
   ls -la /srv/tftp/
   # Should contain: pxeboot only
   ls -la /srv/nfs/freebsd/boot/kernel/
   # Should contain: kernel file
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

On the router (or any system on the network):
```bash
# Install tftp client if needed
pkg install tftp

# Test TFTP download of pxeboot
tftp 192.168.100.1
tftp> get pxeboot
tftp> quit

# Verify file was downloaded
ls -l pxeboot
file pxeboot  # Should show FreeBSD x86 bootloader
```

### Method 3: Test NFS Export

On the router:
```bash
# Install nfs-utils if needed
pkg install nfs-utils

# List NFS exports from server
showmount -e 192.168.100.1

# Try mounting the NFS export
sudo mkdir -p /mnt/test
sudo mount -t nfs 192.168.100.1:/srv/nfs/freebsd /mnt/test

# Verify you can access boot files
ls -la /mnt/test/boot/
ls -la /mnt/test/boot/kernel/kernel

# Unmount
sudo umount /mnt/test
```

### Method 4: Full PXE Boot Test

**IMPORTANT**: This requires FreeBSD boot files in `/srv/tftp/` (pxeboot only) and `/srv/nfs/freebsd/` (boot directory) on the Debian VM (created by setup.sh).

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
   - Debian VM responds with IP (192.168.100.2), pxeboot filename, and NFS root-path
   - Router downloads pxeboot via TFTP
   - pxeboot loads and mounts NFS
   - pxeboot chain-loads to loader (via NFS)
   - Loader reads loader.conf and loads kernel (via NFS)
   - Kernel boots and mounts ZFS root from local storage
   - FreeBSD initializes and router is ready

4. **Monitor Debian VM** during boot:
   ```bash
   # Terminal 1: Watch dnsmasq logs
   sudo journalctl -u dnsmasq -f
   
   # Terminal 2: Watch NFS access
   sudo tail -f /var/log/syslog | grep -i nfs
   
   # Terminal 3: Monitor network traffic
   sudo tcpdump -i ens34 -nn 'port (67 or 68 or 69 or 111 or 2049)'
   ```

## Expected Behavior

### Successful DHCP Test
```
# On Debian VM dnsmasq logs:
dnsmasq-dhcp[PID]: DHCPDISCOVER(ens34) 00:xx:xx:xx:xx:xx
dnsmasq-dhcp[PID]: DHCPOFFER(ens34) 192.168.100.2 00:xx:xx:xx:xx:xx
dnsmasq-dhcp[PID]: DHCPREQUEST(ens34) 192.168.100.2 00:xx:xx:xx:xx:xx
dnsmasq-dhcp[PID]: DHCPACK(ens34) 192.168.100.2 00:xx:xx:xx:xx:xx
```

### Successful TFTP + NFS Boot
```
# dnsmasq logs show pxeboot transfer:
dnsmasq-tftp[PID]: sent /srv/tftp/pxeboot to 192.168.100.2

# NFS logs show mount and file access:
kernel: [NFS mount from 192.168.100.2:/srv/nfs/freebsd]
kernel: [Files accessed via NFS]

# FreeBSD console shows:
Found int 13h unsafe boot hook at 0xbe117 (c800:117)
FreeBSD/x86 bootstrap loader, Revision 3.0
Booting [BootFS]/boot/kernel/kernel...
...
[Kernel mounts ZFS root and boots normally]
```

## Troubleshooting

### Router can't reach 192.168.100.1
- Check physical connection between em2 and Debian VM
- Verify Debian VM has IP: `ip addr show ens34`
- Check pf firewall: `pfctl -sr | grep em2`

### No DHCP response
- Check dnsmasq is running: `systemctl status dnsmasq`
- Verify dnsmasq is listening: `netstat -uln | grep 67`
- Check dnsmasq config: `dnsmasq --test`

### TFTP not working
- Verify TFTP is enabled in dnsmasq.conf: `enable-tftp`
- Check pxeboot file exists: `ls -la /srv/tftp/pxeboot`
- Test with tftp client: `tftp 192.168.100.1` then `get pxeboot`

### NFS not working
- Verify NFS server is running: `sudo systemctl status nfs-kernel-server`
- Check NFS export configured: `sudo showmount -e localhost`
- Verify boot files in NFS: `ls -la /srv/nfs/freebsd/boot/kernel/kernel`
- Test mount from client: `showmount -e 192.168.100.1` and `mount -t nfs 192.168.100.1:/srv/nfs/freebsd /mnt/test`
- See [NFS_SETUP.md](NFS_SETUP.md) for detailed NFS troubleshooting

### FreeBSD pxeboot hangs after "Revision 3.0"

This indicates pxeboot loaded but can't mount NFS or chain-load loader. Debug with:

1. **Monitor all network traffic**:
   ```bash
   sudo tcpdump -i ens34 -nn 'port (67 or 68 or 69 or 111 or 2049)' -vv
   ```
   Watch for NFS requests (port 111, 2049) after pxeboot loads.

2. **Check dnsmasq DHCP logs**:
   ```bash
   sudo journalctl -u dnsmasq -f
   ```
   Verify DHCP root-path option is being provided:
   ```
   dhcp-option=17,/srv/nfs/freebsd
   ```

3. **Verify NFS export**:
   ```bash
   sudo showmount -e 192.168.100.1
   # Should show: /srv/nfs/freebsd 192.168.100.0/24
   ```

4. **Check loader.conf on NFS**:
   ```bash
   cat /srv/nfs/freebsd/boot/loader.conf
   ```
   Should contain: `vfs.root.mountfrom="zfs:zroot/ROOT/default"`

5. **Verify pxeboot is correct**:
   ```bash
   file /srv/tftp/pxeboot
   ```
   Should be: `Intel 80386` or `x86-64` BIOS bootloader, NOT UEFI.

6. **Check NFS server firewall**:
   ```bash
   sudo ufw status
   # Ensure ports 111, 2049 are open to 192.168.100.0/24
   ```

7. **Check NFS server logs**:
   ```bash
   sudo tail -50 /var/log/syslog | grep -i nfs
   ```

For more detailed NFS troubleshooting, see [NFS_SETUP.md](NFS_SETUP.md).

## Next Steps

After successful PXE boot testing:
1. Verify FreeBSD boots completely and all interfaces work
2. Document any kernel modules or additional boot configuration needed
3. Deploy to production Raspberry Pi hardware
4. Configure router to save state/config to persistent storage
