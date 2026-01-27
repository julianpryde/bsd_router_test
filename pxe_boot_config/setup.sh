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
apt install -y dnsmasq pxelinux syslinux-common

echo
echo "Step 2: Backing up existing configuration..."
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%Y%m%d_%H%M%S)
fi
if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak.$(date +%Y%m%d_%H%M%S)
fi

echo
echo "Step 3: Copying configuration files..."
cp interfaces /etc/network/interfaces
cp dnsmasq.conf /etc/dnsmasq.conf

echo
echo "Step 4: Creating TFTP directory structure..."
mkdir -p /srv/tftp/pxelinux.cfg
cp /usr/lib/PXELINUX/pxelinux.0 /srv/tftp/
cp /usr/lib/syslinux/modules/bios/*.c32 /srv/tftp/
cp pxelinux.cfg.default /srv/tftp/pxelinux.cfg/default

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
echo "1. Verify network configuration: ip addr show eth0"
echo "2. Check dnsmasq status: systemctl status dnsmasq"
echo "3. Place FreeBSD boot files in /srv/tftp/"
echo "4. Connect this system to the router's em2 interface"
echo "5. Test PXE boot from the router"
echo
echo "Network Configuration:"
echo "  This server: 192.168.100.1"
echo "  Router (em2): 192.168.100.2"
echo
