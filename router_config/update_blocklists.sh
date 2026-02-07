#!/bin/sh
##
## Convert Pi-hole blocklists to dnscrypt-proxy2 domain-only format
## 
## This script downloads Pi-hole gravity lists and converts them to
## domain-only format required by dnscrypt-proxy2
##
## Usage: ./update_blocklists.sh
##

set -e

BLOCKLIST_DIR="/usr/local/etc/dnscrypt-proxy"
OUTPUT_FILE="${BLOCKLIST_DIR}/blocklist.txt"
LOG_FILE="/var/log/dnscrypt-proxy/blocklist-update.log"
TEMP_DIR="/tmp/dnscrypt-blocklists-$$"

# Create directories if they don't exist
mkdir -p "$BLOCKLIST_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$TEMP_DIR"

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
  rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

log "Starting blocklist update..."

# Steven Black's hosts file (includes ads, malware, ransomware)
# This is one of the most comprehensive blocklists
HOSTS_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"

log "Downloading Steven Black's hosts list..."
if fetch -q -o "${TEMP_DIR}/hosts.txt" "$HOSTS_URL"; then
  log "Downloaded successfully"
  
  # Convert hosts format to domain-only format
  # Remove comments, IP addresses, and empty lines, keep only domain names
  cat "${TEMP_DIR}/hosts.txt" | \
    grep -v '^[[:space:]]*#' | \
    grep -v '^[[:space:]]*$' | \
    awk '{print $2}' | \
    grep -v '^$' | \
    sort -u > "${TEMP_DIR}/blocklist-converted.txt"
  
  log "Converted $(wc -l < "${TEMP_DIR}/blocklist-converted.txt") domains"
else
  log "ERROR: Failed to download hosts list"
  exit 1
fi

# Optional: Add additional Pi-hole compatible lists
# Uncomment to include more blocklists

# Adaway list
# log "Downloading Adaway list..."
# fetch -q -o "${TEMP_DIR}/adaway.txt" "https://adaway.org/hosts.txt" || true

# Peter Lowe's Ad Server List
log "Downloading Peter Lowe's Ad Server list..."
if fetch -q -o "${TEMP_DIR}/pgl.txt" "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts"; then
  cat "${TEMP_DIR}/pgl.txt" | \
    grep -v '^[[:space:]]*#' | \
    grep -v '^[[:space:]]*$' | \
    awk '{print $2}' | \
    grep -v '^$' | \
    sort -u >> "${TEMP_DIR}/blocklist-converted.txt"
  log "Added $(wc -l < "${TEMP_DIR}/pgl.txt") entries from Peter Lowe's list"
fi

# MVPS hosts
log "Downloading MVPS hosts..."
if fetch -q -o "${TEMP_DIR}/mvps.txt" "http://winhelp2002.mvps.org/hosts.txt"; then
  cat "${TEMP_DIR}/mvps.txt" | \
    grep -v '^[[:space:]]*#' | \
    grep -v '^[[:space:]]*$' | \
    awk '{print $2}' | \
    grep -v '^$' | \
    sort -u >> "${TEMP_DIR}/blocklist-converted.txt"
  log "Added entries from MVPS hosts"
fi

# Consolidate, deduplicate, and sort final blocklist
cat "${TEMP_DIR}/blocklist-converted.txt" | sort -u > "$OUTPUT_FILE"

# Get final count
FINAL_COUNT=$(wc -l < "$OUTPUT_FILE")
log "Final blocklist: $FINAL_COUNT unique domains"

# Verify dnscrypt-proxy can be reloaded
if pgrep -q dnscrypt-proxy; then
  log "Reloading dnscrypt-proxy2..."
  service dnscrypt_proxy reload 2>/dev/null || log "WARNING: Failed to reload dnscrypt-proxy"
else
  log "dnscrypt-proxy is not running"
fi

log "Blocklist update completed successfully"
echo "$FINAL_COUNT domains loaded from blocklists" >> "$LOG_FILE"
