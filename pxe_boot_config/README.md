# Debian PXE Boot Server Configuration

## Purpose
This folder contains configuration files for a Debian VM that provides PXE boot functionality for the FreeBSD router. In production, this will be a Raspberry Pi connected to the router's em2 (mgmt) interface.

## Architecture
- **Debian VM**: Provides TFTP server and DHCP for PXE booting (BIOS only)
- **Router Interface**: Connected to em2 (mgmt interface)
- **Network**: 192.168.100.0/24
  - Debian VM: 192.168.100.1
  - Router (em2): 192.168.100.2
- **Services**: DHCP (dnsmasq) and TFTP only
- **Boot Mode**: BIOS PXE only (no UEFI support)

## Network Flow
1. Router boots and sends DHCP discover on em2
2. Debian VM responds with IP address and boot file location
3. Router downloads boot files via TFTP
4. All other router services (WAN, LAN) operate independently through em0/em1

## Installation on Debian/Raspberry Pi OS

### Install Required Packages
```bash
sudo apt update
sudo apt install -y dnsmasq pxelinux syslinux-common
```

### Apply Configuration Files
```bash
sudo mkdir -p /etc/network/interfaces.d
sudo cp interfaces /etc/network/interfaces.d/pxe-boot
sudo cp dnsmasq.conf /etc/dnsmasq.conf
sudo systemctl restart networking
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

### Setup TFTP Directory Structure
```bash
sudo mkdir -p /srv/tftp/pxelinux.cfg
sudo cp /usr/lib/PXELINUX/pxelinux.0 /srv/tftp/
sudo cp /usr/lib/syslinux/modules/bios/*.c32 /srv/tftp/
```

### Add FreeBSD Boot Files
Place FreeBSD boot files (pxeboot, kernel, etc.) in /srv/tftp/ and configure pxelinux.cfg/default accordingly.

## Files in This Directory
- `interfaces` - Network configuration for Debian VM
- `dnsmasq.conf` - DHCP and TFTP server configuration
- `pxelinux.cfg/default` - PXE boot menu configuration (template)
- `README.md` - This file

## Notes
- Uses Raspberry Pi OS defaults where applicable
- Only provides boot functionality; router handles all other services
- Router's pf.conf should allow TFTP traffic on em2
