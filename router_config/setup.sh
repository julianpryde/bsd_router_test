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
  else
    echo "WARNING: $target does not exist, skipping backup" >&2
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
  if ! command -v pkg >/dev/null 2>&1; then
    echo "Bootstrapping pkg..."
    env ASSUME_ALWAYS_YES=yes pkg bootstrap
  elif ! pkg -N >/dev/null 2>&1; then
    echo "Bootstrapping pkg..."
    env ASSUME_ALWAYS_YES=yes pkg bootstrap
  fi

  echo "Checking required packages..."
  
  MISSING_PACKAGES=""
  
  if ! pkg info dnsmasq >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES dnsmasq"
  fi
  
  if ! pkg info ca_root_nss >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES ca_root_nss"
  fi

  if ! pkg info zeek >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES zeek"
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

  # dnscrypt-proxy rc.d script
  mkdir -p /usr/local/etc/rc.d
  backup_file /usr/local/etc/rc.d/dnscrypt_proxy
  cp -p "${SCRIPT_DIR}/dnscrypt-proxy" /usr/local/etc/rc.d/dnscrypt_proxy
  chmod 755 /usr/local/etc/rc.d/dnscrypt_proxy

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

setup_zeek() {
  echo "Configuring Zeek for JA4 fingerprinting..."

  # Create Zeek configuration directory
  mkdir -p /usr/local/etc/zeek

  # Copy ZeekControl and node configuration
  backup_file /usr/local/etc/zeek/zeekctl.cfg
  cp -p "${SCRIPT_DIR}/zeek/zeekctl.cfg" /usr/local/etc/zeek/zeekctl.cfg

  backup_file /usr/local/etc/zeek/node.cfg
  cp -p "${SCRIPT_DIR}/zeek/node.cfg" /usr/local/etc/zeek/node.cfg

  # Install site-local Zeek scripts
  mkdir -p /usr/local/share/zeek/site
  backup_file /usr/local/share/zeek/site/local.zeek
  cp -p "${SCRIPT_DIR}/zeek/local.zeek" /usr/local/share/zeek/site/local.zeek
  cp -p "${SCRIPT_DIR}/zeek/ja4_fingerprint.zeek" /usr/local/share/zeek/site/ja4_fingerprint.zeek

  # Create log and spool directories
  mkdir -p /var/log/zeek
  mkdir -p /var/spool/zeek

  # Install rc.d script
  backup_file /usr/local/etc/rc.d/zeek
  cp -p "${SCRIPT_DIR}/zeek_rc.d" /usr/local/etc/rc.d/zeek
  chmod 755 /usr/local/etc/rc.d/zeek

  # Initialise ZeekControl (creates internal symlinks and checks config)
  if command -v zeekctl >/dev/null 2>&1; then
    zeekctl install
    echo "Zeek configured successfully."
  else
    echo "WARNING: zeekctl not found; Zeek may not have installed correctly." >&2
  fi
}

update_blocklists() {
  echo "Updating blocklists..."
  /usr/local/sbin/update_blocklists.sh
}

download_resolver_list() {
  echo "Downloading dnscrypt-proxy resolver list..."
  mkdir -p /var/cache/dnscrypt-proxy
  if fetch -q -o /var/cache/dnscrypt-proxy/public-resolvers.md "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"; then
    fetch -q -o /var/cache/dnscrypt-proxy/public-resolvers.md.minisig "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md.minisig"
    echo "Resolver list downloaded successfully"
  else
    echo "WARNING: Failed to download resolver list. dnscrypt-proxy will download on first start." >&2
  fi
}

wait_for_dhcp() {
  echo "Waiting for DHCP to complete on em0..."
  
  # Explicitly request a new DHCP lease
  dhclient em0 &
  DHCP_PID=$!
  
  for i in 1 2 3 4 5; do
    if ifconfig em0 | grep -q "inet "; then
      echo "✓ em0 has obtained IP address: $(ifconfig em0 | grep "inet " | awk '{print $2}')"
      wait $DHCP_PID 2>/dev/null || true
      return 0
    else
      echo "  [$i/5] Waiting for DHCP... (em0 not yet configured)"
      sleep 1
    fi
  done
  
  wait $DHCP_PID 2>/dev/null || true
  echo "⚠ Warning: em0 may not have obtained IP address yet"
}

start_services() {
  echo "Starting services..."
  service routing stop || true
  service netif restart || true
  wait_for_dhcp
  service routing start || true
  service dnscrypt_proxy restart || true
  service dnsmasq restart || true
  service pf restart || true
  service zeek restart || true
}

main() {
  require_root
  create_dnscrypt_proxy_user
  install_packages
  install_dnscrypt_proxy
  copy_configs
  setup_zeek
  update_blocklists
  download_resolver_list
  start_services
  echo "Setup complete. Review /etc/rc.conf and /etc/pf.conf before rebooting."
}

main "$@"
