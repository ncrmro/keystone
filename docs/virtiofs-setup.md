# Virtiofs Setup for Libvirt VMs

This guide explains how to set up virtiofs filesystem sharing between a NixOS host and libvirt guest VMs, enabling the MicroVM-like architecture where the host builds and the guest runs instantly.

## Overview

Virtiofs allows sharing the host's `/nix/store` with guest VMs for improved performance:

- **Host builds** → Store paths added to `/nix/store`
- **Guest mounts** → Instantly sees new paths via virtiofs
- **OverlayFS** → Provides writable layer for temporary files

This replicates the MicroVM architecture described in the problem statement, providing fast iteration without copying store paths.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Host NixOS                                                   │
│                                                              │
│  /nix/store (read-only)                                     │
│      │                                                       │
│      │ virtiofsd                                            │
│      └────────────────────────────┐                         │
│                                   │                         │
└───────────────────────────────────┼─────────────────────────┘
                                    │
                                    │ virtiofs protocol
                                    │
┌───────────────────────────────────┼─────────────────────────┐
│ Guest NixOS                       │                         │
│                                   ▼                         │
│  /sysroot/nix/.ro-store ◄─────virtiofs (read-only)        │
│  /sysroot/nix/.rw-store ◄─────tmpfs (writable)            │
│         │                  │                                │
│         └──────┬───────────┘                                │
│                ▼                                             │
│          OverlayFS                                          │
│                │                                             │
│                ▼                                             │
│          /nix/store (appears writable)                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Setup Steps

### 1. Host Configuration

Add the virtiofs host module to your NixOS configuration:

```nix
# /etc/nixos/configuration.nix on the HOST
{
  imports = [
    ./path/to/keystone/modules/virtualization/host-virtiofs.nix
  ];

  keystone.virtualization.host.virtiofs.enable = true;
}
```

Rebuild and switch:

```bash
sudo nixos-rebuild switch
```

This configures:
- `virtualisation.libvirtd.enable = true`
- `virtualisation.libvirtd.qemu.vhostUserPackages = [ pkgs.virtiofsd ]`

### 2. Create VM with Virtiofs

Create a new VM with virtiofs enabled:

```bash
./bin/virtual-machine --name keystone-virtiofs-test --enable-virtiofs --start
```

This generates libvirt XML with:

**A. Shared Memory Configuration**
```xml
<memoryBacking>
  <access mode='shared'/>
  <source type='memfd'/>
</memoryBacking>
```

**B. Filesystem Device**
```xml
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs' queue='1024'/>
  <source dir='/nix/store'/>
  <target dir='nix-store-share'/>
</filesystem>
```

### 3. Guest Configuration

Configure the guest to use the virtiofs share:

```nix
# Guest VM's configuration.nix
{
  imports = [
    ./path/to/keystone/modules/virtualization/guest-virtiofs.nix
  ];

  keystone.virtualization.guest.virtiofs = {
    enable = true;
    shareName = "nix-store-share";  # Must match VM XML <target dir>
  };

  # Rest of your configuration...
}
```

The guest module configures:

1. **Kernel modules**: `virtiofs` and `overlay` available at boot
2. **Read-only mount**: `/sysroot/nix/.ro-store` ← virtiofs share
3. **Writable layer**: `/sysroot/nix/.rw-store` ← tmpfs
4. **OverlayFS**: `/nix/store` ← combined view

### 4. Deploy to VM

Use nixos-anywhere or manual installation:

```bash
nixos-anywhere --flake .#your-guest-config root@192.168.100.99
```

Or install manually via the installer ISO.

### 5. Verify Setup

Inside the guest VM:

```bash
# Check virtiofs mount
mount | grep virtiofs
# Should show: nix-store-share on /sysroot/nix/.ro-store type virtiofs

# Check overlay
mount | grep overlay
# Should show: overlay on /nix/store type overlay

# Test access
ls /nix/store
# Should see host's store contents

# Verify it's working
nix-store --verify --check-contents
```

## Configuration Options

### Guest Options

```nix
keystone.virtualization.guest.virtiofs = {
  enable = true;  # Enable virtiofs mounting

  shareName = "nix-store-share";  # Virtiofs share name (must match XML)
  
  mountPoint = "/nix/store";  # Where to mount the overlay
  
  roStoreMount = "/sysroot/nix/.ro-store";  # Read-only share mount
  
  rwStoreMount = "/sysroot/nix/.rw-store";  # Writable layer mount
  
  persistentRwStore = false;  # Use disk instead of tmpfs (default: false)
};
```

### Persistent Writable Layer

By default, the writable layer uses tmpfs (RAM disk). For persistent writes:

```nix
keystone.virtualization.guest.virtiofs = {
  enable = true;
  persistentRwStore = true;
};

# Pre-create the directory
fileSystems."/sysroot/nix/.rw-store" = {
  device = "/dev/vda3";  # Or wherever you want to store it
  fsType = "ext4";
  neededForBoot = true;
};
```

## Troubleshooting

### virtiofsd not found

**Error**: `virtiofs driver not found` or `qemu-system-x86_64: -device vhost-user-fs-pci: Failed to connect socket`

**Solution**: Ensure virtiofsd is in vhostUserPackages:

```bash
# On host
which virtiofsd
# Should return: /nix/store/...-virtiofsd-.../bin/virtiofsd

# Check libvirtd can find it
sudo systemctl restart libvirtd
```

### Guest can't mount virtiofs

**Error**: `mount: unknown filesystem type 'virtiofs'`

**Solution**: Ensure kernel module is loaded:

```bash
# In guest
lsmod | grep virtiofs
# If not loaded:
modprobe virtiofs
```

Check module is in initrd:

```nix
boot.initrd.availableKernelModules = [ "virtiofs" "overlay" ];
```

### OverlayFS mount fails

**Error**: `mount: /nix/store: wrong fs type, bad option, bad superblock`

**Solution**: Check dependencies are mounted first:

```bash
# In guest
mount | grep /sysroot/nix
# Should show both .ro-store and .rw-store

# If not, check neededForBoot = true
```

### Performance Issues

If virtiofs is slower than expected:

1. **Increase queue size** in libvirt XML:
   ```xml
   <driver type='virtiofs' queue='2048'/>
   ```

2. **Check memory backing** is configured:
   ```xml
   <memoryBacking>
     <access mode='shared'/>
   </memoryBacking>
   ```

3. **Monitor virtiofsd logs**:
   ```bash
   # On host
   journalctl -u libvirtd -f
   ```

## Direct Kernel Boot (Advanced)

For even faster iteration, skip UEFI boot and load the kernel directly:

### 1. Build Guest System

```bash
nix build .#nixosConfigurations.your-guest.config.system.build.kernel
nix build .#nixosConfigurations.your-guest.config.system.build.initialRamdisk
nix build .#nixosConfigurations.your-guest.config.system.build.toplevel
```

### 2. Update Libvirt XML

```bash
virsh shutdown keystone-virtiofs-test
virsh edit keystone-virtiofs-test
```

Replace `<os>` section:

```xml
<os>
  <type arch='x86_64' machine='q35'>hvm</type>
  <kernel>/path/to/result/kernel</kernel>
  <initrd>/path/to/result/initrd</initrd>
  <cmdline>init=/nix/store/.../init console=ttyS0</cmdline>
</os>
```

### 3. Symlink for Convenience

```bash
ln -sf result kernel-current
ln -sf result/initrd initrd-current

# Update XML to use stable paths
<kernel>/path/to/kernel-current</kernel>
<initrd>/path/to/initrd-current</initrd>
```

Now rebuilding updates the symlinks automatically.

## Comparison with Other Approaches

### vs nixos-rebuild build-vm

| Feature | virtiofs | build-vm |
|---------|----------|----------|
| Store sharing | Yes (host store) | Yes (9P) |
| Encryption testing | No | No |
| Secure boot testing | Yes | No |
| TPM testing | Yes | No |
| Persistent disk | Optional | Yes |
| Setup complexity | Higher | Lower |

### vs Full Deployment

| Feature | virtiofs | Full deployment |
|---------|----------|-----------------|
| Build speed | Fast (no copy) | Slow (copies store) |
| Encryption | No | Yes |
| Secure boot | Yes | Yes |
| Production-like | Partial | Yes |
| Use case | Development | Testing/Production |

## Best Practices

1. **Development workflow**: Use virtiofs for fast iteration on configs
2. **Security testing**: Disable virtiofs to test encryption/secure boot properly
3. **Production testing**: Always test final config without virtiofs
4. **Memory allocation**: Allocate extra RAM for tmpfs overlay if needed
5. **Monitoring**: Check `/sysroot/nix/.rw-store` size with `df -h`

## References

- [virtiofs documentation](https://virtio-fs.gitlab.io/)
- [OverlayFS kernel documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [libvirt filesystem sharing](https://libvirt.org/kbase/virtiofs.html)
- [NixOS MicroVM documentation](https://github.com/astro/microvm.nix)
