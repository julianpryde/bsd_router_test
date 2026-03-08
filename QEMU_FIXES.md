# QEMU Boot Issues - Fixed

## Original Problems

1. **Terminal Hangs During Boot**
   - Cause: `-serial mon:stdio` conflicted with `-nographic` monitor
   - Result: Terminal became unresponsive and required killing the process

2. **Cannot SSH to VM** 
   - Cause: Multiple configuration issues in QEMU command

3. **Missing Boot Configuration**
   - Cause: No `-boot c` flag specified
   - Result: QEMU didn't know which disk to boot from

4. **Cloud-init Seed Image Not Detected**
   - Cause: Seed image was attached as `if=virtio,format=raw` instead of `media=cdrom`
   - Result: Cloud-init couldn't find or process the seed image

## Fixes Applied

### 1. Serial Console Fix
**Before:**
```bash
-nographic -serial mon:stdio
```
**After:**
```bash
-nographic
# OR for debugging:
-serial mon:stdio  # (without -nographic)
```
**Why:** The `-nographic` flag already uses stdio for the QEMU monitor. Adding `-serial stdio` creates a conflict.

### 2. Boot Configuration Added
**Before:**
```bash
-drive if=virtio,file=...,format=qcow2
```
**After:**
```bash
-boot c \
-drive if=virtio,file=...,format=qcow2
```
**Why:** Tells QEMU to boot from the first disk (c = drive C for legacy compatibility).

### 3. Cloud-init Seed Image Fix
**Before:**
```bash
-drive file=.../seed.img,if=virtio,format=raw
```
**After:**
```bash
-drive file=.../seed.img,media=cdrom
```
**Why:** Cloud-init expects the seed image to appear as CD-ROM media (ISO), not a virtio block device.

### 4. KVM Support Removed
**Removed:**
```bash
-enable-kvm
```
**Why:** WSL2 doesn't support nested KVM virtualization. Removing this prevents the "invalid accelerator kvm" error.

### 5. Image Format Changed
**Before:** Debian ARM64 generic cloud image
**After:** Ubuntu 22.04 ARM64 cloud image
**Why:** Better compatibility with QEMU virt machine type.

## Current Status

The QEMU command now boots without hanging the terminal and doesn't hang on startup. However, SSH access still times out during banner exchange, which suggests:

1. The VM is partially booting
2. SSH port is listening (confirmed with netcat)
3. SSH service is not responding to connections properly
4. Likely cause: Cloud images may have limited compatibility with QEMU virt on WSL2

## Testing Results

✓ Terminal no longer hangs
✓ QEMU starts without errors  
✓ SSH port (2222) becomes available/listening
✗ SSH banner exchange times out (needs further investigation)

## Recommended Next Steps

1. Try connecting with debugging:
   ```bash
   ssh -vvv -i testing_key -p 2222 root@127.0.0.1
   ```

2. Try raw telnet to see if ANY response comes back:
   ```bash
   telnet 127.0.0.1 2222
   ```

3. Try a different image (Alpine Linux ARM64 or Busybox) for testing

4. Check if using 'screen' can capture detailed boot output:
   ```bash
   screen -L qemu-system-aarch64 ... -serial mon:stdio
   ```

5. Consider using native Linux with KVM enabled for full ARM64 virtualization support
