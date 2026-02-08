#!/bin/sh
set -eu

# Cleanup script to remove all but the most recent backup files created by setup.sh
# Backups are named with pattern: <original_file>.bak.YYYYMMDDHHMMSS

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
  fi
}

cleanup_backups() {
  local backup_dir="$1"
  local base_name="$2"
  
  # Find all backup files for this base name
  # They should be in the format: ${base_name}.bak.YYYYMMDDHHMMSS
  local backups
  backups=$(find "$backup_dir" -maxdepth 1 -name "${base_name}.bak.*" -type f 2>/dev/null | sort)
  
  if [ -z "$backups" ]; then
    return 0
  fi
  
  local backup_count
  backup_count=$(echo "$backups" | wc -l)
  
  # Keep only if we have more than one backup
  if [ "$backup_count" -le 1 ]; then
    return 0
  fi
  
  # Remove all but the most recent (last line when sorted)
  local most_recent
  most_recent=$(echo "$backups" | tail -1)
  
  echo "$backups" | while read -r backup_file; do
    if [ "$backup_file" != "$most_recent" ]; then
      echo "Removing old backup: $backup_file"
      rm -f "$backup_file"
    fi
  done
}

main() {
  require_root
  
  # List of files that are backed up by setup.sh
  # Each entry is "directory:filename"
  files_to_clean="/etc:rc.conf /etc:pf.conf /usr/local/etc:dnsmasq.conf /usr/local/etc/rc.d:dnscrypt_proxy /usr/local/etc/dnscrypt-proxy:dnscrypt-proxy.toml /usr/local/etc/dnscrypt-proxy:blocklist.txt"
  
  echo "Cleaning up old backup files (keeping only the most recent for each)..."
  
  for file_entry in $files_to_clean; do
    backup_dir="${file_entry%:*}"
    filename="${file_entry#*:}"
    
    # Only process if directory exists
    if [ -d "$backup_dir" ]; then
      cleanup_backups "$backup_dir" "$filename"
    fi
  done
  
  echo "Backup cleanup complete."
}

main "$@"
