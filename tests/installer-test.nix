# NixOS VM test for the Keystone installer TUI
#
# This test boots a VM with the installer TUI, interacts with it via
# keystrokes, runs through a complete unencrypted installation, and verifies
# the installation succeeded.
#
# Usage:
#   # Build and run the test headlessly
#   nix build .#checks.x86_64-linux.installer-test
#
#   # Run interactively (watch the VM)
#   nix build .#checks.x86_64-linux.installer-test.driverInteractive
#   ./result/bin/nixos-test-driver --interactive
#
#   # In the Python REPL
#   >>> start_all()
#   >>> test_script()  # Run full test
#   # Or step through manually:
#   >>> installer.wait_for_text("Network Connected")
#   >>> installer.send_key("ret")
#   # etc.
#
{
  pkgs,
  lib,
}: let
  keystone-installer-ui = pkgs.callPackage ../packages/keystone-installer-ui {};
in
  pkgs.testers.runNixOSTest {
    name = "keystone-installer";

    # Enable OCR for wait_for_text to work with graphical screens
    enableOCR = true;

    # Test machine configuration - simplified for VM testing
    nodes.installer = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Basic system configuration
      boot.kernelPackages = pkgs.linuxPackages_6_12;

      # Enable ZFS support
      boot.supportedFilesystems = ["zfs"];
      boot.zfs.forceImportRoot = false;
      boot.kernelModules = ["zfs"];
      boot.extraModulePackages = [config.boot.kernelPackages.zfs_2_3];
      networking.hostId = "8425e349";

      # Enable flakes
      nix.settings.experimental-features = ["nix-command" "flakes"];

      # Include tools needed for installation
      environment.systemPackages = with pkgs; [
        keystone-installer-ui
        networkmanager
        iproute2
        util-linux
        jq
        tpm2-tools
        parted
        cryptsetup
        config.boot.kernelPackages.zfs_2_3
        dosfstools
        e2fsprogs
        nix
        nixos-install-tools
        disko
        git
        shadow
      ];

      # NetworkManager for network detection
      networking.networkmanager.enable = true;

      # Disable getty on tty1 for installer
      systemd.services."getty@tty1".enable = false;
      systemd.services."autovt@tty1".enable = false;

      # Keystone installer service
      systemd.services.keystone-installer = {
        description = "Keystone Installer TUI";
        after = ["network.target" "NetworkManager.service"];
        wants = ["NetworkManager.service"];
        conflicts = ["getty@tty1.service" "autovt@tty1.service"];

        path = with pkgs; [
          networkmanager
          iproute2
          util-linux
          jq
          tpm2-tools
          parted
          cryptsetup
          config.boot.kernelPackages.zfs_2_3
          dosfstools
          e2fsprogs
          nix
          nixos-install-tools
          disko
          git
          shadow
        ];

        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = "${keystone-installer-ui}/bin/keystone-installer";
          Restart = "on-failure";
          RestartSec = "5s";
          StandardInput = "tty";
          StandardOutput = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = "yes";
          TTYVHangup = "yes";
        };
      };

      # VM-specific configuration
      virtualisation = {
        memorySize = 8192;
        diskSize = 30000;
        cores = 4;
        emptyDiskImages = [20000]; # Target disk for installation
        # Don't use useBootLoader - it causes UEFI boot issues in test VMs
        # The test framework boots directly via kernel+initrd
        graphics = true;
      };

      boot.kernelParams = ["console=ttyS0,115200" "console=tty1"];

      # Don't start installer automatically
      systemd.services.keystone-installer.wantedBy = lib.mkForce [];
    };

    # Python test script
    testScript = ''
      import time

      def wait_and_log(text, timeout=60):
          """Wait for text and log progress"""
          print(f"Waiting for: {text}")
          installer.wait_for_text(text, timeout=timeout)
          print(f"Found: {text}")

      def send_and_wait(key, expected_text, timeout=30):
          """Send a key and wait for expected result"""
          installer.send_key(key)
          time.sleep(0.5)
          if expected_text:
              wait_and_log(expected_text, timeout)

      def type_text(text):
          """Type text character by character"""
          for char in text:
              installer.send_chars(char)
              time.sleep(0.05)

      # Start the VM
      print("Starting installer VM...")
      installer.start()

      # Wait for system to boot
      print("Waiting for boot...")
      installer.wait_for_unit("multi-user.target")

      # Ensure an ethernet interface has an IP address before starting installer
      # The installer only waits 2 seconds, so DHCP must be complete
      # Check both eth0 and eth1 since test VMs may use either
      print("Verifying network connectivity...")
      installer.wait_until_succeeds("ip -4 addr show | grep -E 'eth[01]' | grep -q 'inet '", timeout=30)

      # Debug: show network status
      print("Network interfaces:")
      installer.succeed("ip -4 addr show")

      # Start the installer service
      print("Starting keystone-installer service...")
      installer.succeed("systemctl start keystone-installer")

      # Wait for TUI to appear
      print("Waiting for network check...")
      wait_and_log("Keystone Installer", timeout=60)
      # Wait for network screen - look for "Continue to Installation" button text
      # which appears on the ethernet-connected screen (the checkmark symbol may confuse OCR)
      wait_and_log("Continue to Installation", timeout=60)

      # Continue to method selection
      print("Continuing to method selection...")
      send_and_wait("ret", "Installation Method")

      # Select "Local installation"
      print("Selecting local installation...")
      installer.send_key("down")
      time.sleep(0.3)
      send_and_wait("ret", "Disk Selection")

      # Select disk
      print("Selecting disk...")
      time.sleep(2)
      # Use "Selected disk" instead of styled header or red warning - plain white text for OCR
      send_and_wait("ret", "Selected disk")

      # Confirm disk
      print("Confirming disk selection...")
      time.sleep(1)  # Extra delay before confirmation
      installer.send_key("ret")
      time.sleep(3)  # Wait for screen transition to encryption-choice

      # Take a screenshot for debugging
      installer.screenshot("after-disk-confirm")

      # Note: OCR has trouble with the encryption screen (likely due to emojis in menu items)
      # So we skip wait_for_text and just proceed with time-based navigation
      print("Proceeding to encryption choice screen (no OCR verification)...")

      # Select unencrypted (down arrow moves to second option)
      print("Selecting unencrypted installation...")
      installer.send_key("down")
      time.sleep(0.5)
      installer.send_key("ret")
      time.sleep(2)  # Wait for hostname screen

      # Enter hostname
      print("Entering hostname...")
      type_text("test-machine")
      time.sleep(0.5)
      installer.send_key("ret")
      time.sleep(2)  # Wait for username screen

      # Enter username
      print("Entering username...")
      type_text("testuser")
      time.sleep(0.5)
      installer.send_key("ret")
      time.sleep(2)  # Wait for password screen

      # Enter password
      print("Entering password...")
      type_text("testpass123")
      time.sleep(0.5)
      installer.send_key("ret")
      time.sleep(2)  # Wait for confirm password screen

      # Confirm password
      print("Confirming password...")
      type_text("testpass123")
      time.sleep(0.5)
      installer.send_key("ret")
      time.sleep(2)  # Wait for system type screen

      # Select server (default is first option, which is server)
      print("Selecting system type...")
      installer.send_key("ret")
      time.sleep(2)  # Wait for summary screen

      # Note: OCR has trouble with the summary screen too (styled text in Ink TUI)
      # So we skip wait_for_text and just proceed with time-based navigation
      print("Summary screen reached (no OCR verification)...")
      time.sleep(3)  # Give time for summary to render

      # Take screenshot for debugging
      installer.screenshot("summary-screen")

      # Start installation
      print("Starting installation...")
      installer.send_key("ret")
      time.sleep(5)  # Wait for installation to begin

      # Wait for installation to complete
      # Installation typically takes 3-5 minutes for unencrypted ext4
      # We'll poll for the completion by checking if installation artifacts exist
      print("Waiting for installation to complete...")
      print("This may take several minutes...")

      # Poll for completion by checking for installation artifacts
      # The installer creates /mnt with the full system when done
      installer.wait_until_succeeds(
          "test -f /mnt/home/testuser/nixos-config/flake.nix",
          timeout=600
      )
      print("Installation artifacts detected, verifying...")

      # Verify artifacts
      print("Verifying installation...")
      installer.succeed("mountpoint -q /mnt")
      installer.succeed("test -f /mnt/home/testuser/nixos-config/flake.nix")
      installer.succeed("test -f /mnt/etc/nixos/hardware-configuration.nix")
      installer.succeed("test -d /mnt/boot")
      installer.succeed("test -d /mnt/home/testuser")

      print("All tests passed!")
    '';

    # Interactive mode
    interactive.nodes.installer = {...}: {
      systemd.services.keystone-installer.wantedBy = ["multi-user.target"];
    };
  }
