# macOS Remote Builder for Asahi Linux

Build and deploy NixOS configurations to your MacBook Air (Asahi Linux) using a Mac Pro with OrbStack as the native ARM Linux builder.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Linux Workstation (runs nixos-rebuild)                                      │
│                                                                             │
│  ./scripts/deploy.sh                                                        │
│       │                                                                     │
│       │ NIX_SSHOPTS="-F ./ssh/config"                                       │
│       │ nixos-rebuild --builders "ssh://nixbuilder" --target-host macbook   │
│       │                                                                     │
│       ├─────── ProxyJump (via ssh/config) ───────┐                          │
│       │                                          │                          │
│       │                                          ▼                          │
│       │    ┌─────────────────────────────────────────────────────────────┐  │
│       │    │ Mac Pro (nicholas@unsup-16-pro.local)                       │  │
│       │    │                                                             │  │
│       │    │  ┌─────────────────────────────────────────────────────┐   │  │
│       │    │  │ OrbStack VM (nixbuilder) - aarch64-linux            │   │  │
│       │    │  │                                                     │   │  │
│       │    │  │  • Native ARM compilation (no emulation!)           │   │  │
│       │    │  │  • NixOS with flakes enabled                        │   │  │
│       │    │  │  • Binary cache access                              │   │  │
│       │    │  └─────────────────────────────────────────────────────┘   │  │
│       │    └─────────────────────────────────────────────────────────────┘  │
│       │                                                                     │
│       └─────── Direct SSH ───────────┐                                      │
│                                      ▼                                      │
│       ┌─────────────────────────────────────────────────────────────────┐   │
│       │ MacBook Air (root@192.168.1.64) - Asahi Linux                   │   │
│       │                                                                 │   │
│       │  • Receives built system closure                                │   │
│       │  • Activates new NixOS configuration                            │   │
│       └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Feature: Self-Contained SSH Config

This template uses a **project-local SSH config** (`ssh/config`) instead of modifying `~/.ssh/config`. All scripts use `ssh -F ./ssh/config` to reference it.

**Benefits:**
- Zero global config changes
- Portable - config travels with the project
- Explicit - all settings visible in one place
- Avoids known issues with `NIX_SSHOPTS` + inline `-J` options

## Prerequisites

- **Linux workstation** with Nix installed
- **Mac Pro** (Apple Silicon) with OrbStack and nixbuilder VM configured
- **MacBook Air** running NixOS/Asahi Linux
- SSH key access to all machines

## Quick Start

```bash
# 1. Edit ssh/config if needed (update hostnames/IPs)
vim ssh/config

# 2. Copy your SSH key to machines (uses project config)
ssh-copy-id -F ssh/config nixbuilder
ssh-copy-id -F ssh/config macbook

# 3. Test connectivity
./scripts/test-builder.sh

# 4. Copy hardware config from your MacBook
ssh -F ssh/config macbook cat /etc/nixos/hardware-configuration.nix > hardware-configuration.nix

# 5. Edit configuration.nix (search for TODO:)
vim configuration.nix

# 6. Deploy!
./scripts/deploy.sh
```

## Daily Workflow

```bash
# Edit your config
vim configuration.nix

# Deploy to MacBook
./scripts/deploy.sh

# Or specify a different flake target
./scripts/deploy.sh .#my-custom-config

# SSH to machines using project config
ssh -F ssh/config nixbuilder
ssh -F ssh/config macbook
```

## How It Works

The deploy script uses standard `nixos-rebuild` with these key components:

1. **`NIX_SSHOPTS="-F ./ssh/config"`** - Tells Nix to use our project-local SSH config
2. **`--builders "ssh://nixbuilder aarch64-linux"`** - Offloads ARM builds to the OrbStack VM
3. **`--target-host macbook`** - Deploys the result to the MacBook (using alias from ssh/config)

The `ssh/config` file contains `ProxyJump` configuration that transparently tunnels through the Mac Pro to reach the builder VM, since `.orb.local` domains only resolve on the Mac Pro itself.

## Asahi Firmware Handling

The `hardware.asahi.peripheralFirmwareDirectory` option references Apple peripheral firmware extracted during Asahi Linux installation. This presents challenges for Nix flakes and remote builds.

See: [nixos-apple-silicon issue #172](https://github.com/nix-community/nixos-apple-silicon/issues/172)

### Option 1: Disable Firmware Extraction (Simplest)

If firmware is already installed on your MacBook, you can skip extraction:

```nix
hardware.asahi = {
  enable = true;
  extractPeripheralFirmware = false;  # Skip extraction, use existing firmware
  setupAsahiSound = true;
};
```

This is the **recommended approach for remote builds** - it avoids both the `--impure` flag and firmware copying.

### Option 2: Use `--impure` Flag

If you need firmware extraction and the firmware exists at `/boot/asahi` on the build machine:

```nix
hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
```

This requires `--impure` because Nix flakes forbid absolute paths. The build must run on a machine where `/boot/asahi` exists.

### Option 3: Copy Firmware to Repo

Copy firmware files into your config directory for pure, reproducible builds:

```bash
mkdir -p firmware
scp macbook:/boot/asahi/all_firmware.tar.gz firmware/
scp macbook:/boot/asahi/kernelcache* firmware/
```

Then reference with a relative path:
```nix
hardware.asahi.peripheralFirmwareDirectory = ./firmware;
```

**Note:** Apple firmware may have licensing restrictions on redistribution. This approach is best for private repositories.

### Choosing an Approach

| Approach | Remote Build | Pure Evaluation | Reproducible |
|----------|--------------|-----------------|--------------|
| Disable extraction | ✅ Yes | ✅ Yes | ✅ Yes |
| `--impure` | ❌ No* | ❌ No | ❌ No |
| Copy to repo | ✅ Yes | ✅ Yes | ✅ Yes |

*Remote builds with `--impure` require the firmware path to exist on the machine running `nix build`.

## Files

| File | Purpose |
|------|---------|
| `flake.nix` | NixOS configuration for MacBook |
| `configuration.nix` | System settings (edit this!) |
| `hardware-configuration.nix` | Hardware-specific (copy from MacBook) |
| `scripts/deploy.sh` | Build and deploy to MacBook |
| `scripts/test-builder.sh` | Verify builder connectivity |
| `ssh/config` | Project-local SSH config with ProxyJump |

## Troubleshooting

### Cannot SSH to nixbuilder

Test step by step using the project config:
```bash
# 1. Can you reach Mac Pro directly?
ssh nicholas@unsup-16-pro.local echo OK

# 2. Can you reach builder via Mac Pro (manual)?
ssh -J nicholas@unsup-16-pro.local root@nixbuilder.orb.local echo OK

# 3. Does the project SSH config work?
ssh -F ssh/config nixbuilder echo OK
```

### OrbStack VM not running

```bash
ssh nicholas@unsup-16-pro.local 'export PATH="$HOME/.orbstack/bin:$PATH"; orb start nixbuilder'
```

### Slow builds (kernel compiling)

If you see the Asahi kernel compiling, check your flake.nix. **Do NOT** use `inputs.nixpkgs.follows` for keystone or nixos-apple-silicon - this breaks binary cache compatibility.

## Why This Architecture?

### Why OrbStack?

OrbStack runs Linux VMs with near-native performance on Apple Silicon:
- **No emulation**: ARM64 Linux runs natively
- **Fast I/O**: Optimized filesystem sharing
- **Low overhead**: Lightweight compared to Docker Desktop or UTM
- **Easy networking**: Automatic `.orb.local` DNS resolution

### Why ProxyJump?

The `.orb.local` domain only resolves on the Mac Pro. ProxyJump lets your Linux workstation reach the VM transparently through the Mac Pro, making it work like any other SSH host for Nix remote builds.

### Why Project-Local SSH Config?

Using `ssh -F ./ssh/config` instead of modifying `~/.ssh/config`:
- Avoids polluting global SSH config
- Known issues with `NIX_SSHOPTS` + inline `-J` (ProxyJump) options
- Config travels with the project
- Easier to maintain and debug
