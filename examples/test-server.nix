{
  config,
  pkgs,
  ...
}: {
  #
  # Keystone Test Server Example Configuration
  #
  # This is a minimal server configuration for testing nixos-anywhere deployments.
  # It demonstrates the basic setup needed for a Keystone server with encryption.
  #
  # Usage:
  #   1. Copy this file or create vms/your-server/configuration.nix
  #   2. Customize the options below
  #   3. Add to flake.nix nixosConfigurations
  #   4. Deploy with: nixos-anywhere --flake .#your-server root@target-ip
  #

  ## System Identity
  #
  # The hostname must be unique within your network and will be used for:
  # - mDNS resolution (hostname.local)
  # - System identification
  # - Logging and monitoring
  networking.hostName = "test-server";

  # Required for ZFS: Unique 8-character hex identifier
  # Generate a new one with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  # Important: Each ZFS system needs a unique hostId
  networking.hostId = "deadbeef";

  ## Keystone Modules Configuration
  #
  keystone = {
    ## Disk Configuration
    #
    # The disko module handles disk partitioning, ZFS pool creation, and encryption
    disko = {
      enable = true;

      # Disk device selection - CRITICAL SETTING
      #
      # Choose the correct device for your environment:
      #
      # VMs (QEMU/KVM with virtio):
      #   device = "/dev/vda";
      #
      # VMs (VirtualBox or older configs):
      #   device = "/dev/sda";
      #
      # Physical hardware (RECOMMENDED - stable identifier):
      #   device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V";
      #   device = "/dev/disk/by-id/ata-WDC_WD20EFRX-68EUZN0_WD-WCC4M0123456";
      #
      # Physical hardware (NOT recommended - can change on reboot):
      #   device = "/dev/nvme0n1";  # Avoid on production
      #   device = "/dev/sda";       # Avoid on production
      #
      # To list available devices on target system:
      #   ls -l /dev/disk/by-id/
      #
      device = "/dev/vda";

      # Encrypted swap configuration
      #
      # Swap is encrypted with a random key on each boot (no hibernation support).
      # Set to false if you don't need swap or want to save disk space.
      enableEncryptedSwap = true;

      # Swap size guidelines:
      #   8G  - VMs with 4GB RAM
      #   16G - VMs with 8GB RAM
      #   32G - Workstations with 16GB RAM
      #   64G - Default (suitable for most servers)
      #   128G - High-memory servers
      swapSize = "8G";

      # EFI System Partition size
      # Default 1G is sufficient for most use cases
      # Increase to 2G if you need multiple boot entries or custom kernels
      # espSize = "1G";
    };

    ## Server Module
    #
    # Enables Keystone server features:
    # - SSH server with public key authentication only
    # - mDNS/Avahi for network discovery
    # - Firewall configured to allow only SSH (port 22)
    # - Server-optimized kernel parameters
    # - System administration tools (vim, git, htop, etc.)
    server.enable = true;
  };

  ## SSH Access Configuration
  #
  # IMPORTANT: You MUST add at least one SSH public key here for post-deployment access!
  #
  # To get your public key:
  #   cat ~/.ssh/id_ed25519.pub
  #
  # If you don't have an SSH key, generate one:
  #   ssh-keygen -t ed25519 -C "your-email@example.com"
  #
  users.users.root.openssh.authorizedKeys.keys = [
    # Replace this placeholder with your actual SSH public key(s)
    # Format: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJlZ... user@hostname"

    # Example with multiple keys for team access:
    # "ssh-ed25519 AAAAC3... admin@workstation"
    # "ssh-ed25519 AAAAC3... developer@laptop"
    # "ssh-ed25519 AAAAC3... backup@backup-server"

    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEPlaceholderKeyReplaceWithYourActualKey placeholder@example"
  ];

  ## Optional: Additional Configuration
  #
  # Uncomment and customize these settings as needed:

  # Set timezone (default is UTC from server module)
  # time.timeZone = "America/New_York";
  # time.timeZone = "Europe/London";
  # time.timeZone = "Asia/Tokyo";

  # Add extra packages beyond the server defaults
  # IMPORTANT: sbctl is required for Secure Boot key management
  environment.systemPackages = with pkgs; [
    sbctl # Secure Boot key management tool (required for key generation/enrollment)
    #   neovim    # Enhanced text editor
    #   curl      # HTTP client
    #   wget      # Download tool
    #   jq        # JSON processor
    #   tree      # Directory tree viewer
  ];

  # Customize swap size if needed
  # keystone.disko.swapSize = "32G";

  # Disable encrypted swap if not needed
  # keystone.disko.enableEncryptedSwap = false;

  ## Common Configuration Errors and Solutions
  #
  # Error: "Failed assertions: ZFS requires networking.hostId to be set"
  # Solution: Ensure networking.hostId is set (see above)
  #
  # Error: "Cannot connect via SSH after deployment"
  # Solution: Verify your SSH public key is correctly added (see above)
  #
  # Error: "Device /dev/vda not found"
  # Solution: Check your VM type - VirtualBox uses /dev/sda instead of /dev/vda
  #
  # Error: "Path '/dev/disk/by-id/...' does not exist"
  # Solution: The by-id path may be different on your hardware - run 'ls -l /dev/disk/by-id/' on the target
  #

  ## Deployment Instructions
  #
  # 1. Build and verify this configuration:
  #    nix build .#nixosConfigurations.test-server.config.system.build.toplevel
  #
  # 2. Boot target VM from Keystone installer ISO
  #
  # 3. Note the IP address shown on the VM console
  #
  # 4. Deploy using nixos-anywhere:
  #    nixos-anywhere --flake .#test-server root@<target-ip>
  #
  #    Or use the deployment wrapper:
  #    ./scripts/deploy-vm.sh test-server <target-ip> --verify
  #
  # 5. Wait for deployment to complete (5-10 minutes)
  #
  # 6. After reboot, unlock the credstore when prompted (VMs without TPM2)
  #
  # 7. SSH into the deployed server:
  #    ssh root@<target-ip>
  #    ssh root@test-server.local
  #
  # 8. Verify the deployment:
  #    ./scripts/verify-deployment.sh test-server <target-ip>
  #

  ## Security Notes
  #
  # - All data is encrypted at rest (LUKS credstore + ZFS native encryption)
  # - TPM2 provides automatic unlock on bare metal (VMs use password prompt)
  # - SSH access is public key only (no password authentication)
  # - Firewall blocks all ports except SSH (22)
  # - Root login is restricted to SSH keys only
  #

  ## What Gets Deployed
  #
  # File Systems:
  #   /boot - EFI System Partition (unencrypted, required for boot)
  #   /     - ZFS encrypted dataset (rpool/crypt/system)
  #   /nix  - ZFS encrypted dataset (rpool/crypt/system/nix)
  #   /var  - ZFS encrypted dataset (rpool/crypt/system/var)
  #   /home - ZFS encrypted dataset (rpool/crypt/system/home)
  #   /tmp  - ZFS encrypted dataset (rpool/crypt/system/tmp)
  #   swap  - Encrypted swap partition (optional, random key per boot)
  #
  # Services:
  #   - OpenSSH server (port 22)
  #   - Avahi mDNS responder
  #   - systemd-resolved (DNS)
  #   - ZFS auto-scrub (weekly)
  #   - ZFS auto-snapshot (configurable retention)
  #   - Nix garbage collection (weekly)
  #
  # Security:
  #   - Firewall enabled
  #   - Secure boot ready (requires manual key enrollment)
  #   - TPM2 integration (with password fallback)
  #   - No password authentication
  #
}
