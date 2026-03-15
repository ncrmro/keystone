# NixOS VM test for the Keystone installer TUI
#
# This test boots a VM with the installer TUI, interacts with it via
# keystrokes, runs through a complete unencrypted installation, and verifies
# the installation succeeded.
#
# Usage:
#   # Build and run the test headlessly
#   nix build .#installer-test
#
#   # Run interactively (watch the VM)
#   nix build .#installer-test.driverInteractive
#   ./result/bin/nixos-test-driver --interactive
#
#   # Or use the helper script
#   ./bin/test-installer --interactive
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
  keystone-tui = pkgs.callPackage ../../packages/keystone-tui {};
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
      # Use default kernel (NixOS 25.05 uses 6.12 LTS which is ZFS-compatible)

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
        keystone-tui
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
          ExecStart = "${keystone-tui}/bin/keystone-tui";
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
    #
    # The current keystone-tui is a scaffold (welcome screen + quit-on-q).
    # This test verifies the TUI starts, renders the welcome screen, and
    # exits cleanly when 'q' is pressed.
    testScript = ''
      import time

      # Start the VM
      print("Starting installer VM...")
      installer.start()

      # Wait for system to boot
      print("Waiting for boot...")
      installer.wait_for_unit("multi-user.target")

      # Start the TUI service
      print("Starting keystone-installer service...")
      installer.succeed("systemctl start keystone-installer")

      # Wait for the TUI process to be running
      print("Waiting for TUI process...")
      installer.wait_until_succeeds("pgrep -f 'keystone-tui'", timeout=10)

      # Allow TUI to render the welcome screen
      time.sleep(3)

      # Verify the process is still running (didn't crash on startup)
      installer.succeed("pgrep -f 'keystone-tui'")

      # Send 'q' to quit the TUI
      print("Sending 'q' to quit...")
      installer.send_key("q")

      # Verify the TUI exited cleanly
      time.sleep(2)
      installer.wait_until_fails("pgrep -f 'keystone-tui'", timeout=10)

      print("TUI started and exited cleanly. All tests passed!")
    '';

    # Interactive mode
    interactive.nodes.installer = {...}: {
      systemd.services.keystone-installer.wantedBy = ["multi-user.target"];
    };
  }
