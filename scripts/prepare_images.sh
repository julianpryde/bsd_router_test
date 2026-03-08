#!/bin/sh
# Prepare QEMU base images for automated testing
# - Injects SSH keys for Ansible access
# - Enables SSH on first boot
# - Uses cloud-init to configure the image on first boot
#
# Requirements:
#   - cloud-image-utils or genisoimage (for creating cloud-init seed image)
#     Install: sudo apt-get install cloud-image-utils
#     Or: sudo apt-get install genisoimage
#   - wget (for downloading base images)
#   - qemu-system-x86_64 (for running x86_64 VMs with KVM)
#   - KVM access: sudo usermod -aG kvm $USER  (then log out and back in)

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

# Download Ubuntu x86_64 base image (has cloud-init pre-installed)
download_base_image() {
  BASE_IMAGE="$IMAGES_DIR/base.qcow2"
  # Ubuntu 24.04 LTS cloud image (known to have cloud-init working)
  BASE_SOURCE="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"

  if [ -f "$BASE_IMAGE" ]; then
    log_info "Base image already exists at $BASE_IMAGE"
    return 0
  fi

  log_info "Downloading Ubuntu 24.04 LTS x86_64 cloud image..."
  log_warn "This is a large file (~300 MB). First download only."

  if ! command -v wget >/dev/null 2>&1; then
    log_error "wget not found. Install wget or download manually:"
    echo "  wget -O $BASE_IMAGE $BASE_SOURCE"
    return 1
  fi

  wget -O "$BASE_IMAGE" "$BASE_SOURCE" || {
    log_error "Failed to download base image"
    return 1
  }
  log_success "Base image downloaded"
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

  # Create user-data with cloud-config for SSH key injection
  cat > "$CLOUD_INIT_DIR/user-data" <<'EOF'
#cloud-config
ssh_pwauth: false
disable_root: false

packages:
  - openssh-server

users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - SSH_PUB_KEY_PLACEHOLDER
    shell: /bin/bash
    sudo: false

runcmd:
  - systemctl enable ssh
  - systemctl start ssh

final_message: "Cloud-init has finished. System is ready."
EOF

  # Replace the placeholder with the actual key
  sed -i "s|SSH_PUB_KEY_PLACEHOLDER|${SSH_KEY_CONTENT}|g" "$CLOUD_INIT_DIR/user-data"

  # Create meta-data
  cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: qemu-test-$(date +%s)
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

# Check KVM availability
check_kvm() {
  if [ ! -e /dev/kvm ]; then
    log_warn "KVM device not found. VM will run without acceleration (slow)."
    KVM_FLAG=""
    return
  fi
  if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    log_warn "/dev/kvm exists but is not accessible. Run: sudo usermod -aG kvm \$USER"
    log_warn "VM will run without acceleration until you log out and back in."
    KVM_FLAG=""
    return
  fi
  log_success "KVM available and accessible"
  KVM_FLAG="-enable-kvm -cpu host"
}

# Verify all components
verify_setup() {
  log_info "Verifying setup..."

  if [ ! -f "$IMAGES_DIR/base.qcow2" ]; then
    log_error "Base image not found at $IMAGES_DIR/base.qcow2"
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

  check_kvm

  log_success "All components verified"

  # Show file info
  log_info "Base image: $(du -h "$IMAGES_DIR/base.qcow2" | cut -f1)"
  log_info "Cloud-init seed: $(du -h "$IMAGES_DIR/cloud-init/seed.img" | cut -f1)"
  log_info "SSH private key: $TEST_KEY (permissions: $(stat -c %a "$TEST_KEY" 2>/dev/null || stat -f %A "$TEST_KEY"))"

  echo ""
  log_success "=== Ready to start VM ==="
  echo ""
  echo "Start QEMU with:"
  echo ""
  echo "  qemu-system-x86_64 \\"
  echo "    -M q35 ${KVM_FLAG:--cpu qemu64} -m 2048 \\"
  if [ -n "$KVM_FLAG" ]; then
    echo "    -enable-kvm \\"
  fi
  echo "    -boot c \\"
  echo "    -drive if=virtio,file=$IMAGES_DIR/base.qcow2,format=qcow2 \\"
  echo "    -drive file=$IMAGES_DIR/cloud-init/seed.img,media=cdrom \\"
  echo "    -netdev user,id=wan,hostfwd=tcp::2222-:22 \\"
  echo "    -device virtio-net,netdev=wan \\"
  echo "    -netdev socket,id=lan,listen=:12345 \\"
  echo "    -device virtio-net,netdev=lan \\"
  echo "    -nographic"
  echo ""
  log_info "Wait 60-90 seconds for cloud-init to complete, then SSH in with:"
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
  download_base_image || exit 1
  create_cloud_init_config || exit 1
  create_cloud_init_seed || exit 1
  verify_setup || exit 1

  log_success "=== Image preparation complete ==="
}

main "$@"
