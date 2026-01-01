# Apple Silicon (Asahi Linux) Support

This guide covers running Keystone on Apple Silicon Macs using [Asahi Linux](https://asahilinux.org/).

## Overview

Keystone supports Apple Silicon Macs (M1, M2, M3 series) through the [nixos-apple-silicon](https://github.com/tpwrules/nixos-apple-silicon) project. The desktop module works on aarch64-linux with some platform-specific considerations.

## Prerequisites

1. **Asahi Linux installed** - Follow the [Asahi Linux installation guide](https://asahilinux.org/fedora/)
2. **NixOS installed** - Use the [nixos-apple-silicon UEFI standalone guide](https://github.com/tpwrules/nixos-apple-silicon/blob/main/docs/uefi-standalone.md)

## Flake Configuration

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    keystone.url = "github:ncrmro/keystone";
    home-manager.url = "github:nix-community/home-manager";
    # Required for keystone desktop
    hyprland.url = "github:hyprwm/Hyprland";
    elephant.url = "github:abenz1267/elephant";
    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };
  };

  outputs = { nixpkgs, nixos-apple-silicon, keystone, home-manager, ... }@inputs: {
    nixosConfigurations.my-mac = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-apple-silicon.nixosModules.default
        home-manager.nixosModules.home-manager
        keystone.nixosModules.desktop
        ./configuration.nix
        {
          hardware.asahi = {
            enable = true;
            peripheralFirmwareDirectory = /boot/asahi;  # See note below
            setupAsahiSound = true;
          };

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.sharedModules = [ keystone.homeModules.desktop ];
        }
      ];
    };
  };
}
```

## The `--impure` Flag Requirement

### Why It's Needed

The `peripheralFirmwareDirectory = /boot/asahi` setting uses an **absolute path**, which breaks Nix's pure evaluation model. This firmware directory contains:

- WiFi/Bluetooth firmware
- Speaker DSP firmware
- Other hardware-specific blobs

These files are extracted during Asahi Linux installation and are **unique to your specific Mac**.

### Building the Configuration

```bash
# Build only (recommended first)
nixos-rebuild build --flake .#my-mac --impure

# Apply the configuration
nixos-rebuild switch --flake .#my-mac --impure
```

### Memory-Constrained Builds

Apple Silicon Macs with limited RAM (8GB) may experience OOM kills during large builds. Use these flags:

```bash
NIX_BUILD_CORES=2 nixos-rebuild build --flake .#my-mac --impure --max-jobs 1
```

This serializes builds (`--max-jobs 1`) and limits parallelism within each build (`NIX_BUILD_CORES=2`).

## Alternative: Pure Flake Evaluation

If you want to eliminate the `--impure` flag (e.g., for remote builds), copy the firmware into your config:

```bash
# Copy firmware to your nixos config directory
mkdir -p /etc/nixos/firmware
cp /boot/asahi/{all_firmware.tar.gz,kernelcache*} /etc/nixos/firmware/
```

Then update your configuration:

```nix
hardware.asahi = {
  enable = true;
  peripheralFirmwareDirectory = ./firmware;  # Relative path = pure!
  setupAsahiSound = true;
};
```

**Trade-offs:**
- **Pro:** No `--impure` flag needed, can build remotely
- **Con:** ~50-100MB firmware files in your config, manual updates required

## Platform-Specific Packages

Some packages in the Keystone desktop module are x86_64-only and automatically excluded on aarch64:

- `gpu-screen-recorder` - Not available on ARM64 (uses NVIDIA/AMD-specific APIs)

The screen recording script (`keystone-screenrecord`) is conditionally included only on x86_64 systems.

## Troubleshooting

### Build Killed by OOM

If you see `SIGKILL` (exit code 247) during builds:

```bash
# Check system logs
journalctl -k | grep -i "out of memory"

# Rebuild with memory-safe settings
NIX_BUILD_CORES=2 nixos-rebuild build --flake .#my-mac --impure --max-jobs 1
```

### SSH Connection Drops During Long Builds

Apple Silicon laptops may sleep during builds. Use keepalive settings:

```bash
ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10 user@mac-ip
```

Or run the build with `nohup` or in a `tmux`/`screen` session.

### Audio Not Working

Ensure `setupAsahiSound = true` is set. The Asahi sound system requires specific speaker safety DSP configuration.

## References

- [nixos-apple-silicon documentation](https://github.com/tpwrules/nixos-apple-silicon)
- [Asahi Linux wiki](https://github.com/AsahiLinux/docs/wiki)
- [NixOS on Apple Silicon blog post](https://yusef.napora.org/blog/nixos-asahi/)
