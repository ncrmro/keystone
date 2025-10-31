# Initrd SSH Unlock Module

Enable SSH access during boot to remotely unlock encrypted disks. This module is particularly useful for:
- Virtual machines (VMs) without TPM2 support
- Remote servers without local console access
- Headless systems requiring encrypted storage
- Development and testing environments

## Features

- **Network-based unlocking**: Uses SSH to securely unlock LUKS-encrypted volumes during boot
- **Flexible networking**: Supports both DHCP (default) and static IP configuration
- **Hardware compatibility**: Configurable network driver module for different hardware
- **Security**: Key-based authentication only (no password auth)
- **Parallel with TPM2**: Can be used alongside TPM2 automatic unlocking as a fallback

## Quick Start

### 1. Generate SSH Host Key

The initrd SSH daemon needs its own host key:

```bash
sudo ssh-keygen -t ed25519 -N "" -f /etc/ssh/initrd_ssh_host_ed25519_key
```

### 2. Configure Your System

Add to your `configuration.nix`:

```nix
{
  keystone.initrdSshUnlock = {
    enable = true;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3Nza... your-key-here user@host"
    ];
    # For VMs:
    networkModule = "virtio_net";
    # For physical hardware, find your module with:
    # lspci -v | grep -iA8 'network\|ethernet'
  };
}
```

### 3. Rebuild and Reboot

```bash
sudo nixos-rebuild boot
sudo reboot
```

### 4. Unlock During Boot

When the system boots, SSH to it and enter the LUKS password:

```bash
ssh root@your-server-ip
# You'll be prompted for the LUKS password
# After unlocking, the connection will close and boot continues
```

## Configuration Options

### Basic Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable SSH unlock in initrd |
| `authorizedKeys` | list | `[]` | SSH public keys for authentication |
| `hostKey` | path | `/etc/ssh/initrd_ssh_host_ed25519_key` | Path to SSH host key |
| `port` | port | `22` | SSH port to listen on |

### Network Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `networkModule` | string | `"virtio_net"` | Kernel module for network card |
| `dhcp` | bool | `true` | Use DHCP for IP configuration |
| `kernelParams` | list | `[]` | Additional kernel network parameters |

## Examples

### Example 1: VM with Default Settings

```nix
{
  keystone.initrdSshUnlock = {
    enable = true;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVc... user@laptop"
    ];
  };
}
```

### Example 2: Physical Server with Realtek NIC

First, find your network module:
```bash
lspci -v | grep -iA8 'network\|ethernet'
```

Then configure:
```nix
{
  keystone.initrdSshUnlock = {
    enable = true;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVc... admin@desktop"
    ];
    networkModule = "r8169";  # Realtek RTL8111/8168/8411
  };
}
```

### Example 3: Static IP Configuration

```nix
{
  keystone.initrdSshUnlock = {
    enable = true;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVc... user@host"
    ];
    networkModule = "e1000e";  # Intel Gigabit
    dhcp = false;
    kernelParams = [
      # Format: ip=<client-ip>::<gateway-ip>:<netmask>:<hostname>::none
      "ip=10.0.0.50::10.0.0.1:255.255.255.0:myserver::none"
    ];
  };
}
```

### Example 4: Custom SSH Port

```nix
{
  keystone.initrdSshUnlock = {
    enable = true;
    port = 2222;  # Use non-standard port
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVc... user@host"
    ];
  };
}
```

## Common Network Modules

| Hardware | Module | Notes |
|----------|--------|-------|
| QEMU/KVM VMs | `virtio_net` | Default for virtual machines |
| Intel Gigabit | `e1000e` | Most Intel wired adapters |
| Realtek RTL8111/8168 | `r8169` | Common on consumer motherboards |
| Broadcom | `tg3` or `bnx2` | Server NICs |

To find your module:
```bash
lspci -v | grep -iA8 'network\|ethernet'
# Look for "Kernel driver in use:" or "Kernel modules:"
```

## Troubleshooting

### SSH Not Available During Boot

**Check network module is loaded:**
```bash
# After boot fails, check dmesg or journal
journalctl -b | grep -i network
```

**Verify DHCP is working:**
```bash
# In emergency shell during boot
ip addr show
# Should show an IP address
```

**Try serial console:**
```bash
# Connect via serial console to see initrd logs
virsh console vm-name  # For VMs
```

### Wrong Network Module

If the network doesn't come up, you may have the wrong module. Find the correct one:

```bash
# List all loaded network modules on a working system
lsmod | grep -i net

# Check specific hardware
lspci -k | grep -A 3 -i network
```

### Host Key Verification Failed

First time connecting, you'll see a host key warning. This is normal because the initrd SSH daemon uses a different host key than the running system.

To avoid the warning:
```bash
# Remove the old key from known_hosts
ssh-keygen -R your-server-ip

# Or use -o StrictHostKeyChecking=no (less secure)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@your-server-ip
```

### System Hangs at Boot

If DHCP is enabled but the network is unreachable, the boot process may hang waiting for network configuration. Solutions:

1. **Use static IP** instead of DHCP
2. **Reduce timeout** via kernel parameter:
   ```nix
   kernelParams = [ "ip=dhcp:dhcp_timeout=30" ];
   ```
3. **Ensure network cable is connected** before boot

## Security Considerations

- **Host Key**: The initrd SSH host key is different from your system's SSH host key. This is intentional.
- **Key-based auth only**: Password authentication is disabled for security.
- **Limited environment**: The initrd SSH session has minimal tools (no shell) and closes after password entry.
- **Network exposure**: During boot, your system is accessible via SSH. Use firewall rules or network segmentation if this is a concern.

## Integration with Other Modules

### With Disko Module

This module works seamlessly with the `diskoSingleDiskRoot` module:

```nix
{
  imports = [
    keystone.nixosModules.diskoSingleDiskRoot
    keystone.nixosModules.initrdSshUnlock
  ];

  keystone.disko = {
    enable = true;
    device = "/dev/sda";
  };

  keystone.initrdSshUnlock = {
    enable = true;
    authorizedKeys = [ "..." ];
  };
}
```

### With TPM2

You can enable both SSH unlock and TPM2 automatic unlock. The system will:
1. Try TPM2 unlock first (if hardware present)
2. Fall back to password prompt if TPM2 fails
3. Allow SSH access for remote password entry

## Technical Details

This module configures:
- `boot.initrd.network.enable = true` - Enables networking in initrd
- `boot.initrd.network.ssh` - Configures SSH daemon
- `boot.initrd.availableKernelModules` - Loads network driver
- `boot.kernelParams` - Adds `ip=dhcp` or custom network config

The SSH daemon runs during the initrd phase, before the actual system boots. After successfully entering the LUKS password, the credstore is unlocked, ZFS encryption keys are loaded, and the system continues booting normally.

## References

- [NixOS Wiki: Remote Disk Unlocking](https://nixos.wiki/wiki/Remote_disk_unlocking)
- [Kernel IP Configuration](https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt)
- [systemd-cryptsetup](https://www.freedesktop.org/software/systemd/man/systemd-cryptsetup@.service.html)
