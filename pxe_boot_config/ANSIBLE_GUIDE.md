# Ansible Playbook Usage Guide

## Prerequisites

1. **Install Ansible**:
   ```bash
   # Debian/Ubuntu
   sudo apt update
   sudo apt install ansible
   
   # macOS
   brew install ansible
   
   # Or via pip
   pip install ansible
   ```

2. **Install Required Collections**:
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

## Configuration

### Method 1: Using Inventory File (Recommended)

Edit `inventory.ini` and set your values:

```ini
[pxe_server]
192.168.244.135 ansible_user=root

[pxe_server:vars]
remote_server_ip=172.21.135.127
freebsd_iso_filename=FreeBSD-15.0-RELEASE-amd64-disc1.iso.xz
```

Then run:
```bash
ansible-playbook playbook.yml
```

### Method 2: Using Command-Line Variables

```bash
ansible-playbook playbook.yml \
  -i "192.168.244.135," \
  -e "remote_server_ip=172.21.135.127" \
  -e "freebsd_iso_filename=FreeBSD-15.0-RELEASE-amd64-disc1.iso.xz" \
  -u root
```

### Method 3: Using Extra Vars File

Create a file `vars.yml`:
```yaml
remote_server_ip: 172.21.135.127
freebsd_iso_filename: FreeBSD-15.0-RELEASE-amd64-disc1.iso.xz
```

Run with:
```bash
ansible-playbook playbook.yml -e @vars.yml
```

## Common Options

### Dry Run (Check Mode)
See what would change without making any changes:
```bash
ansible-playbook playbook.yml --check
```

### Verbose Output
Get detailed information about what's happening:
```bash
ansible-playbook playbook.yml -v    # verbose
ansible-playbook playbook.yml -vv   # more verbose
ansible-playbook playbook.yml -vvv  # very verbose (debug)
```

### Run with Password Prompt
If you need to enter the SSH password:
```bash
ansible-playbook playbook.yml --ask-pass
```

### Run with Sudo Password
If your user needs to use sudo with a password:
```bash
ansible-playbook playbook.yml --ask-become-pass
```

### Run Specific Tasks (Tags)
The playbook doesn't currently use tags, but you can skip sections:
```bash
# Skip verification step
ansible-playbook playbook.yml --limit pxe_server
```

## Troubleshooting

### Test Connectivity
```bash
ansible pxe_server -m ping
```

### Check Host Variables
```bash
ansible-inventory --host <hostname> --yaml
```

### Run Ad-hoc Commands
```bash
# Check disk space
ansible pxe_server -m command -a "df -h"

# Check service status
ansible pxe_server -m systemd -a "name=dnsmasq state=started" --check
```

### Common Issues

1. **SSH Key Not Accepted**:
   ```bash
   # Copy your SSH key first
   ssh-copy-id root@192.168.100.1
   ```

2. **Python Not Found**:
   Add to inventory:
   ```ini
   ansible_python_interpreter=/usr/bin/python3
   ```

3. **ISO Download Fails**:
   - Verify the remote server is accessible: `curl http://<remote_ip>:8080/<iso_filename>`
   - Check firewall rules on both ends
   - Increase timeout in playbook if needed

4. **NFS Export Issues**:
   - Check `/etc/exports` on the target
   - Verify with: `ansible pxe_server -m command -a "showmount -e localhost"`

## Idempotency

The playbook is designed to be idempotent - you can run it multiple times safely. It will:
- Skip already installed packages
- Create timestamped backups of existing configurations
- Only restart services when configurations change

## Re-running After Failure

If the playbook fails partway through, simply fix the issue and re-run. Ansible will:
- Skip completed tasks
- Pick up where it left off
- Complete any remaining steps

## Customization

To customize the playbook for your environment:

1. **Change network ranges**: Edit `playbook.yml` and modify `pxe_network` variable
2. **Change paths**: Modify `tftp_root` and `nfs_root` variables
3. **Add custom tasks**: Insert tasks in the appropriate play sections
4. **Adjust handlers**: Modify handlers if you need different service restart behavior

## Examples

### Example 1: Local Network Setup
```bash
ansible-playbook playbook.yml \
  -e "remote_server_ip=192.168.1.50" \
  -e "freebsd_iso_filename=FreeBSD-15.0-RELEASE-amd64-dvd1.iso.xz"
```

### Example 2: Remote Host
```bash
ansible-playbook playbook.yml \
  -i "pxe-server.example.com," \
  -e "remote_server_ip=fileserver.example.com" \
  -e "freebsd_iso_filename=FreeBSD-15.0-RELEASE-amd64-dvd1.iso.xz" \
  -u admin \
  --ask-become-pass
```

### Example 3: Multiple Hosts
Edit `inventory.ini`:
```ini
[pxe_server]
pxe-1.example.com
pxe-2.example.com

[pxe_server:vars]
remote_server_ip=fileserver.example.com
freebsd_iso_filename=FreeBSD-15.0-RELEASE-amd64-dvd1.iso.xz
```

Run:
```bash
ansible-playbook playbook.yml
```
