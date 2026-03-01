# Debian PXE Boot Server Configuration

## Purpose
This folder contains configuration files for a Debian VM that provides PXE boot functionality for the FreeBSD router. In production, this will be a Raspberry Pi connected to the router's em2 (mgmt) interface.

## Architecture
- **Debian VM**: Provides TFTP server (for pxeboot), NFS server (for kernel), and DHCP (PXE setup)
- **Router Interface**: Connected to em2 (mgmt interface)
- **Network**: 192.168.100.0/24
  - Debian VM: 192.168.100.1
  - Router (em2): 192.168.100.2
- **Services**: 
  - DHCP (dnsmasq) - provides IP and boot parameters
  - TFTP (dnsmasq) - serves pxeboot bootloader
  - NFS (nfs-kernel-server) - serves kernel and boot files
- **Boot Mode**: BIOS PXE only (no UEFI support)

## Network Flow
1. Router boots and sends DHCP discover on em2
2. Debian VM responds with IP address, pxeboot filename, and NFS mount path
3. Router downloads pxeboot via TFTP
4. pxeboot mounts NFS and loads kernel and loader files
5. Kernel boots from NFS root filesystem (diskless boot into installer environment)
6. `rc.local` automatically launches `bsdinstall`
7. `bsdinstall` partitions the local hard drive (`da0`) and installs FreeBSD
8. `bsdinstall` copies router configuration files to the new local installation
9. System reboots from the local hard drive as a fully configured router

## Quick Start - Ansible (Recommended)

Use the Ansible playbook to configure the PXE boot server in an idempotent, declarative manner:

```bash
# Install Ansible (if not already installed)
sudo apt install ansible

# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml

# Edit inventory.ini and set your configuration
# - Update the IP address/hostname for your PXE server
# - Set remote_server_ip to the host serving the FreeBSD release files
nano inventory.ini

# Run the playbook
ansible-playbook playbook.yml
```

The playbook will:
- Install required packages (dnsmasq, nfs-kernel-server, xz-utils, p7zip-full)
- Back up any existing configuration files with timestamps
- Apply network, DHCP, and NFS configuration
- Download and extract the FreeBSD base.txz and kernel.txz from the remote server
- Create TFTP and NFS export directories
- Extract FreeBSD release files to NFS directory and copy pxeboot to TFTP directory
- Install custom loader.conf configured for NFS root boot
- Configure NFS exports for client access (with UDP/NFSv3 support)
- Set appropriate file permissions
- Start and enable dnsmasq and NFS services
- Verify the installation

The legacy shell-script workflow has been removed to keep deployment paths unambiguous for coding agents and operators.

## Manual Installation (Alternative)

If you prefer to configure manually instead of using Ansible, follow these steps:

### Install Required Packages
```bash
sudo apt update
sudo apt install -y dnsmasq nfs-kernel-server
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

### Setup TFTP and NFS Directories and Extract Release Files
```bash
sudo mkdir -p /srv/tftp
sudo mkdir -p /srv/nfs/freebsd

# Extract base and kernel to NFS export
sudo tar -xf base.txz -C /srv/nfs/freebsd/
sudo tar -xf kernel.txz -C /srv/nfs/freebsd/

# Copy pxeboot to TFTP root (for initial boot via TFTP)
sudo cp /srv/nfs/freebsd/boot/pxeboot /srv/tftp/

# Install custom loader.conf (configured for NFS root boot)
sudo cp loader.conf /srv/nfs/freebsd/boot/loader.conf

# Set permissions
sudo chmod -R 755 /srv/tftp
sudo chmod -R 755 /srv/nfs
sudo chown -R nobody:nogroup /srv/nfs/freebsd

# Configure NFS export
echo "/srv/nfs/freebsd 192.168.100.0/24(ro,sync,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -ra
```

## Files in This Directory
- `playbook.yml` - Ansible playbook for automated setup (recommended)
- `inventory.ini` - Ansible inventory file with configuration variables
- `requirements.yml` - Ansible collection requirements
- `ansible.cfg` - Ansible configuration file
- `interfaces` - Network configuration for Debian VM
- `dnsmasq.conf` - DHCP and TFTP server configuration
- `loader.conf` - FreeBSD boot loader configuration (NFS root boot)
- `README.md` - This file
- `NFS_SETUP.md` - Detailed NFS server configuration and troubleshooting
- `TESTING.md` - Testing procedures

## Additional Documentation

For detailed NFS configuration and troubleshooting, see [NFS_SETUP.md](NFS_SETUP.md).

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

## FreeBSD Release Files

The Ansible playbook downloads FreeBSD release files (`base.txz` and `kernel.txz`) from the remote HTTP server and sets up an **NFS-based PXE boot environment** that automatically installs FreeBSD to the local hard drive.

### Required Files

- **/srv/tftp/pxeboot**: First-stage PXE bootloader (TFTP)
- **/srv/nfs/freebsd/boot/**: Complete boot directory (NFS)
- **/srv/nfs/freebsd/boot/loader.conf**: Boot configuration for NFS root

### Verifying Boot Files

After running the Ansible playbook (or completing manual setup), verify the files are in place:

```bash
# TFTP directory (pxeboot only)
sudo ls -lh /srv/tftp/

# NFS export directory (kernel and loader files)
sudo ls -lh /srv/nfs/freebsd/
sudo ls -lh /srv/nfs/freebsd/boot/kernel/

# Check NFS exports
sudo showmount -e localhost
```

You should see:
- `pxeboot` in `/srv/tftp/`
- Complete `boot/` directory structure in `/srv/nfs/freebsd/`
- `boot/loader.conf` with NFS root boot configuration
- `boot/kernel/kernel` available via NFS

### Boot Process Flow (NFS Root - Automated Installer)

1. Router sends PXE boot request on em2
2. dnsmasq responds with:
   - IP address (192.168.100.2)
   - pxeboot filename (via TFTP)
   - NFS root-path (/srv/nfs/freebsd)
3. Router downloads pxeboot via TFTP (first-stage loader)
4. pxeboot mounts NFS from 192.168.100.1:/srv/nfs/freebsd
5. pxeboot chain-loads to loader_lua or loader_4th (second-stage, via NFS)
6. Loader reads `/boot/loader.conf` (from NFS mount) for boot configuration
7. Loader downloads kernel from `/boot/kernel/kernel` (via NFS) and executes it
8. Kernel mounts NFS root filesystem from 192.168.100.1:/srv/nfs/freebsd
9. FreeBSD boots as a diskless client into the installer environment
10. `/etc/rc.local` automatically launches `bsdinstall` with `/etc/installerconfig`
11. `bsdinstall` partitions the local hard drive (`da0`), extracts `base.txz` and `kernel.txz` from `/usr/freebsd-dist`, and installs the system
12. `bsdinstall` copies router configuration files from the staging directory to the new local installation
13. System reboots from the local hard drive as a fully configured router

**Note:** The automated installation process requires:
- pxeboot (TFTP): Minimal first-stage bootloader
- Complete boot/ directory structure (NFS): Including loader, scripts, and kernel
- loader.conf configured for NFS root mount
- NFS export accessible to the booting client with read-write permissions (rw)
- `base.txz` and `kernel.txz` available in `/usr/freebsd-dist` for `bsdinstall`
- `installerconfig` and `rc.local` configured to automate the installation

## Notes
- Uses Raspberry Pi OS defaults where applicable
- Only provides boot functionality; router handles all other services
- Router's pf.conf should allow TFTP traffic on em2
