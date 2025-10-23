# Quickstart: SSH-Enabled ISO VM Testing

## Prerequisites

- Nix installed
- quickemu installed (`nix-env -iA nixpkgs.quickemu`)
- SSH key pair (`ssh-keygen -t ed25519` if needed)

## Quick Test

```bash
# Complete test in one command
make vm-test

# SSH into the VM
ssh -p 22220 root@localhost

# Stop when done
make vm-stop
```

## Step-by-Step

### 1. Build ISO with your SSH key

```bash
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

Output:
```
✅ ISO built successfully!
📁 Location: vms/keystone-installer.iso
```

### 2. Start the VM

```bash
make vm-server
```

The VM window will appear. Wait for the boot to complete (~30 seconds).

### 3. Connect via SSH

```bash
ssh -p 22220 root@localhost
```

You're now in the Keystone installer environment!

### 4. Clean Up

```bash
# Stop the VM
make vm-stop

# Remove VM artifacts
make vm-clean
```

## Common Tasks

### Test with different SSH key

```bash
./bin/build-iso --ssh-key /path/to/other/key.pub
make vm-server
```

### Check if VM is running

```bash
ps aux | grep qemu | grep server.conf
```

### View VM console output

```bash
tail -f vms/server/server.log
```

## Troubleshooting

### "Connection refused" when SSHing

- Wait 30 seconds after VM start for SSH to be ready
- Check VM is running: `ps aux | grep qemu`
- Verify port 22220 is forwarded: `cat vms/server/server.ports`

### "quickemu not found"

Install quickemu:
```bash
nix-env -iA nixpkgs.quickemu
```

### Port 22220 already in use

Stop any existing VM:
```bash
make vm-stop
```

Or check what's using the port:
```bash
lsof -i :22220
```

### SSH key not working

Ensure you're using the public key when building the ISO:
```bash
# Correct (public key)
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Wrong (private key)
./bin/build-iso --ssh-key ~/.ssh/id_ed25519  # Don't do this!
```

## Tips

- The VM uses 4GB RAM and 2 CPU cores by default (configured in `vms/server.conf`)
- The VM disk is created at `vms/server/disk.qcow2` (20GB max)
- SSH is available on localhost port 22220
- The root user has no password (SSH key only)

## Next Steps

After testing the installer ISO, you can:

1. Deploy to real hardware using nixos-anywhere
2. Customize the installer modules in `modules/iso-installer.nix`
3. Test different configurations by modifying `vms/server.conf`