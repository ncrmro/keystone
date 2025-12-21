{
  config,
  pkgs,
  lib,
  ...
}: {
  # ============================================================================
  # REQUIRED CONFIGURATION
  # ============================================================================
  #
  # Search for "TODO:" to find all values you must change before deployment.
  #

  # System Identity
  # ─────────────────────────────────────────────────────────────────────────────
  networking.hostName = "my-machine"; # TODO: Change to your hostname

  # Required for ZFS - unique 8-character hex string
  # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId = "00000000"; # TODO: Generate and replace this value

  # State version - DO NOT CHANGE after initial deployment
  system.stateVersion = "25.05";

  # ============================================================================
  # KEYSTONE OS CONFIGURATION
  # ============================================================================

  keystone.os = {
    enable = true;

    # ──────────────────────────────────────────────────────────────────────────
    # Storage Configuration
    # ──────────────────────────────────────────────────────────────────────────
    #
    # Keystone supports two filesystem types:
    #   - zfs: Full features (snapshots, compression, checksums, native encryption)
    #   - ext4: Simple/legacy (LUKS encryption only, no advanced features)
    #
    storage = {
      type = "zfs"; # "zfs" (recommended) or "ext4"

      # Disk device(s) - ALWAYS use /dev/disk/by-id/ paths for stability
      # Find your disk IDs with: ls -la /dev/disk/by-id/
      # Example: /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V
      devices = [
        "/dev/disk/by-id/YOUR-DISK-ID-HERE" # TODO: Replace with your disk ID
        # Add more disks for multi-disk configurations:
        # "/dev/disk/by-id/YOUR-SECOND-DISK-ID"
      ];

      # Multi-disk mode (only for ZFS with 2+ disks)
      # Options: "single", "mirror", "stripe", "raidz1", "raidz2", "raidz3"
      #   - single: One disk (default)
      #   - mirror: RAID1 - all disks mirror each other (2+ disks)
      #   - stripe: RAID0 - data striped, no redundancy (2+ disks)
      #   - raidz1: RAID5 equivalent - single parity (3+ disks)
      #   - raidz2: RAID6 equivalent - double parity (4+ disks)
      #   - raidz3: Triple parity (5+ disks)
      mode = "single";

      # Partition sizes
      esp.size = "1G"; # EFI System Partition (rarely needs changing)
      swap.size = "16G"; # Swap partition (set to "0" to disable)
      # credstore.size = "100M";  # LUKS credstore for ZFS keys (ZFS only)

      # ZFS-specific options
      zfs = {
        compression = "zstd"; # "zstd" (best), "lz4" (fastest), "off"
        atime = "off"; # Access time updates (off = better performance)
        autoSnapshot = true; # Enable automatic snapshots
        autoScrub = true; # Weekly integrity scrub
        # arcMax = "8G";       # ARC cache limit (null = automatic)
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Security Features
    # ──────────────────────────────────────────────────────────────────────────

    # Secure Boot - requires UEFI with Secure Boot support
    secureBoot = {
      enable = true; # Disable if your hardware doesn't support Secure Boot
    };

    # TPM - automatic disk unlock using hardware TPM
    tpm = {
      enable = true; # Disable if no TPM2 chip available
      pcrs = [1 7]; # PCRs to bind to (1=firmware, 7=secure boot state)
      # Use [7] only for more update-resilient binding
    };

    # SSH server for remote administration
    ssh.enable = true;

    # ──────────────────────────────────────────────────────────────────────────
    # Remote Unlock (for headless servers)
    # ──────────────────────────────────────────────────────────────────────────
    #
    # Enables SSH in initrd for remote disk unlocking. Essential for headless
    # servers where you can't enter the disk password locally.
    #
    remoteUnlock = {
      enable = false; # Set to true for headless servers
      port = 22;
      dhcp = true;
      networkModule = "virtio_net"; # Change based on your NIC driver
      # Common modules: "e1000e" (Intel), "igb" (Intel server), "r8169" (Realtek)
      # For VMs: "virtio_net"

      # SSH keys authorized for initrd unlock
      # If empty, keys are collected from all configured users
      authorizedKeys = [
        # "ssh-ed25519 AAAAC3... admin@workstation"
      ];
    };

    # ──────────────────────────────────────────────────────────────────────────
    # User Configuration
    # ──────────────────────────────────────────────────────────────────────────
    #
    # Keystone creates users with:
    #   - NixOS user accounts
    #   - ZFS home directories with quotas and compression (when using ZFS)
    #   - Optional terminal dev environment (Helix, Zsh, Zellij, Starship)
    #   - Optional desktop environment (Hyprland, Waybar, Mako)
    #

    users = {
      # ────────────────────────────────────────────────────────────────────────
      # Primary Administrator
      # ────────────────────────────────────────────────────────────────────────
      admin = {
        fullName = "System Administrator"; # TODO: Change to your name
        email = "admin@example.com"; # TODO: Change to your email

        # Groups - add "wheel" for sudo access
        extraGroups = [
          "wheel" # Required for sudo
          # "networkmanager"  # For desktop/laptop
          # "video" "audio"   # For desktop/laptop
        ];

        # Authentication - choose ONE method:
        #
        # Option 1: Plain text password (INSECURE - for testing only)
        # WARNING: Stored in Nix store, visible to all users
        initialPassword = "changeme"; # TODO: Change or switch to hashedPassword

        # Option 2: Hashed password (RECOMMENDED for production)
        # Generate with: mkpasswd -m sha-512
        # hashedPassword = "$6$...";  # TODO: Uncomment and set

        # SSH public keys for this user
        # Generate with: ssh-keygen -t ed25519
        authorizedKeys = [
          # TODO: Add your SSH public key(s)
          # "ssh-ed25519 AAAAC3... admin@laptop"
          # "ssh-ed25519 AAAAC3... admin@workstation"
        ];

        # Terminal development environment
        terminal = {
          enable = true; # Includes: Zsh, Helix, Zellij, Starship, Git
        };

        # Desktop environment (for use with keystone.nixosModules.desktop)
        desktop = {
          enable = false; # Set to true when using desktop module
          hyprland = {
            modifierKey = "SUPER"; # "SUPER" (Windows key) or "ALT"
            capslockAsControl = true; # Remap Caps Lock to Control
          };
        };

        # ZFS home directory options
        zfs = {
          quota = null; # e.g., "100G", "500G", null for unlimited
          compression = "lz4"; # "lz4", "zstd", "off"
          atime = "off";
        };
      };

      # ────────────────────────────────────────────────────────────────────────
      # Additional Users (Examples)
      # ────────────────────────────────────────────────────────────────────────
      #
      # Uncomment and modify these examples as needed:

      # Developer with desktop access
      # alice = {
      #   fullName = "Alice Developer";
      #   email = "alice@example.com";
      #   extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
      #   hashedPassword = "$6$...";  # mkpasswd -m sha-512
      #   authorizedKeys = [
      #     "ssh-ed25519 AAAAC3... alice@laptop"
      #   ];
      #   terminal.enable = true;
      #   desktop = {
      #     enable = true;
      #     hyprland.modifierKey = "SUPER";
      #   };
      #   zfs.quota = "500G";
      # };

      # Limited user (no sudo access)
      # guest = {
      #   fullName = "Guest User";
      #   email = "guest@example.com";
      #   extraGroups = [];  # No wheel = no sudo
      #   initialPassword = "guest123";
      #   terminal.enable = true;
      #   zfs.quota = "10G";  # Limited storage
      # };

      # Service account (no interactive shell)
      # backup = {
      #   fullName = "Backup Service";
      #   email = "backup@internal";
      #   extraGroups = [];
      #   hashedPassword = "!";  # Disabled password login
      #   authorizedKeys = [
      #     ''command="/run/current-system/sw/bin/restic",no-pty ssh-ed25519 AAAA... backup-server''
      #   ];
      #   terminal.enable = false;
      # };
    };
  };

  # ============================================================================
  # SYSTEM SETTINGS
  # ============================================================================

  time.timeZone = "UTC"; # TODO: Change to your timezone (e.g., "America/New_York")

  # Nix settings - keystone.os handles flakes and GC automatically
  nix.settings.trusted-users = ["root" "@wheel"];

  # ============================================================================
  # ADDITIONAL PACKAGES (Optional)
  # ============================================================================
  #
  # Add system-wide packages here. User-specific packages should go in
  # home-manager configuration instead.
  #
  environment.systemPackages = with pkgs; [
    # Secure Boot management (useful for post-install provisioning)
    sbctl

    # Add your packages here:
    # vim
    # git
    # htop
  ];

  # ============================================================================
  # NETWORKING (Optional)
  # ============================================================================

  # Additional firewall ports (SSH is already enabled by keystone.os.ssh)
  # networking.firewall.allowedTCPPorts = [ 80 443 ];
  # networking.firewall.allowedUDPPorts = [ ];

  # Static IP configuration (for servers with fixed addresses)
  # networking.interfaces.eth0.ipv4.addresses = [{
  #   address = "192.168.1.100";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = "192.168.1.1";
  # networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
}
