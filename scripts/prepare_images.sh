#!/bin/sh
# Prepare QEMU base images for automated testing
# - Injects SSH keys for Ansible access
# - Enables SSH on first boot
# - Uses cloud-init to configure the image on first boot
#
# Requirements:
#   - genisoimage (for creating cloud-init seed image)
#     Install: sudo apt-get install genisoimage
#   - wget (for downloading base images)

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

# Download Pi base image
download_pi_image() {
  PI_IMAGE="$IMAGES_DIR/rpi_base.qcow2"
  PI_SOURCE="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2"

  if [ -f "$PI_IMAGE" ]; then
    log_info "Pi image already exists at $PI_IMAGE"
    return 0
  fi

  log_info "Downloading Debian ARM64 cloud image for Pi emulation..."
  log_warn "This is a large file (~400 MB). First download only."
  
  if ! command -v wget >/dev/null 2>&1; then
    log_error "wget not found. Install wget or download manually:"
    echo "  wget -O $PI_IMAGE $PI_SOURCE"
    return 1
  fi

  wget -O "$PI_IMAGE" "$PI_SOURCE" || {
    log_error "Failed to download Pi image"
    return 1
  }
  log_success "Pi image downloaded"
}

# Create cloud-init configuration
create_cloud_init_config() {
  log_info "Creating cloud-init configuration..."
  
  CLOUD_INIT_DIR="$IMAGES_DIR/cloud-init"
  mkdir -p "$CLOUD_INIT_DIR"
  
  # Read the actual public key from testing_key.pub
  if [ ! -f "$TEST_KEY_PUB" ]; then
    log_error "SSH public key not found at $TEST_KEY_PUB"
    return 1
  fi
  
  SSH_KEY_CONTENT=$(cat "$TEST_KEY_PUB")
  
  # Create user-data with SSH key injection
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
  
  # Create meta-data
  cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: qemu-pi-test-$(date +%s)
local-hostname: pxe-server
EOF

  log_success "Cloud-init configuration created"
  log_info "SSH key injected: ${SSH_KEY_CONTENT%% *}..."
}

# Create cloud-init seed image
create_cloud_init_seed() {
  log_info "Creating cloud-init seed image..."
  
  CLOUD_INIT_DIR="$IMAGES_DIR/cloud-init"
  
  # Try cloud-localds first (cleaner method)
  if command -v cloud-localds >/dev/null 2>&1; then
    log_info "Using cloud-localds to create seed image..."
    cloud-localds "$CLOUD_INIT_DIR/seed.img" \
      "$CLOUD_INIT_DIR/user-data" \
      "$CLOUD_INIT_DIR/meta-data" 2>/dev/null
    
    if [ $? -eq 0 ]; then
      log_success "Cloud-init seed image created with cloud-localds"
      return 0
    else
      log_warn "cloud-localds failed, trying mkisofs/genisoimage..."
    fi
  fi

  # Fall back to mkisofs/genisoimage
  if command -v mkisofs >/dev/null 2>&1; then
    MKISOFS_CMD="mkisofs"
  elif command -v genisoimage >/dev/null 2>&1; then
    MKISOFS_CMD="genisoimage"
  else
    log_error "No ISO creation tool found. Install one of:"
    echo "  sudo apt-get install cloud-image-utils  # for cloud-localds"
    echo "  sudo apt-get install genisoimage         # for genisoimage"
    return 1
  fi
  
  # Create a temporary directory for ISO content
  ISO_BUILD_DIR=$(mktemp -d)
  cp "$CLOUD_INIT_DIR/user-data" "$ISO_BUILD_DIR/user-data"
  cp "$CLOUD_INIT_DIR/meta-data" "$ISO_BUILD_DIR/meta-data"

  "$MKISOFS_CMD" -output "$CLOUD_INIT_DIR/seed.img" \
    -volid cidata -joliet -rock \
    -input-charset utf-8 \
    "$ISO_BUILD_DIR" 2>/dev/null
  
  result=$?
  rm -rf "$ISO_BUILD_DIR"
  
  if [ $result -eq 0 ]; then
    log_success "Cloud-init seed image created with $MKISOFS_CMD"
    return 0
  else
    log_error "Failed to create cloud-init seed image"
    return 1
  fi
}

# Verify all components
verify_setup() {
  log_info "Verifying setup..."

  if [ ! -f "$IMAGES_DIR/rpi_base.qcow2" ]; then
    log_error "Pi image not found at $IMAGES_DIR/rpi_base.qcow2"
    return 1
  fi

  if [ ! -f "$IMAGES_DIR/cloud-init/seed.img" ]; then
    log_error "Cloud-init seed image not found"
    return 1
  fi

  if [ ! -f "$TEST_KEY" ] || [ ! -f "$TEST_KEY_PUB" ]; then
    log_error "SSH keys not found"
    return 1
  fi

  # Check key permissions
  KEY_PERMS=$(stat -c %a "$TEST_KEY" 2>/dev/null || stat -f %A "$TEST_KEY")
  if [ "$KEY_PERMS" != "600" ]; then
    log_warn "Fixing SSH key permissions..."
    chmod 600 "$TEST_KEY"
  fi

  log_success "All components verified"
  
  # Show file info
  log_info "Pi base image: $(du -h "$IMAGES_DIR/rpi_base.qcow2" | cut -f1)"
  log_info "Cloud-init seed: $(du -h "$IMAGES_DIR/cloud-init/seed.img" | cut -f1)"
  log_info "SSH private key: $TEST_KEY (permissions: $(stat -c %a "$TEST_KEY" 2>/dev/null || stat -f %A "$TEST_KEY"))"
  
  echo ""
  log_success "=== Ready to start Pi emulator ==="
  echo ""
  echo "Start the Pi QEMU with:"
  echo ""
  echo "  qemu-system-aarch64 \\"
  echo "    -M virt -cpu cortex-a57 -m 2048 \\"
  echo "    -drive if=virtio,file=$IMAGES_DIR/rpi_base.qcow2,format=qcow2 \\"
  echo "    -drive file=$IMAGES_DIR/cloud-init/seed.img,if=virtio,format=raw \\"
  echo "    -netdev user,id=wan,hostfwd=tcp::2222-:22 \\"
  echo "    -device virtio-net,netdev=wan \\"
  echo "    -netdev socket,id=lan,listen=:12345 \\"
  echo "    -device virtio-net,netdev=lan \\"
  echo "    -nographic -serial mon:stdio"
  echo ""
  log_info "Wait 60-90 seconds for cloud-init to complete, then test with:"
  echo "  ssh -i $TEST_KEY -p 2222 root@127.0.0.1"
  echo ""
}

# Main execution
main() {
  log_info "=== QEMU Test Environment Image Preparation ==="
  log_info "Using cloud-init for image configuration"
  log_info "Project root: $PROJECT_ROOT"
  log_info "Images directory: $IMAGES_DIR"
  echo ""
  
  generate_ssh_keys || exit 1
  download_pi_image || exit 1
  create_cloud_init_config || exit 1
  create_cloud_init_seed || exit 1
  verify_setup || exit 1
  
  log_success "=== Image preparation complete ==="
}

main "$@"
