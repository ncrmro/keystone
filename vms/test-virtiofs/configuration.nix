{
  config,
  pkgs,
  lib,
  ...
}: {
  # Test configuration for virtiofs filesystem sharing
  # This VM demonstrates using the host's /nix/store via virtiofs with overlay
  #
  # Prerequisites:
  #   - Host has virtiofs enabled (modules/virtualization/host-virtiofs.nix)
  #   - VM created with: ./bin/virtual-machine --name test-virtiofs --enable-virtiofs --start
  #
  # Deploy with:
  #   nixos-anywhere --flake .#test-virtiofs root@192.168.100.99

  system.stateVersion = "25.05";
  
  # System identity
  networking.hostName = "test-virtiofs-vm";

  # Import virtiofs guest module
  imports = [
    ../../modules/virtualization/guest-virtiofs.nix
  ];

  # Enable virtiofs filesystem sharing
  keystone.virtualization.guest.virtiofs = {
    enable = true;
    shareName = "nix-store-share";  # Must match VM XML
    persistentRwStore = false;  # Use tmpfs (RAM disk)
  };

  # Simple boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem - simple ext4 for testing
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/vda2";
    fsType = "vfat";
  };

  # Serial console for VM testing
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable serial console in systemd
  boot.initrd.systemd.emergencyAccess = true;

  # Ensure virtio modules are available
  boot.initrd.availableKernelModules = [
    "virtio_blk"
    "virtio_pci"
    "virtio_net"
    "virtiofs"  # Required for virtiofs
    "overlay"   # Required for overlay fs
  ];

  # SSH access for testing
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Basic networking
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = false;

  # Test user
  users.mutableUsers = true;
  users.users.testuser = {
    isNormalUser = true;
    initialPassword = "testpass";
    extraGroups = ["wheel"];
  };

  users.users.root.initialPassword = "root";

  # Allow sudo without password (testing only)
  security.sudo.wheelNeedsPassword = false;

  # Basic packages for testing
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
  ];

  # Nix settings
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "testuser"];
  };

  # Verification service - checks virtiofs is working
  systemd.services.verify-virtiofs = {
    description = "Verify virtiofs mount is working";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "verify-virtiofs" ''
        set -e
        
        echo "========================================"
        echo "Verifying virtiofs configuration"
        echo "========================================"
        
        echo ""
        echo "1. Checking virtiofs mount..."
        if mount | grep -q "type virtiofs"; then
          echo "✓ virtiofs mount found:"
          mount | grep "type virtiofs"
        else
          echo "✗ virtiofs mount NOT found!"
          echo "Expected mount: nix-store-share on /sysroot/nix/.ro-store type virtiofs"
          exit 1
        fi
        
        echo ""
        echo "2. Checking overlay mount..."
        if mount | grep -q "overlay on /nix/store"; then
          echo "✓ overlay mount found:"
          mount | grep "overlay on /nix/store"
        else
          echo "✗ overlay mount NOT found!"
          echo "Expected: overlay on /nix/store type overlay"
          exit 1
        fi
        
        echo ""
        echo "3. Checking /nix/store access..."
        if [ -d "/nix/store" ]; then
          STORE_COUNT=$(ls /nix/store 2>/dev/null | wc -l)
          if [ "$STORE_COUNT" -gt 0 ]; then
            echo "✓ /nix/store is accessible with $STORE_COUNT paths"
          else
            echo "✗ /nix/store is empty!"
            exit 1
          fi
        else
          echo "✗ /nix/store does not exist!"
          exit 1
        fi
        
        echo ""
        echo "4. Checking write capability (overlay)..."
        TEST_FILE="/nix/store/.virtiofs-test-$$"
        if touch "$TEST_FILE" 2>/dev/null; then
          echo "✓ Can write to /nix/store (overlay working)"
          rm -f "$TEST_FILE"
        else
          echo "✗ Cannot write to /nix/store!"
          echo "Overlay may not be configured correctly"
          exit 1
        fi
        
        echo ""
        echo "5. Checking kernel modules..."
        if lsmod | grep -q virtiofs; then
          echo "✓ virtiofs kernel module loaded"
        else
          echo "⚠ virtiofs module not in lsmod (may be built-in)"
        fi
        
        if lsmod | grep -q overlay; then
          echo "✓ overlay kernel module loaded"
        else
          echo "⚠ overlay module not in lsmod (may be built-in)"
        fi
        
        echo ""
        echo "========================================"
        echo "✓ virtiofs verification PASSED"
        echo "========================================"
      '';
    };
  };

  # Display verification results in MOTD
  users.motd = ''
    
    ╔════════════════════════════════════════════════════════════╗
    ║              Test Virtiofs VM                              ║
    ║        Filesystem sharing via virtiofs + overlay           ║
    ╚════════════════════════════════════════════════════════════╝
    
    Check virtiofs status:
      systemctl status verify-virtiofs
      journalctl -u verify-virtiofs
    
    Manual verification:
      mount | grep virtiofs
      mount | grep overlay
      ls /nix/store | wc -l
      df -h /sysroot/nix/.rw-store
    
    Login: testuser / testpass  or  root / root
    
  '';
}
