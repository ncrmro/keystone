# Keystone Apple Silicon Configuration

This is a standalone NixOS configuration for Apple Silicon Macs running Asahi Linux,
initialized from the Keystone `macos` template.

## Quick Start

1. **Update hardware configuration:**
   Edit `hardware-configuration.nix` to match your disk UUIDs:
   ```bash
   # Find your root filesystem UUID
   lsblk -o NAME,UUID,LABEL,FSTYPE

   # Find your boot partition PARTUUID
   blkid /dev/nvme0n1p* | grep -i boot
   ```

2. **Customize configuration:**
   Edit `configuration.nix`:
   - Change `networking.hostName` if desired
   - Update user settings (name, email, password)
   - Set your timezone

3. **Deploy:**
   ```bash
   # First time (from installer)
   sudo nixos-rebuild switch --flake .#keystone-mac

   # Subsequent updates
   nixos-rebuild switch --flake .#keystone-mac
   ```

## Architecture

This configuration uses Keystone as a flake input rather than containing the
entire Keystone repository. Benefits:

- **Isolation**: Machine-specific settings stay separate from framework code
- **Efficiency**: Smaller disk footprint, faster git operations
- **Binary Cache**: Uses pinned nixpkgs for Asahi kernel cache compatibility

## Important Notes

### Do NOT use `follows` for nixos-apple-silicon

The `flake.nix` intentionally does NOT use:
```nix
# BAD - causes kernel recompilation
keystone.inputs.nixpkgs.follows = "nixpkgs";
nixos-apple-silicon.inputs.nixpkgs.follows = "nixpkgs";
```

This is because:
1. The Asahi kernel must be compiled from source
2. Keystone and nixos-apple-silicon pin specific nixpkgs versions
3. Binary caches provide pre-built kernels for these pinned versions
4. Using `follows` breaks binary cache compatibility = multi-hour builds

### Updating

To update Keystone to the latest version:
```bash
nix flake update keystone
nixos-rebuild switch --flake .#keystone-mac
```

To update all inputs:
```bash
nix flake update
nixos-rebuild switch --flake .#keystone-mac
```

## Troubleshooting

### Boot Issues
- Ensure `boot.loader.efi.canTouchEfiVariables = false` (set in config)
- U-Boot cannot write EFI variables - this prevents bricking

### Network Issues
- NetworkManager with iwd backend is configured for WiFi
- Check `systemctl status NetworkManager` and `systemctl status iwd`

### Display Issues
- Hyprland scale is set to 2 for Retina displays
- Adjust `keystone.desktop.hyprland.scale` if needed
