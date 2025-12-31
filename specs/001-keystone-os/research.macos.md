# macOS (Apple Silicon) Installer ISO - Research & Troubleshooting Notes

This document captures research, design decisions, and troubleshooting steps related to building a functional installer ISO for macOS (Apple Silicon) devices.

---

## 1. Initial Build & TUI Integration Challenges

**Problem:** The initial design of the installer ISO aimed to include a Terminal User Interface (TUI) installer for interactive setup. However, this led to several issues after booting:
    *   `Failed to stat User Login Management` (related to `systemd-logind`).
    *   No interactive `bash` shell available upon exiting the TUI, despite `bashInteractive` being specified.
    *   General instability and unexpected behavior related to TTY control.

**Root Cause Analysis:**
The primary cause was identified as a conflict in systemd service enablement for `tty1` (where the TUI installer was configured to run).
1.  `modules/iso-installer.nix` and `modules/iso-installer-apple-silicon.nix` were defining `environment.systemPackages` with `lib.mkForce`, inadvertently removing essential system packages (like `coreutils`, `findutils`, default `bash`) that are typically inherited from `nixos/modules/installer/cd-dvd/installation-cd-minimal.nix`. This resulted in a very minimal (and broken) system environment.
2.  The `keystone-installer.service` (TUI) was configured to run on `tty1` and conflict with `getty@tty1.service` and `autovt@tty1.service`.
3.  `modules/iso-base.nix` (a refactored common module) was initially configured to unconditionally enable `getty@tty1.service` and `autovt@tty1.service`. This created a race condition or direct conflict with the TUI installer, preventing `systemd-logind` from establishing a proper user session.

**Solution/Fixes Implemented:**

1.  **Module Refactoring**:
    *   Created `modules/iso-base.nix` to hold common ISO configurations (SSH, root user, essential packages, network basics).
    *   Modified `modules/iso-installer.nix` (for x86_64) to import `iso-base.nix` and add only ZFS/x86-specific configurations.
    *   Modified `modules/iso-installer-apple-silicon.nix` to import `iso-base.nix` and add only Apple Silicon-specific configurations.
    *   **Crucially**: Removed `lib.mkForce` from `environment.systemPackages` in `modules/iso-installer-apple-silicon.nix` and ensured all required essential packages are inherited from `iso-base.nix` (which in turn builds upon `installation-cd-minimal.nix` defaults). This resolved missing basic shell commands like `bash` and `coreutils`.

2.  **TTY Management**:
    *   In `modules/iso-base.nix`, the enablement of `getty@tty1.service` and `autovt@tty1.service` was made conditional on `!enableTui`. This ensures that `getty` services are only active when the TUI installer is disabled, preventing conflicts.
    *   Added an `ExecStopPost` command to `keystone-installer.service` (in `iso-base.nix`) to explicitly start `getty@tty1.service` when the TUI installer exits cleanly. This ensures the user drops to a functional login shell after exiting the TUI.

3.  **TUI "Exit to Shell" Feature**: Added a "Exit to Shell" option directly into the `keystone-installer-ui` application, which gracefully exits the TUI and triggers the `ExecStopPost` action in systemd.

---

## 2. Transition to "Vanilla" macOS Installer ISO

**Decision**: Due to the complexities and debugging efforts required to integrate the TUI installer and provide a robust shell environment simultaneously, the user requested to make the macOS installer ISO as "vanilla" (minimal) as possible. The primary goal is to have an image that:
    *   Boots on Apple Silicon.
    *   Includes SSH access with pre-configured keys.
    *   Provides basic network functionality.
    *   Does *not* include the TUI installer or excessive extra modules.

**Implementation**:
    *   `modules/iso-installer-apple-silicon.nix` was extensively rewritten.
    *   It now directly imports `nixos/modules/installer/cd-dvd/installation-cd-minimal.nix` (implicitly via the flake) and applies only the necessary Apple Silicon-specific overrides.
    *   All TUI-related configurations were removed.
    *   SSH service and authorized keys for root are explicitly enabled.
    *   Basic networking (`iwd` and later `NetworkManager`) and essential command-line tools (`git`, `vim`, `parted`, `nixos-install-tools`, `usbutils`, `pciutils`, `ethtool`, `dhclient`, `dhcpcd`) are included.

---

## 3. Networking Notes After Booting into the Installer (Vanilla macOS ISO)

After booting into the newly vanilla macOS installer ISO, network connectivity can still be a challenge due to the minimal nature of the image and the behavior of USB Ethernet adapters.

**Observed Issues:**
*   USB Ethernet adapters may be detected by the kernel (`lsusb`, `dmesg`), but fail to obtain an IP address automatically.
*   Upon hot-plugging/re-plugging, the device might not re-appear or acquire an IP.
*   Essential DHCP client tools like `dhclient` or `dhcpcd` may not be installed by default in a very minimal configuration.

**ISO Configuration for Robust Networking (Next Builds):**
To ensure reliable networking for subsequent builds of the vanilla macOS installer ISO, the `modules/iso-installer-apple-silicon.nix` has been updated with the following:
*   **Enabled `NetworkManager`**:
    ```nix
    networking.networkmanager.enable = true;
    networking.networkmanager.wifi.backend = "iwd";
    ```
    This ensures `NetworkManager` is running, which is excellent for handling hot-plugged USB Ethernet devices and automatically obtaining IP addresses via DHCP.
*   **Explicitly Added Network Tools**:
    ```nix
    environment.systemPackages = with pkgs; [
      # ... other tools ...
      networkmanager
      dhclient
      dhcpcd
      usbutils
      pciutils
      ethtool
    ];
    ```
    This guarantees that `NetworkManager` (the package), `dhclient`, and `dhcpcd` (for manual DHCP if needed) are present in the ISO environment, along with diagnostic tools.

**Troubleshooting Steps for Current Booted Session (If NetworkManager/DHCP clients are missing):**

If your currently booted ISO lacks `NetworkManager`, `dhclient`, or `dhcpcd`, you will need to manually configure the network using `ip` commands. This requires knowing your network's IP address range, subnet mask, gateway, and DNS servers.

1.  **Identify your network interface name:**
    ```bash
    ip link show
    ```
    (Look for names like `eth0`, `enp...`, or `usb...`. Let's assume it's `<interface_name>` for the following steps.)

2.  **Verify USB Ethernet device detection:**
    ```bash
    lsusb
    dmesg | tail -n 20 # Check kernel messages for device detection
    ```

3.  **Bring the network interface up:**
    ```bash
    sudo ip link set <interface_name> up
    ```

4.  **Assign a static IP address and subnet mask:**
    ```bash
    sudo ip addr add 192.168.1.100/24 dev <interface_name>
    ```
    (Replace `192.168.1.100` with an available IP on your network, and `/24` with your subnet mask.)

5.  **Add a default route (gateway):**
    ```bash
    sudo ip route add default via 192.168.1.1
    ```
    (Replace `192.168.1.1` with your network's gateway IP.)

6.  **Configure DNS servers:**
    ```bash
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
    # (Optional: Add more nameservers)
    # echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
    ```

After these steps, you should have network connectivity. You can verify with `ping google.com`.

---

## 4. NixOS Installation on Apple Silicon (Post-Asahi)

This section documents how to install Keystone (NixOS) on Apple Silicon after the Asahi Linux environment has been set up.

### 4.1 Why nixos-anywhere + Disko Won't Work

**Important**: The standard Keystone deployment method (`nixos-anywhere` with `disko`) **cannot be used** on Apple Silicon. Here's why:

1. **Disko reformats the entire disk**: Disko is designed to declaratively partition and format disks. On Apple Silicon, this would destroy critical system partitions.

2. **Apple Silicon requires preserved partitions**: The following partitions must NEVER be modified:
   | Partition | Type | Purpose |
   |-----------|------|---------|
   | iBootSystemContainer | APFS | Boot policies, system firmware, boot picker |
   | macOS Container | APFS | Main macOS installation |
   | RecoveryOSContainer | APFS | System recovery (deletion breaks OS upgrades) |

3. **Asahi creates its own structure**: The Asahi installer creates:
   - Stub APFS partition (2.5GB) - Contains m1n1 stage 1 bootloader
   - EFI System Partition (500MB) - Contains m1n1 stage 2, U-Boot, kernels
   - These must be used as-is, not replaced

4. **ZFS not supported**: The Asahi Linux kernel does not support ZFS. Keystone's default ZFS configuration will not work - ext4 is required.

### 4.2 Apple Silicon Partition Layout

After running the Asahi installer, your disk layout looks like:

```
[iBootSystemContainer] [macOS] [Stub APFS] [ESP] [Free Space] [Recovery]
       DO NOT TOUCH      ↑         ↑        ↑         ↑        DO NOT TOUCH
                     Preserve   Created  Created   For Linux
                                by Asahi by Asahi  root partition
```

**Key constraint**: All new partitions must be placed between the existing partitions and the RecoveryOSContainer (which must remain last).

### 4.3 Prerequisites

Before installing NixOS, ensure:

1. **Asahi Linux installer has been run**: `curl https://alx.sh | sh`
   - Select "UEFI environment only" option (recommended)
   - This creates the stub APFS and ESP partitions

2. **Boot into Keystone installer ISO**: The Apple Silicon ISO you built

3. **Network connectivity established**: Verify with `ip addr` and `ping`

### 4.4 Installation Approach

Since disko cannot be used, we provide two installation methods:

1. **Automated script** - `install-apple-silicon` (included in ISO)
2. **Manual installation** - Step-by-step commands (recommended for troubleshooting)

---

#### 4.4.1 Automated Script Installation

The `install-apple-silicon` script is **included in the ISO** and available in `$PATH` after booting.

**Usage:**
```bash
# From the booted installer ISO (script is pre-installed):
install-apple-silicon --hostname my-macbook

# With SSH key:
install-apple-silicon --hostname my-macbook --ssh-key ~/.ssh/id_ed25519.pub

# With LUKS encryption:
install-apple-silicon --hostname my-macbook --encrypt

# Preview without making changes:
install-apple-silicon --dry-run
```

**Options:**
- `--hostname NAME` - System hostname (default: keystone-mac)
- `--disk DEVICE` - Target disk device (default: /dev/nvme0n1)
- `--encrypt` - Enable LUKS encryption on root partition
- `--ssh-key FILE` - SSH public key file to add for admin user
- `--dry-run` - Show what would be done without making changes

**What the script does:**
1. Detects the Asahi ESP partition (from `/proc/device-tree/chosen/asahi,efi-system-partition`)
2. Creates a root partition in free space (if not already exists)
3. Optionally encrypts root with LUKS
4. Formats root as ext4
5. Mounts ESP to `/mnt/boot` and root to `/mnt`
6. Initializes a Keystone flake template with Apple Silicon-specific configuration
7. Runs `nixos-install` with the generated flake
8. Copies the configuration to `/root/keystone-config` for future modifications

---

#### 4.4.2 Manual Installation (Recommended)

Manual installation gives full control and is easier to troubleshoot. This method is recommended when the automated script encounters issues.

##### Step 1: Verify Partition Layout

First, check the current disk layout:

```bash
# View partition layout
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL

# Get detailed GPT information (sector locations)
sgdisk -p /dev/nvme0n1
```

Expected Asahi layout:
```
Number  Start (sector)    End (sector)  Size       Code  Name
   1               6          128005   500.0 MiB   AF0B  iBootSystemContainer
   2          128006        24542213   93.1 GiB    AF0A  (macOS)
   3        24542214        25152517   2.3 GiB     AF0A  (Asahi stub)
   4        25152518        25274629   477.0 MiB   EF00  (ESP)
   5        59968630        61279338   5.0 GiB     AF0C  RecoveryOSContainer
```

**Key observation**: Free space exists between partition 4 (ESP, ends ~25274629) and partition 5 (Recovery, starts ~59968630).

##### Step 2: Create Linux Root Partition

The Recovery partition **must remain last** on disk. Create the new partition in the gap:

```bash
# Create partition 6 between ESP and Recovery
# Adjust sector numbers based on YOUR sgdisk output!
sgdisk -n 6:25274630:59968628 -t 6:8300 -c 6:nixos /dev/nvme0n1

# Inform kernel of partition table changes
partprobe /dev/nvme0n1
sleep 2

# Verify partition was created
lsblk
```

##### Step 3a: Format WITHOUT Encryption (Simple)

```bash
# Format as ext4
mkfs.ext4 -L nixos /dev/nvme0n1p6

# Mount filesystems
mount /dev/nvme0n1p6 /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p4 /mnt/boot
```

##### Step 3b: Format WITH LUKS Encryption (Recommended)

```bash
# Set up LUKS encryption (you'll be prompted for a passphrase)
cryptsetup luksFormat --type luks2 /dev/nvme0n1p6

# Open the encrypted volume
cryptsetup luksOpen /dev/nvme0n1p6 cryptroot

# Format the encrypted volume as ext4
mkfs.ext4 -L nixos /dev/mapper/cryptroot

# Mount filesystems
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p4 /mnt/boot

# Save the LUKS UUID (needed for configuration)
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p6)
echo "LUKS UUID: $LUKS_UUID"
```

##### Step 4: Get ESP PARTUUID

```bash
# Get ESP PARTUUID (needed for hardware-configuration.nix)
ESP_PARTUUID=$(blkid -s PARTUUID -o value /dev/nvme0n1p4)
echo "ESP PARTUUID: $ESP_PARTUUID"

# Or from device tree (more reliable on Asahi)
cat /proc/device-tree/chosen/asahi,efi-system-partition | tr -d '\0'
```

##### Step 5: Generate NixOS Configuration

```bash
# Generate hardware configuration
nixos-generate-config --root /mnt

# This creates:
# /mnt/etc/nixos/configuration.nix
# /mnt/etc/nixos/hardware-configuration.nix
```

##### Step 6: Edit Configuration Files

Edit `/mnt/etc/nixos/hardware-configuration.nix`:

```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Boot partition (use YOUR ESP PARTUUID)
  fileSystems."/boot" = {
    device = "/dev/disk/by-partuuid/YOUR-ESP-PARTUUID-HERE";
    fsType = "vfat";
  };

  # LUKS encryption (only if using --encrypt)
  # Use YOUR LUKS UUID from Step 3b
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/YOUR-LUKS-UUID-HERE";
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
```

Edit `/mnt/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # CRITICAL: U-Boot cannot write EFI variables - prevents bricking!
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "0";

  networking.hostName = "keystone-mac";

  # Networking
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;

  # Users
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    initialPassword = "changeme";
  };

  # SSH
  services.openssh.enable = true;

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim git curl wget htop
  ];

  system.stateVersion = "25.05";
}
```

##### Step 7: Add Apple Silicon Support

For full Apple Silicon support, you need the `nixos-apple-silicon` flake. Create `/mnt/etc/nixos/flake.nix`:

```nix
{
  description = "Keystone - Apple Silicon Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-apple-silicon, ... }: {
    nixosConfigurations.keystone-mac = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-apple-silicon.nixosModules.default
        ./configuration.nix
        {
          # Asahi hardware support
          hardware.asahi = {
            enable = true;
            # Use /mnt/boot/asahi during install, update to /boot/asahi before reboot
            peripheralFirmwareDirectory = /mnt/boot/asahi;
            setupAsahiSound = true;
          };
        }
      ];
    };
  };
}
```

**Important notes about the flake configuration:**

1. **`useExperimentalGPUDriver` is deprecated** - As of late 2024, the Asahi GPU drivers have been merged into mainline Mesa, so this option is no longer needed and will cause an error if included.

2. **`peripheralFirmwareDirectory` - Two-Phase Path Handling**:

   The firmware path is evaluated at **build time**, not runtime. This creates a path mismatch:

   | Phase | ESP Mount | Firmware Path |
   |-------|-----------|---------------|
   | During `nixos-install` | `/mnt/boot` | `/mnt/boot/asahi` |
   | After reboot (runtime) | `/boot` | `/boot/asahi` |

   **Solution**: Use a two-phase approach:
   1. During install: Use `/mnt/boot/asahi` with `--impure` flag
   2. Before reboot: Update flake to `/boot/asahi`
   3. Future rebuilds: Work without `--impure` (path exists)

   **IMPORTANT**: Update the path BEFORE rebooting:
   ```bash
   # After nixos-install completes, update the path
   sed -i 's|/mnt/boot/asahi|/boot/asahi|g' /mnt/etc/nixos/flake.nix
   ```

   The `install-apple-silicon` script handles this automatically.

##### Step 8: Run Installation

```bash
# IMPORTANT: Must use --impure flag!
# The firmware path detection requires filesystem access, which pure evaluation blocks.
nixos-install --flake /mnt/etc/nixos#keystone-mac --no-root-passwd --impure
```

**Why `--impure` is required:**
- Flakes use "pure evaluation" by default, blocking access to absolute paths like `/mnt/boot/asahi`
- The nixos-apple-silicon module needs to read the firmware files during evaluation
- Without `--impure`, you'll get: `error: access to absolute path '/mnt/boot/asahi' is forbidden in pure evaluation mode`

**Do NOT use the non-flake method:**
```bash
# This will NOT work for Apple Silicon!
# nixos-install --no-root-passwd
```
The standard nixos-install without `--flake` uses only `configuration.nix`, which doesn't include the Asahi kernel. This results in a **black screen on boot** because the standard NixOS kernel lacks Apple Silicon display drivers.

##### Step 9: Reboot

```bash
# Unmount filesystems
umount /mnt/boot
umount /mnt

# If using LUKS:
cryptsetup luksClose cryptroot

# Reboot
reboot
```

**Post-reboot:**
1. Hold power button during boot to access boot picker
2. Select "NixOS" (or "EFI Boot")
3. If using LUKS, enter passphrase at prompt
4. Login as `admin` with password `changeme`
5. Change password immediately: `passwd`

### 4.5 Required NixOS Configuration for Apple Silicon

Apple Silicon requires specific configuration that differs from x86_64:

```nix
{ config, pkgs, lib, ... }: {
  # Import nixos-apple-silicon overlay
  imports = [
    # From your flake inputs
    inputs.nixos-apple-silicon.nixosModules.default
  ];

  # Filesystem configuration (NO ZFS - use ext4)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partuuid/<your-esp-uuid>";
    fsType = "vfat";
  };

  # CRITICAL: U-Boot cannot write EFI variables
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "0";

  # Enable Asahi hardware support
  hardware.asahi = {
    enable = true;
    # GPU drivers are now in mainline Mesa (useExperimentalGPUDriver is deprecated)
    peripheralFirmwareDirectory = /boot/asahi;  # Firmware extracted by Asahi installer
    setupAsahiSound = true;  # PipeWire/ALSA config for Apple speakers
  };

  # Disable features not available on Apple Silicon
  # (TPM, Secure Boot are not available)

  # NetworkManager recommended for USB Ethernet and WiFi
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
}
```

### 4.6 Key Differences from x86_64 Installation

| Feature | x86_64 | Apple Silicon |
|---------|--------|---------------|
| Deployment tool | nixos-anywhere + disko | Custom script (manual partitioning) |
| Filesystem | ZFS (recommended) | ext4 only |
| EFI Variables | `canTouchEfiVariables = true` | `= false` (U-Boot limitation) |
| Boot Loader | systemd-boot | U-Boot → systemd-boot |
| TPM Support | Yes | No |
| Secure Boot | Yes (Lanzaboote) | No |
| Partitioning | Full disk (disko) | Partial disk (preserve Apple partitions) |

### 4.7 Post-Installation

After `nixos-install` completes:

1. **Reboot**: `reboot`
2. **Select NixOS** from the boot picker (hold power button during boot)
3. **First boot** may take longer as firmware is extracted

**Troubleshooting:**
- If boot fails, hold power button to access boot picker
- Select "Options" → "Startup Disk" to change default boot OS
- Recovery is always available by holding power button

### 4.8 Future Improvements

- [ ] Add Keystone OS module support for ext4-only configurations
- [x] Create Apple Silicon-specific flake template (implemented in `install-apple-silicon` script)
- [x] Add GPU driver and sound configuration (GPU now in mainline Mesa, `setupAsahiSound = true`)
- [ ] Document WiFi setup with iwd/NetworkManager
- [x] Add pre-reboot verification to prevent black screen issues
- [x] Document two-phase firmware path handling (`/mnt/boot/asahi` → `/boot/asahi`)
- [ ] Add desktop installation as default in install-apple-silicon script (with --no-desktop flag to opt out)

### 4.9 Installing Keystone Desktop (Hyprland)

After a successful base installation, you can add the Keystone desktop environment (Hyprland) to your Apple Silicon Mac.

#### Prerequisites
- Successfully booted NixOS on Apple Silicon
- Network connectivity established
- Logged in as admin user

#### Step 1: Update flake.nix

Edit `/etc/nixos/flake.nix` to add the Keystone flake input and desktop module:

```nix
{
  description = "Keystone - Apple Silicon Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Add Keystone input
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Add home-manager for desktop user configuration
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-apple-silicon, keystone, home-manager, ... }: {
    nixosConfigurations.keystone-mac = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-apple-silicon.nixosModules.default
        home-manager.nixosModules.home-manager
        keystone.nixosModules.desktop  # Add desktop module
        ./configuration.nix
        {
          hardware.asahi = {
            enable = true;
            peripheralFirmwareDirectory = /boot/asahi;
            setupAsahiSound = true;
          };
        }
      ];
    };
  };
}
```

#### Step 2: Update configuration.nix

Modify `/etc/nixos/configuration.nix` to enable desktop for your user:

```nix
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ... existing configuration ...

  # Enable home-manager integration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  # Configure admin user with desktop
  home-manager.users.admin = { pkgs, ... }: {
    imports = [
      # Import Keystone home-manager modules (from flake)
    ];

    home.stateVersion = "25.05";

    # Enable Keystone desktop
    keystone.desktop = {
      enable = true;
      hyprland = {
        enable = true;
        modifierKey = "SUPER";  # Use Command key as modifier
        capslockAsControl = true;
        scale = 2;  # HiDPI for Retina display
      };
    };

    # Enable terminal tools
    keystone.terminal = {
      enable = true;
      git = {
        userName = "Your Name";
        userEmail = "you@example.com";
      };
    };
  };
}
```

#### Step 3: Rebuild the System

```bash
cd /etc/nixos
sudo nixos-rebuild switch --flake .#keystone-mac
```

This will:
- Download and build Hyprland and all desktop components
- Configure greetd display manager
- Set up PipeWire audio
- Install desktop applications (browser, file manager, terminal)

#### Step 4: Reboot or Start Desktop Session

After rebuild completes:

```bash
# Reboot to start fresh with greetd
sudo reboot

# Or manually start Hyprland (if already logged in)
Hyprland
```

#### Desktop Features on Apple Silicon

| Feature | Status | Notes |
|---------|--------|-------|
| Hyprland compositor | ✓ Works | Full Wayland support |
| HiDPI/Retina | ✓ Works | Set `scale = 2` for MacBook displays |
| Audio (speakers) | ✓ Works | Via `setupAsahiSound = true` |
| Touchpad gestures | ✓ Works | Configure via Hyprland input settings |
| GPU acceleration | Partial | Experimental via Asahi GPU drivers |
| External displays | Varies | Depends on adapter/dock support |

#### Key Bindings (Default)

With `modifierKey = "SUPER"` (Command key):

| Binding | Action |
|---------|--------|
| Super+Return | Open terminal (Ghostty) |
| Super+Space | Application launcher |
| Super+B | Open browser |
| Super+E | File manager |
| Super+W | Close window |
| Super+1-0 | Switch workspace |
| Super+Escape | Keystone menu |

#### Troubleshooting

**Black screen after enabling desktop:**
- Ensure `hardware.asahi.enable = true` is set
- Check that Asahi kernel is being used: `uname -r` should show `asahi`

**No audio:**
- Verify `setupAsahiSound = true` in hardware.asahi config
- Run `wpctl status` to check PipeWire

**Touchpad not working:**
- Add to Hyprland config: `input:touchpad:natural_scroll = true`
