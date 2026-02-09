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

## Quick Start

Run the automated setup script to configure the PXE boot server:

```bash
sudo bash setup.sh
```

This script will:
- Install required packages (dnsmasq, pxelinux, syslinux-common)
- Back up any existing configuration files
- Apply network and DHCP/TFTP configuration
- Create and populate the TFTP directory structure
- Copy FreeBSD boot files into `/srv/tftp/` if `FreeBSD-15.0/boot/` is present next to `setup.sh`
- Set appropriate file permissions
- Start and enable the dnsmasq service

After setup completes, follow the next steps displayed by the script.

## Manual Installation (Alternative)

If you prefer to configure manually instead of using `setup.sh`, follow these steps:

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
sudo cp pxelinux.cfg.default /srv/tftp/pxelinux.cfg/default
sudo chmod -R 755 /srv/tftp
sudo chown -R root:root /srv/tftp
```

## Files in This Directory
- `setup.sh` - Automated setup script (recommended)
- `interfaces` - Network configuration for Debian VM
- `dnsmasq.conf` - DHCP and TFTP server configuration
- `pxelinux.cfg.default` - PXE boot menu configuration
- `README.md` - This file

## Verification

After setup, verify the installation:

```bash
# Check network configuration
ip addr show

# Check dnsmasq status
systemctl status dnsmasq

# Verify TFTP files are in place
ls -la /srv/tftp/
```

## FreeBSD Boot Files

After setup completes, the script will automatically place the FreeBSD boot files in `/srv/tftp/` if the directory `FreeBSD-15.0` exists next to `setup.sh`. If it is not present, you must place the files manually. These files are required for the router to boot from the network.

### Required Files

```
/srv/tftp/
├── pxeboot                 # FreeBSD PXE bootloader (REQUIRED)
├── kernel                  # FreeBSD kernel (REQUIRED)
├── kernel.symbols          # Kernel symbols (optional, for debugging)
└── boot/
    ├── kernel.gz           # Compressed kernel (optional alternative)
    ├── mfsroot.gz          # Minimal filesystem (optional, for diskless boot)
    └── device.hints        # Device configuration hints (optional)
```

### Obtaining Boot Files
If you place the directory `FreeBSD-15.0` alongside setup.sh, the `setup.sh` script will automatically place them in their correct spot in `/srv/tftp/`.

**Option 1: From an existing FreeBSD system**
```bash
# SSH to a FreeBSD system or copy from local installation
cp /boot/pxeboot /srv/tftp/
cp /boot/kernel/kernel /srv/tftp/
cp /boot/kernel.symbols /srv/tftp/  # optional
```

**Option 2: From FreeBSD release media**
1. Download a FreeBSD release ISO or memstick image from [freebsd.org](https://www.freebsd.org)
2. Extract or mount the image
3. Locate `boot/pxeboot` and `boot/kernel/kernel`
4. Copy to `/srv/tftp/`

### Set Permissions

After placing the files, ensure correct permissions:

```bash
sudo chmod -R 755 /srv/tftp/
sudo chown -R root:root /srv/tftp/
```

### Verification

Verify all boot files are in place:

```bash
ls -la /srv/tftp/ | grep -E 'pxeboot|kernel'
```

## Next Steps

1. Ensure FreeBSD boot files are in `/srv/tftp/` (the script copies them automatically if they arepresent)
2. Connect this system to the router's em2 interface
3. Test PXE boot from the router

## Notes
- Uses Raspberry Pi OS defaults where applicable
- Only provides boot functionality; router handles all other services
- Router's pf.conf should allow TFTP traffic on em2
