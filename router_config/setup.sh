#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
  fi
}

backup_file() {
  target="$1"
  if [ -f "$target" ]; then
    cp -p "$target" "${target}.bak.${TIMESTAMP}"
  fi
}

install_packages() {
  echo "Updating package repo..."
  pkg update -f

  echo "Installing required packages..."
  pkg install -y dnsmasq dnscrypt-proxy ca_root_nss
}

copy_configs() {
  echo "Copying configuration files..."

  # rc.conf
  backup_file /etc/rc.conf
  cp -p "${SCRIPT_DIR}/rc.conf" /etc/rc.conf

  # pf.conf
  backup_file /etc/pf.conf
  cp -p "${SCRIPT_DIR}/pf.conf" /etc/pf.conf

  # dnsmasq
  backup_file /usr/local/etc/dnsmasq.conf
  cp -p "${SCRIPT_DIR}/dnsmasq.conf" /usr/local/etc/dnsmasq.conf

  # dnscrypt-proxy
  mkdir -p /usr/local/etc/dnscrypt-proxy
  backup_file /usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml
  cp -p "${SCRIPT_DIR}/dnscrypt-proxy.toml" /usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml

  # blocklist
  backup_file /usr/local/etc/dnscrypt-proxy/blocklist.txt
  cp -p "${SCRIPT_DIR}/blocklist.txt" /usr/local/etc/dnscrypt-proxy/blocklist.txt

  # blocklist update helper
  cp -p "${SCRIPT_DIR}/update_blocklists.sh" /usr/local/sbin/update_blocklists.sh
  chmod 755 /usr/local/sbin/update_blocklists.sh

  # dnscrypt-proxy logs
  mkdir -p /var/log/dnscrypt-proxy
}

start_services() {
  echo "Starting services..."
  service pf restart || true
  service dnscrypt_proxy restart || true
  service dnsmasq restart || true
}

main() {
  require_root
  install_packages
  copy_configs
  start_services
  echo "Setup complete. Review /etc/rc.conf and /etc/pf.conf before rebooting."
}

main "$@"
