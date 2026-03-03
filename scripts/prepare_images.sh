#!/bin/sh
# Prepare QEMU base images for automated testing
# - Injects SSH keys for Ansible access
# - Enables SSH on first boot
# - Uses virt-customize to modify image before booting
#
# Troubleshooting:
# If virt-customize fails with supermin errors:
#   1. Try: export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
#   2. Run: libguestfs-test-tool
#   3. The script will fall back to cloud-init method automatically
#
# Requirements:
#   - libguestfs-tools (for virt-customize)
#   - OR cloud-image-utils (for cloud-init fallback)

set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"
TEST_KEY="$PROJECT_ROOT/testing_key"
TEST_KEY_PUB="$PROJECT_ROOT/testing_key.pub"

mkdir -p "$IMAGES_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN] $*${NC}"
}

log_error() {
  echo -e "${RED}[ERROR] $*${NC}"
}

log_success() {
  echo -e "${GREEN}[SUCCESS] $*${NC}"
}

# Generate SSH keys if they don't exist
generate_ssh_keys() {
  if [ -f "$TEST_KEY" ] && [ -f "$TEST_KEY_PUB" ]; then
    log_info "SSH keys already exist at $TEST_KEY"
    return 0
  fi

  log_info "Generating temporary SSH keys for testing..."
  ssh-keygen -t ed25519 -f "$TEST_KEY" -N "" -C "qemu-test-key"
  chmod 600 "$TEST_KEY"
  chmod 644 "$TEST_KEY_PUB"
  log_success "SSH keys generated"
}

# Prepare Pi (Debian ARM64) image
prepare_pi_image() {
  PI_IMAGE="$IMAGES_DIR/rpi_base.qcow2"
  PI_SOURCE="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2"

  if [ ! -f "$PI_IMAGE" ]; then
    log_info "Downloading Debian ARM64 image for Pi emulation..."
    log_warn "This is a large file (~400 MB). First download only."
    
    if ! command -v wget >/dev/null 2>&1; then
      log_error "wget not found. Install wget or download manually:"
      echo "  wget -O $PI_IMAGE $PI_SOURCE"
      exit 1
    fi

    wget -O "$PI_IMAGE" "$PI_SOURCE" || {
      log_error "Failed to download Pi image"
      exit 1
    }
    log_success "Pi image downloaded"
  else
    log_info "Pi image already exists at $PI_IMAGE"
  fi

  # Check if virt-customize is available
  if ! command -v virt-customize >/dev/null 2>&1; then
    log_error "virt-customize not found. Install libguestfs-tools:"
    echo "  sudo apt-get install libguestfs-tools"
    log_warn "Falling back to cloud-init method..."
    prepare_pi_image_manual
    return $?
  fi

  log_info "Customizing Pi image with SSH and keys..."
  log_warn "This may take several minutes on first run..."
  
  # Set libguestfs backend to direct mode (works better for non-root users)
  export LIBGUESTFS_BACKEND=direct
  
  # Enable debugging if the operation fails
  if ! virt-customize -a "$PI_IMAGE" \
    --install openssh-server \
    --run-command 'systemctl enable ssh' \
    --ssh-inject root:file:"$TEST_KEY_PUB" \
    2>/tmp/virt-customize-error.log
  then
    log_error "Failed to customize Pi image"
    log_error "Trying alternative method: manual cloud-init setup"
    
    # Alternative: Use cloud-init to inject SSH key
    prepare_pi_image_manual
    return $?
  fi

  log_success "Pi image customized with SSH and test keys"
}

# Fallback method using cloud-init
prepare_pi_image_manual() {
  log_info "Setting up image with cloud-init (alternative method)..."
  
  # Create cloud-init user-data
  CLOUD_INIT_DIR="$IMAGES_DIR/cloud-init"
  mkdir -p "$CLOUD_INIT_DIR"
  
  # Read the actual public key from testing_key.pub
  if [ ! -f "$TEST_KEY_PUB" ]; then
    log_error "SSH public key not found at $TEST_KEY_PUB"
    return 1
  fi
  
  SSH_KEY_CONTENT=$(cat "$TEST_KEY_PUB")
  
  cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
ssh_pwauth: false
disable_root: false
users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - $SSH_KEY_CONTENT

packages:
  - openssh-server
  - openssh-client

write_files:
  - path: /etc/ssh/sshd_config.d/99-cloud-init.conf
    content: |
      PermitRootLogin yes
      PubkeyAuthentication yes
      PasswordAuthentication no
    permissions: '0644'

runcmd:
  - systemctl enable ssh
  - systemctl restart ssh
  - echo "Cloud-init SSH setup completed at \$(date)" >> /var/log/cloud-init.log

EOF
  
  cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: qemu-pi-test
local-hostname: pxe-server
EOF

  if command -v cloud-localds >/dev/null 2>&1; then
    log_info "Using cloud-localds to create seed image..."
    cloud-localds "$CLOUD_INIT_DIR/seed.img" "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    if [ $? -eq 0 ]; then
      log_success "Created cloud-init seed image with cloud-localds"
      log_info "SSH key injected from $TEST_KEY_PUB"
      return 0
    else
      log_error "Failed to create cloud-init seed image with cloud-localds"
      # Fall through to mkisofs attempt
    fi
  fi

  log_info "Creating cloud-init ISO seed image with mkisofs/genisoimage..."
  
  if command -v mkisofs >/dev/null 2>&1; then
    MKISOFS_CMD="mkisofs"
  elif command -v genisoimage >/dev/null 2>&1; then
    MKISOFS_CMD="genisoimage"
  else
    log_error "Neither mkisofs nor genisoimage found. Install genisoimage."
    echo "  sudo apt-get install genisoimage"
    return 1
  fi
  
  # Create a temporary directory for ISO content to ensure correct filenames
  ISO_BUILD_DIR=$(mktemp -d)
  cp "$CLOUD_INIT_DIR/user-data" "$ISO_BUILD_DIR/user-data"
  cp "$CLOUD_INIT_DIR/meta-data" "$ISO_BUILD_DIR/meta-data"

  "$MKISOFS_CMD" -output "$CLOUD_INIT_DIR/seed.img" \
    -volid cidata -joliet -rock \
    -input-charset utf-8 \
    "$ISO_BUILD_DIR" 2>/dev/null
  
  rm -rf "$ISO_BUILD_DIR"
  
  if [ $? -eq 0 ]; then
    log_success "Created cloud-init seed image with $MKISOFS_CMD"
    log_info "SSH key injected from $TEST_KEY_PUB"
    return 0
  else
    log_error "Failed to create cloud-init seed image"
    return 1
  fi
}

# Verify images
verify_images() {
  log_info "Verifying images..."

  if [ ! -f "$IMAGES_DIR/rpi_base.qcow2" ]; then
    log_error "Pi image not found at $IMAGES_DIR/rpi_base.qcow2"
    return 1
  fi

  if [ ! -f "$TEST_KEY" ] || [ ! -f "$TEST_KEY_PUB" ]; then
    log_error "SSH keys not found"
    return 1
  fi

  log_success "All images and keys verified"
  
  # Show file info
  log_info "Pi image: $(du -h "$IMAGES_DIR/rpi_base.qcow2" | cut -f1)"
  log_info "Test key: $TEST_KEY (permissions: $(stat -c %a "$TEST_KEY"))"
  
  # Check if cloud-init was used
  if [ -f "$IMAGES_DIR/cloud-init/seed.img" ]; then
    log_warn "Cloud-init seed image detected: $IMAGES_DIR/cloud-init/seed.img"
    log_warn "Add this parameter when starting the Pi QEMU:"
    echo "  -drive file=$IMAGES_DIR/cloud-init/seed.img,if=virtio,format=raw"
  fi
}

# Main execution
main() {
  log_info "=== QEMU Test Environment Image Preparation ==="
  log_info "Project root: $PROJECT_ROOT"
  log_info "Images directory: $IMAGES_DIR"
  
  generate_ssh_keys
  prepare_pi_image
  verify_images
  
  log_success "=== Image preparation complete ==="
  log_info "Ready to run manual test commands from Phase 6"
}

main "$@"
