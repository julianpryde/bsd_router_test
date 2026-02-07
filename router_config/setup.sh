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

create_dnscrypt_proxy_user() {
  echo "Creating _dnscrypt-proxy user..."
  if ! id _dnscrypt-proxy >/dev/null 2>&1; then
    pw useradd _dnscrypt-proxy -d /nonexistent -s /usr/sbin/nologin -c "dnscrypt-proxy user"
    echo "_dnscrypt-proxy user created"
  else
    echo "_dnscrypt-proxy user already exists"
  fi
}

install_packages() {
  echo "Checking required packages..."
  
  MISSING_PACKAGES=""
  
  if ! pkg info dnsmasq >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES dnsmasq"
  fi
  
  if ! pkg info ca_root_nss >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES ca_root_nss"
  fi
  
  if [ -z "$MISSING_PACKAGES" ]; then
    echo "All required packages are already installed"
    return 0
  fi
  
  echo "Updating package repo..."
  pkg update -f

  echo "Installing required packages:$MISSING_PACKAGES"
  pkg install -y $MISSING_PACKAGES
}

install_dnscrypt_proxy() {
  echo "Installing dnscrypt-proxy from GitHub..."
  TEMP_DIR="/tmp/dnscrypt-proxy-install-$$"
  mkdir -p "$TEMP_DIR"
  cd "$TEMP_DIR"

  # Fetch the latest dnscrypt-proxy release for FreeBSD amd64
  # Adjust the version/platform as needed
  RELEASE_URL="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.15/dnscrypt-proxy-freebsd_amd64-2.1.15.tar.gz"
  
  echo "Downloading from $RELEASE_URL..."
  if fetch -q "$RELEASE_URL"; then
    echo "Extracting..."
    tar xzf dnscrypt-proxy-freebsd_amd64-*.tar.gz
    
    if [ -f "freebsd-amd64/dnscrypt-proxy" ]; then
      echo "Installing binary..."
      install -m 755 freebsd-amd64/dnscrypt-proxy /usr/local/sbin/
      echo "dnscrypt-proxy installed to /usr/local/sbin/dnscrypt-proxy"
    else
      echo "ERROR: dnscrypt-proxy binary not found in archive" >&2
      rm -rf "$TEMP_DIR"
      return 1
    fi
  else
    echo "ERROR: Failed to download dnscrypt-proxy" >&2
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  rm -rf "$TEMP_DIR"
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

  # Set ownership and permissions for dnscrypt-proxy user
  chown -R _dnscrypt-proxy:_dnscrypt-proxy /usr/local/etc/dnscrypt-proxy
  chmod 750 /usr/local/etc/dnscrypt-proxy
  chmod 640 /usr/local/etc/dnscrypt-proxy/*.toml
  chmod 640 /usr/local/etc/dnscrypt-proxy/blocklist.txt

  chown -R _dnscrypt-proxy:_dnscrypt-proxy /var/log/dnscrypt-proxy
  chmod 750 /var/log/dnscrypt-proxy
}

update_blocklists() {
  echo "Updating blocklists..."
  /usr/local/sbin/update_blocklists.sh
}

start_services() {
  echo "Starting services..."
  service pf restart || true
  service dnscrypt_proxy restart || true
  service dnsmasq restart || true
}

main() {
  require_root
  create_dnscrypt_proxy_user
  install_packages
  install_dnscrypt_proxy
  copy_configs
  update_blocklists
  start_services
  echo "Setup complete. Review /etc/rc.conf and /etc/pf.conf before rebooting."
}

main "$@"
