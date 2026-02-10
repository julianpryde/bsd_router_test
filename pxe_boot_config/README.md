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
- Install required packages (dnsmasq)
- Back up any existing configuration files
- Apply network and DHCP/TFTP configuration
- Create and populate the TFTP directory structure
- Copy FreeBSD boot files from `FreeBSD-15.0/boot/` into `/srv/tftp/`
- Copy FreeBSD bootloader configuration (`loader.conf`) to TFTP
- Set appropriate file permissions
- Start and enable the dnsmasq service

After setup completes, follow the next steps displayed by the script.

## Manual Installation (Alternative)

If you prefer to configure manually instead of using `setup.sh`, follow these steps:

### Install Required Packages
```bash
sudo apt update
sudo apt install -y dnsmasq
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

### Setup TFTP Directory and Copy FreeBSD Boot Files
```bash
sudo mkdir -p /srv/tftp
sudo cp FreeBSD-15.0/boot/pxeboot /srv/tftp/pxeboot
sudo cp FreeBSD-15.0/boot/kernel/kernel /srv/tftp/kernel
sudo cp FreeBSD-15.0/boot/kernel/kernel.symbols /srv/tftp/kernel.symbols
sudo cp loader.conf /srv/tftp/loader.conf
sudo chmod -R 755 /srv/tftp
sudo chown -R root:root /srv/tftp
```

## Files in This Directory
- `setup.sh` - Automated setup script (recommended)
- `interfaces` - Network configuration for Debian VM
- `dnsmasq.conf` - DHCP and TFTP server configuration for FreeBSD PXE
- `loader.conf` - FreeBSD bootloader configuration (copied to `/srv/tftp/loader.conf`)
- `FreeBSD-15.0/` - FreeBSD boot files directory
  - `boot/pxeboot` - FreeBSD PXE bootloader
  - `boot/kernel/kernel` - FreeBSD kernel
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

The setup script automatically copies FreeBSD boot files from the `FreeBSD-15.0` directory if it exists. These files are required for the router to PXE boot successfully.

### Required Files in /srv/tftp/

```
/srv/tftp/
├── pxeboot                 # FreeBSD PXE bootloader (REQUIRED)
├── kernel                  # FreeBSD kernel (REQUIRED)
├── kernel.symbols          # Kernel symbols (optional, for debugging)
└── loader.conf             # Boot loader configuration (REQUIRED)
```

### File Requirements

- **pxeboot** (446K): The FreeBSD PXE bootloader that runs on the client
- **kernel** (28M): The FreeBSD kernel image
- **loader.conf**: Configuration file for the boot loader

### Verifying Boot Files

After running setup.sh, verify the files are in place:

```bash
sudo ls -lh /srv/tftp/ | grep -E 'pxeboot|kernel|loader.conf'
```

You should see:
```
-r--r--r-- pxeboot (446K)
-r--r--r-- kernel (28M)
-r--r--r-- loader.conf
```

### Boot Process Flow

1. Router sends PXE boot request on em2
2. dnsmasq responds with pxeboot location
3. Router downloads pxeboot via TFTP
4. pxeboot loads and reads loader.conf
5. pxeboot loads the kernel from /srv/tftp/kernel
6. FreeBSD kernel boots and initializes the router

## Notes
- Uses Raspberry Pi OS defaults where applicable
- Only provides boot functionality; router handles all other services
- Router's pf.conf should allow TFTP traffic on em2
