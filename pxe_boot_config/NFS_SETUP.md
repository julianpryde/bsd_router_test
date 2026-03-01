# NFS Server Setup for FreeBSD PXE Boot

## Overview

FreeBSD's `pxeboot` uses NFS (Network File System) to load the kernel and loader files. Once booted, the kernel mounts the NFS root filesystem to run the automated `bsdinstall` script, which installs FreeBSD to the local hard drive.

This document explains how the NFS setup works and how to verify it.

## Network Setup

The NFS server is configured to export boot files to the booting FreeBSD client:

```
Debian/Linux PXE Server (192.168.100.1)
  └─ NFS Export: /srv/nfs/freebsd
     ├─ boot/
     │  ├─ kernel/
     │  │  └─ kernel (loaded by pxeboot/loader via NFS)
     │  ├─ loader.conf (specifies vfs.root.mountfrom="nfs:192.168.100.1:/srv/nfs/freebsd")
     │  ├─ loader_lua, loader_4th (stage 2 bootloaders)
     │  └─ [other boot files]
     ├─ etc/
     │  ├─ installerconfig (bsdinstall automation script)
     │  └─ rc.local (triggers bsdinstall on boot)
     ├─ usr/freebsd-dist/
     │  ├─ base.txz
     │  └─ kernel.txz
     └─ (accessed by FreeBSD client at 192.168.100.2)
```

## How It Works

1. **DHCP** (dnsmasq) provides:
   - Client IP: 192.168.100.2
   - Boot file: `pxeboot`
   - Root-path: `/srv/nfs/freebsd` (NFS mount path)

2. **TFTP** (dnsmasq) delivers:
   - `/srv/tftp/pxeboot` - First-stage bootloader

3. **NFS** (nfs-kernel-server) exports:
   - `/srv/nfs/freebsd` - Contains boot files, loader, and kernel

## Setup Script

The `setup.sh` script automatically:
- Installs `nfs-kernel-server`
- Creates `/srv/nfs/freebsd` directory
- Downloads `base.txz` and `kernel.txz` from the remote HTTP server and extracts them to `/srv/nfs/freebsd`
- Configures NFS UDP and NFSv3 settings for FreeBSD `pxeboot` compatibility
- Configures `/etc/exports` to share the NFS export
- Starts and enables the NFS server

## Manual NFS Configuration (if needed)

If you need to reconfigure NFS manually:

### 1. Install NFS Server
```bash
sudo apt update
sudo apt install -y nfs-kernel-server
```

### 2. Create NFS Export Directory
```bash
sudo mkdir -p /srv/nfs/freebsd
```

### 3. Extract Release Files
```bash
sudo tar -xf /path/to/base.txz -C /srv/nfs/freebsd/
sudo tar -xf /path/to/kernel.txz -C /srv/nfs/freebsd/
```
If you are using the automated flow, `setup.sh` will download the release files from the HTTP server instead of copying from local disk.

### 4. Configure NFS Export

Edit `/etc/exports`:
```bash
sudo nano /etc/exports
```

Add this line:
```
/srv/nfs/freebsd 192.168.100.0/24(ro,sync,no_subtree_check)
```

Options explained:
- `ro` - Read-only
- `sync` - Commit changes before replying (safer)
- `no_subtree_check` - Avoid subtree verification delays
- `192.168.100.0/24` - Allow only this subnet

### 5. Set Permissions
```bash
sudo chmod -R 755 /srv/nfs/freebsd
sudo chown -R nobody:nogroup /srv/nfs/freebsd
```

### 6. Enable and Start NFS
```bash
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server
```

### 7. Verify Export
```bash
sudo showmount -e localhost
```

Output should show:
```
Export list for localhost:
/srv/nfs/freebsd 192.168.100.0/24
```

## Troubleshooting

### NFS Export Not Showing

1. Check that NFS is running:
   ```bash
   sudo systemctl status nfs-kernel-server
   ```

2. Re-export the configuration:
   ```bash
   sudo exportfs -ra
   sudo showmount -e
   ```

3. Check `/etc/exports` syntax:
   ```bash
   sudo exportfs -v
   ```

### FreeBSD pxeboot Hangs at Loader

FreeBSD `pxeboot` typically requires NFSv3 over UDP. Ensure UDP and v3 are enabled:

1. Check `/etc/nfs.conf`:
   ```bash
   sudo grep -E 'udp=|vers3=' /etc/nfs.conf
   ```

2. Verify mountd options (if present):
   ```bash
   sudo grep -E '^RPCMOUNTDOPTS=' /etc/default/nfs-kernel-server
   ```

3. Restart NFS services:
   ```bash
   sudo systemctl restart nfs-kernel-server
   ```

### Client Can't Mount NFS

1. Verify network connectivity:
   ```bash
   ping 192.168.100.1  # From the FreeBSD client
   showmount -e 192.168.100.1  # Check exports from client
   ```

2. Check firewall rules (on both systems):
   ```bash
   sudo ufw status
   sudo firewall-cmd --list-all  # if using firewalld
   ```

3. Check NFS server logs:
   ```bash
   sudo tail -f /var/log/syslog | grep nfs
   ```

### Kernel Fails to Load from NFS

1. Verify kernel file exists:
   ```bash
   ls -lh /srv/nfs/freebsd/boot/kernel/kernel
   ```

2. Check file permissions:
   ```bash
   stat /srv/nfs/freebsd/boot/kernel/kernel
   # Should be readable by everyone
   ```

3. Verify loader.conf is correct:
   ```bash
   cat /srv/nfs/freebsd/boot/loader.conf
   # Should contain: vfs.root.mountfrom="nfs:192.168.100.1:/srv/nfs/freebsd"
   ```

4. Check NFS mounts from client logs during boot

## Security Considerations

- NFS export is restricted to `192.168.100.0/24` subnet
- Export is read-only (`-ro`)
- NFS server requires authentication via DHCP binding
- In production, consider additional firewall rules or VPN protection

## Performance

- NFS can be slower than TFTP for large files
- The kernel and loader files are relatively small (tens of MB)
- After installation, the system runs from local ZFS storage (fast)

For faster boot in production, consider:
- Optimizing network MTU size (jumbo frames if network supports it)
