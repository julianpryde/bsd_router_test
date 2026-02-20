#!/bin/bash
# Setup script for Debian PXE Boot Server
# Run with sudo
# Usage: sudo ./setup.sh <remote_ip> <iso_filename>

set -e

echo "=== Debian PXE Boot Server Setup ==="
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Parse command line arguments
if [ $# -ne 2 ]; then
    echo "Usage: sudo ./setup.sh <remote_ip> <iso_filename>"
    echo "  remote_ip: IP address of the server hosting the ISO file"
    echo "  iso_filename: Name of the .xz compressed ISO file (e.g., FreeBSD-15.0-RELEASE-amd64-dvd1.iso.xz)"
    exit 1
fi

REMOTE_IP="$1"
echo "Remote server IP: $REMOTE_IP"

ISO_FILENAME="$2"
echo "ISO filename: $ISO_FILENAME"

# Get the directory where this script is located
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo
echo "Step 1: Installing required packages..."
apt update
apt install -y dnsmasq nfs-kernel-server xz-utils p7zip-full

echo
echo "Step 2: Backing up existing configuration..."
if [ -f /etc/network/interfaces.d/pxe-boot ]; then
    cp /etc/network/interfaces.d/pxe-boot ~/pxe-boot.bak.$(date +%Y%m%d_%H%M%S)
fi
if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak.$(date +%Y%m%d_%H%M%S)
fi

echo
echo "Step 3: Copying configuration files..."
mkdir -p /etc/network/interfaces.d
cp interfaces /etc/network/interfaces.d/pxe-boot
cp dnsmasq.conf /etc/dnsmasq.conf

echo
echo "Step 4: Creating TFTP and NFS directory structure..."
mkdir -p /srv/tftp
rm -rf /srv/tftp/*  # Clean TFTP directory (only pxeboot goes here)
mkdir -p /srv/nfs/freebsd
rm -rf /srv/nfs/freebsd/*  # Clean NFS directory

# Create temp directories for extraction
TEMP_DIR=$(mktemp -d)
TEMP_ISO_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR $TEMP_ISO_DIR" EXIT

echo "Downloading FreeBSD ISO from http://$REMOTE_IP:8080/$ISO_FILENAME..."
wget "http://$REMOTE_IP:8080/$ISO_FILENAME" -O "$TEMP_DIR/$ISO_FILENAME" 2>&1 | grep -E "(^HTTP|saved|failed)" || true

if [ ! -f "$TEMP_DIR/$ISO_FILENAME" ]; then
    echo "ERROR: Failed to download $ISO_FILENAME"
    echo "Check that http://$REMOTE_IP:8080/$ISO_FILENAME is accessible"
    exit 1
fi
echo "✓ ISO downloaded"

echo "Extracting .xz archive..."
unxz -k "$TEMP_DIR/$ISO_FILENAME" -c > "$TEMP_DIR/${ISO_FILENAME%.xz}" 2>&1 | grep -E "(Error|OK)" || true
ISO_NAME="${ISO_FILENAME%.xz}"

if [ ! -f "$TEMP_DIR/$ISO_NAME" ]; then
    echo "ERROR: Failed to extract ISO from .xz archive"
    exit 1
fi
echo "✓ ISO extracted"

echo "Extracting ISO contents using 7z..."
7z x "$TEMP_DIR/$ISO_NAME" -o"$TEMP_ISO_DIR" > /dev/null 2>&1 || {
    echo "ERROR: Failed to extract ISO"
    exit 1
}
echo "✓ ISO contents extracted to temporary directory"

echo "Copying FreeBSD filesystem to NFS root..."
cp -a "$TEMP_ISO_DIR"/* /srv/nfs/freebsd/ 2>&1 | tail -20 || {
    echo "ERROR: Failed to copy filesystem"
    exit 1
}
echo "✓ Filesystem copied to /srv/nfs/freebsd"

echo "Extracting boot files..."
if [ -f "/srv/nfs/freebsd/boot/pxeboot" ]; then
    cp "/srv/nfs/freebsd/boot/pxeboot" /srv/tftp/pxeboot
    echo "✓ Copied pxeboot to TFTP"
else
    echo "ERROR: pxeboot not found in ISO"
    exit 1
fi

if [ ! -f "/srv/nfs/freebsd/boot/kernel/kernel" ]; then
    echo "ERROR: kernel not found in ISO"
    exit 1
fi

echo "✓ Boot files verified"

# Install custom loader.conf for NFS root
echo "Installing custom loader.conf..."
if [ -f "$SCRIPT_DIR/loader.conf" ]; then
    cp "$SCRIPT_DIR/loader.conf" /srv/nfs/freebsd/boot/loader.conf
    echo "✓ Boot configured to use NFS root"
fi

# Create required NFS root mount points to prevent mountroot error
# Fixes: mountroot: unable to remount devfs under /dev (error 2)
echo "Creating required NFS root mount points..."
mkdir -p /srv/nfs/freebsd/{dev,proc,etc,tmp,var,mnt,root,zroot}
chmod 755 /srv/nfs/freebsd/{dev,proc,etc,tmp,var,mnt,root,zroot}

echo
echo "Step 4.2: Setting up NFS exports..."

# Configure NFS and MOUNTD for UDP/NFSv3 (Required for FreeBSD pxeboot/loader)
# Debian 11/12 disables UDP by default
echo "Enabling NFS UDP and v3 configuration..."
NFS_CONF_TMP=$(mktemp)
cat > "$NFS_CONF_TMP" <<'EOF'
[general]
pipefs-directory=/run/rpc_pipefs

[mountd]
manage-gids=y
udp=y

[nfsd]
udp=y
vers3=y
EOF
if [ -f /etc/nfs.conf ] && cmp -s "$NFS_CONF_TMP" /etc/nfs.conf; then
    rm -f "$NFS_CONF_TMP"
else
    if [ -f /etc/nfs.conf ]; then
        cp /etc/nfs.conf /etc/nfs.conf.bak.$(date +%Y%m%d_%H%M%S)
    fi
    mv "$NFS_CONF_TMP" /etc/nfs.conf
fi

if [ -f /etc/default/nfs-kernel-server ]; then
    cp /etc/default/nfs-kernel-server /etc/default/nfs-kernel-server.bak.$(date +%Y%m%d_%H%M%S)
    if ! grep -q "^RPCMOUNTDOPTS=" /etc/default/nfs-kernel-server; then
        echo 'RPCMOUNTDOPTS="--no-tcp"' >> /etc/default/nfs-kernel-server
    fi
fi

# Configure NFS exports
if ! grep -q "/srv/nfs/freebsd" /etc/exports; then
    echo "/srv/nfs/freebsd 192.168.100.0/24(rw,sync,no_subtree_check)" >> /etc/exports
    echo "Added NFS export for /srv/nfs/freebsd"
else
    echo "NFS export already configured"
fi

# Enable and start NFS server
systemctl restart nfs-kernel-server || systemctl start nfs-kernel-server
systemctl enable nfs-kernel-server
echo "✓ NFS server configured and started"

echo
echo "Step 5: Setting permissions..."
chmod -R 755 /srv/tftp
chmod -R 755 /srv/nfs
chown -R nobody:nogroup /srv/nfs/freebsd

echo
echo "Step 6: Restarting services..."
systemctl restart networking
systemctl restart dnsmasq
systemctl enable dnsmasq
systemctl restart nfs-kernel-server || systemctl start nfs-kernel-server

echo
echo "=== Verification ==="
echo "TFTP files (pxeboot):"
ls -lh /srv/tftp/
echo ""
echo "NFS exports:"
showmount -e localhost
echo ""
if [ -f "/srv/tftp/pxeboot" ] && [ -f "/srv/nfs/freebsd/boot/loader.conf" ] && [ -f "/srv/nfs/freebsd/boot/kernel/kernel" ]; then
    echo "✓ All required files are in place:"
    echo "  - /srv/tftp/pxeboot (loaded via TFTP)"
    echo "  - /srv/nfs/freebsd/boot/loader.conf (accessed via NFS)"
    echo "  - /srv/nfs/freebsd/boot/kernel/kernel (accessed via NFS)"
    echo ""
    echo "PXE Boot Setup Complete!"
    echo "Boot sequence:"
    echo "  1. pxeboot loads via TFTP"
    echo "  2. pxeboot mounts NFS from /srv/nfs/freebsd"
    echo "  3. Kernel loads from NFS mount"
    echo "  4. Kernel boots from NFS root"
else
    echo "✗ Some files are missing. Check the output above."
    exit 1
fi
echo
echo "Network Configuration:"
echo "  This server: 192.168.100.1"
echo "  Router (em2): 192.168.100.2"
echo
