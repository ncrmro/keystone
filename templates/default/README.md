# Keystone Infrastructure Configuration

Your Keystone infrastructure project has been initialized!

## Quick Start

### 1. Configure Your System

Edit `configuration.nix` and search for `TODO:` to find all required changes:

```bash
grep -n "TODO:" configuration.nix
```

**Required changes:**
- `networking.hostName` - Your machine's hostname
- `networking.hostId` - Unique ID for ZFS (generate below)
- `storage.devices` - Your disk ID (find below)
- `users.admin.fullName` - Your name
- `users.admin.email` - Your email
- `users.admin.authorizedKeys` - Your SSH public key(s)

### 2. Generate Host ID

Required for ZFS - run this command and paste the result:

```bash
head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
```

### 3. Find Your Disk ID

Use stable disk identifiers for reliable boot:

```bash
ls -la /dev/disk/by-id/
```

Look for entries like `nvme-Samsung_SSD_980_PRO_2TB_...` or `ata-WDC_WD10EZEX_...`

### 4. Choose Your Configuration

In `flake.nix`, the `operating-system` module is already imported. For desktops:

- Uncomment `keystone.nixosModules.desktop` for Hyprland desktop environment
- Set `desktop.enable = true` in your user configuration

### 5. Deploy

#### Option A: Fresh Installation (nixos-anywhere)

1. Boot target machine from Keystone installer ISO
2. Get the IP address: `ip addr show`
3. Deploy from your development machine:

```bash
nixos-anywhere --flake .#my-machine root@<installer-ip>
```

#### Option B: Existing NixOS System

```bash
sudo nixos-rebuild switch --flake .#my-machine
```

## Post-Deployment

### Secure Boot Key Enrollment

If Secure Boot is enabled, enroll your keys after first boot:

```bash
sudo sbctl create-keys
sudo sbctl enroll-keys --microsoft
sudo nixos-rebuild switch --flake .#my-machine
```

### TPM Enrollment

If TPM is enabled, enroll after Secure Boot keys are set:

```bash
# Check current enrollment
systemd-cryptenroll --tpm2-device=auto /dev/<your-luks-device>
```

## File Structure

```
.
├── flake.nix           # Inputs and machine definitions
├── configuration.nix   # System configuration
├── hardware.nix        # Hardware-specific settings
└── README.md           # This file
```

## Adding More Machines

1. Duplicate the machine block in `flake.nix`
2. Create machine-specific configuration files:

```
machines/
├── server/
│   ├── configuration.nix
│   └── hardware.nix
└── laptop/
    ├── configuration.nix
    └── hardware.nix
```

## Common Tasks

### Update System

```bash
nix flake update
sudo nixos-rebuild switch --flake .#my-machine
```

### View Configuration Options

```bash
# All Keystone options
nix repl --expr 'builtins.getFlake (toString ./.)'
# Then: :p nixosConfigurations.my-machine.options.keystone

# Or search nixos.wiki or the Keystone repository
```

### Generate Hardware Configuration

On the target machine:

```bash
nixos-generate-config --show-hardware-config > hardware.nix
```

## Troubleshooting

### "hostId is required for ZFS"

Generate and set `networking.hostId` in `configuration.nix`:
```bash
head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
```

### "Disk not found during boot"

Ensure you're using `/dev/disk/by-id/` paths, not `/dev/sda` or `/dev/nvme0n1`.

### "Secure Boot verification failed"

Run Secure Boot key enrollment (see Post-Deployment section).

### "TPM enrollment failed"

- Ensure Secure Boot keys are enrolled first
- Check TPM is enabled in BIOS/UEFI
- Verify TPM 2.0 compatibility: `ls /dev/tpm*`

## Resources

- [Keystone Documentation](https://github.com/ncrmro/keystone)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Disko Documentation](https://github.com/nix-community/disko)
- [Lanzaboote Guide](https://github.com/nix-community/lanzaboote)
