# Virtiofs Quick Start Guide

Get up and running with virtiofs filesystem sharing in 5 minutes.

## What is Virtiofs?

Virtiofs lets you share your host's `/nix/store` with VM guests for faster development:
- **No copying** - Guest sees host's store instantly
- **Less disk space** - No duplication of store paths
- **Faster iteration** - Like MicroVM but with full libvirt features

## Prerequisites

- NixOS host with libvirtd
- Keystone repository cloned
- User in `libvirtd` group

## Step-by-Step Setup

### 1. Enable Host Support (One-time)

Add to `/etc/nixos/configuration.nix`:

```nix
{
  imports = [
    /path/to/keystone/modules/virtualization/host-virtiofs.nix
  ];

  keystone.virtualization.host.virtiofs.enable = true;
}
```

Rebuild:
```bash
sudo nixos-rebuild switch
```

### 2. Create VM with Virtiofs

```bash
cd /path/to/keystone

# Build installer ISO (if needed)
make build-iso-ssh

# Create VM with virtiofs enabled
./bin/virtual-machine --name my-dev-vm --enable-virtiofs --start

# Or use Makefile
make VM_NAME=my-dev-vm vm-create-virtiofs
```

### 3. Configure Guest

Create a guest configuration or modify existing one:

```nix
# configuration.nix
{
  imports = [
    /path/to/keystone/modules/virtualization/guest-virtiofs.nix
  ];

  # Enable virtiofs mounting
  keystone.virtualization.guest.virtiofs = {
    enable = true;
    shareName = "nix-store-share";
  };

  # ... rest of your config
}
```

### 4. Deploy to VM

```bash
nixos-anywhere --flake .#my-dev-vm root@192.168.100.99
```

### 5. Verify It's Working

Inside the guest VM:

```bash
# Check virtiofs mount
mount | grep virtiofs
# Output: nix-store-share on /sysroot/nix/.ro-store type virtiofs

# Check overlay
mount | grep overlay
# Output: overlay on /nix/store type overlay

# Check store access
ls /nix/store | wc -l
# Output: Should match host's store count

# Check overlay usage
df -h /sysroot/nix/.rw-store
# Output: Shows tmpfs usage
```

## Common Commands

```bash
# Create virtiofs VM
make vm-create-virtiofs

# Start VM
make vm-start

# SSH into VM
./bin/test-vm-ssh

# Connect to console
virsh console keystone-test-vm

# View graphical display
remote-viewer $(virsh domdisplay keystone-test-vm)

# Stop VM
make vm-stop

# Delete VM completely
make vm-reset
```

## Troubleshooting

### virtiofsd not found

**Problem**: VM fails to start with "virtiofsd not found"

**Solution**: Verify host config:
```bash
which virtiofsd
# Should return: /nix/store/...-virtiofsd-.../bin/virtiofsd

sudo systemctl restart libvirtd
```

### Guest can't mount virtiofs

**Problem**: `mount: unknown filesystem type 'virtiofs'`

**Solution**: Check kernel module:
```bash
# In guest
modprobe virtiofs
lsmod | grep virtiofs

# Ensure in config:
boot.initrd.availableKernelModules = [ "virtiofs" "overlay" ];
```

### OverlayFS not working

**Problem**: Can't write to `/nix/store`

**Solution**: Check dependencies:
```bash
# In guest
mount | grep /sysroot/nix
# Should show both .ro-store and .rw-store

# Check module options
ls -la /sysroot/nix/.rw-store
# Should exist and be writable
```

## Performance Tips

1. **Allocate enough RAM** - Tmpfs overlay uses RAM
   ```bash
   ./bin/virtual-machine --memory 8192 --enable-virtiofs --start
   ```

2. **Monitor overlay size** - Check periodically
   ```bash
   df -h /sysroot/nix/.rw-store
   ```

3. **Use persistent overlay** - For long-running VMs
   ```nix
   keystone.virtualization.guest.virtiofs = {
     enable = true;
     persistentRwStore = true;
   };
   ```

## When to Use Virtiofs

**✅ Good for:**
- Development and testing
- Iterating on configurations
- Reducing VM disk usage
- Fast rebuilds

**❌ Not for:**
- Production deployments
- Testing encryption fully
- Systems requiring isolated stores
- VMs on different hosts

## Next Steps

- Read full guide: `docs/virtiofs-setup.md`
- See examples: `examples/virtiofs-*.nix`
- Review implementation: `docs/VIRTIOFS_IMPLEMENTATION_SUMMARY.md`

## Getting Help

- Check virtiofs logs: `journalctl -u libvirtd | grep virtio`
- Review VM XML: `virsh dumpxml my-dev-vm`
- Test basic virtiofs: `mount | grep virtiofs` in guest

## Complete Example

See `examples/virtiofs-guest-config.nix` for a full working configuration with:
- Verification service
- MOTD with status
- Proper module imports
- Commented options

---

**That's it!** You now have virtiofs filesystem sharing set up for faster VM development.
