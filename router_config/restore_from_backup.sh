#!/bin/sh
set -eu

restore_latest_backup() {
  target="$1"
  latest_backup=$(ls -1t "${target}.bak."* 2>/dev/null | head -n 1 || true)
  if [ -z "$latest_backup" ]; then
    echo "No backup found for $target"
    return 1
  fi

  echo "Restoring $target from $latest_backup"
  cp -p "$latest_backup" "$target"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
  fi
}

restore_configs() {
  restore_latest_backup /etc/rc.conf
  restore_latest_backup /etc/pf.conf
  restore_latest_backup /usr/local/etc/dnsmasq.conf
  restore_latest_backup /usr/local/etc/dnscrypt-proxy/dnscrypt-proxy.toml
  restore_latest_backup /usr/local/etc/dnscrypt-proxy/blocklist.txt
}

fix_dnscrypt_permissions() {
  if id _dnscrypt-proxy >/dev/null 2>&1; then
    chown -R _dnscrypt-proxy:_dnscrypt-proxy /usr/local/etc/dnscrypt-proxy || true
    chmod 750 /usr/local/etc/dnscrypt-proxy || true
    chmod 640 /usr/local/etc/dnscrypt-proxy/*.toml || true
    chmod 640 /usr/local/etc/dnscrypt-proxy/blocklist.txt || true

    mkdir -p /var/log/dnscrypt-proxy
    chown -R _dnscrypt-proxy:_dnscrypt-proxy /var/log/dnscrypt-proxy || true
    chmod 750 /var/log/dnscrypt-proxy || true
  fi
}

restart_services() {
  service netif start || true
  service routing restart || true
  service pf restart || true
  service dnscrypt_proxy restart || true
  service dnsmasq restart || true
}

main() {
  require_root
  restore_configs
  fix_dnscrypt_permissions
  restart_services
  echo "Restore complete."
}

main "$@"
