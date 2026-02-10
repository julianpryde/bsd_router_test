#!/bin/bash
# Setup script for Debian PXE Boot Server
# Run with sudo

set -e

echo "=== Debian PXE Boot Server Setup ==="
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

echo "Step 1: Installing required packages..."
apt update
apt install -y dnsmasq

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
echo "Step 4: Creating TFTP directory structure..."
mkdir -p /srv/tftp

echo
echo "Step 4.1: Placing FreeBSD boot files..."
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FREEBSD_BOOT_DIR="$SCRIPT_DIR/FreeBSD-15.0/boot"
if [ ! -f "$FREEBSD_BOOT_DIR/pxeboot" ]; then
    echo "ERROR: FreeBSD pxeboot not found at $FREEBSD_BOOT_DIR/pxeboot"
    echo "Ensure FreeBSD-15.0 directory exists with boot files"
    exit 1
fi
if [ ! -f "$FREEBSD_BOOT_DIR/kernel/kernel" ]; then
    echo "ERROR: FreeBSD kernel not found at $FREEBSD_BOOT_DIR/kernel/kernel"
    exit 1
fi

cp "$FREEBSD_BOOT_DIR/pxeboot" /srv/tftp/pxeboot
cp "$FREEBSD_BOOT_DIR/kernel/kernel" /srv/tftp/kernel
if [ -f "$FREEBSD_BOOT_DIR/kernel/kernel.symbols" ]; then
    cp "$FREEBSD_BOOT_DIR/kernel/kernel.symbols" /srv/tftp/kernel.symbols
fi
cp loader.conf /srv/tftp/loader.conf
echo "FreeBSD boot files copied from $FREEBSD_BOOT_DIR"

echo
echo "Step 5: Setting permissions..."
chmod -R 755 /srv/tftp
chown -R root:root /srv/tftp

echo
echo "Step 6: Restarting services..."
systemctl restart networking
systemctl restart dnsmasq
systemctl enable dnsmasq

echo
echo "=== Setup Complete ==="
echo
echo "Next steps:"
echo "1. Verify network configuration: ip addr show ens34"
echo "2. Check dnsmasq status: systemctl status dnsmasq"
echo "3. Verify FreeBSD boot files: ls -la /srv/tftp/"
echo "4. Connect this system to the router's em2 interface"
echo "5. Configure router to PXE boot on em2 interface"
echo "6. Test PXE boot from the router"
echo
echo "Network Configuration:"
echo "  This server: 192.168.100.1"
echo "  Router (em2): 192.168.100.2"
echo
