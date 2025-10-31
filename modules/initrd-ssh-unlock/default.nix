{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.initrdSshUnlock;
in {
  options.keystone.initrdSshUnlock = {
    enable = mkEnableOption "SSH access in initrd for remote disk unlocking";

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@host"];
      description = ''
        SSH public keys authorized to unlock the disk remotely.
        These keys will be used by the SSH daemon running in the initrd.
      '';
    };

    hostKey = mkOption {
      type = types.path;
      default = "/etc/ssh/initrd_ssh_host_ed25519_key";
      example = "/etc/ssh/initrd_ssh_host_ed25519_key";
      description = ''
        Path to the SSH host key for the initrd SSH daemon.
        Generate with: sudo ssh-keygen -t ed25519 -N "" -f /etc/ssh/initrd_ssh_host_ed25519_key
      '';
    };

    port = mkOption {
      type = types.port;
      default = 22;
      example = 2222;
      description = ''
        Port for the initrd SSH daemon to listen on.
        Default is 22. Change if you need to avoid conflicts.
      '';
    };

    networkModule = mkOption {
      type = types.str;
      default = "virtio_net";
      example = "r8169";
      description = ''
        Kernel module for the network card.
        Common values:
        - virtio_net: For QEMU/KVM virtual machines
        - r8169: For Realtek network cards
        - e1000e: For Intel network cards
        Find yours with: lspci -v | grep -iA8 'network\|ethernet'
      '';
    };

    dhcp = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use DHCP to obtain IP address in initrd.
        If false, you must configure a static IP via kernelParams.
      '';
    };

    kernelParams = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["ip=10.0.0.2::10.0.0.1:255.255.255.0:myhost::none"];
      description = ''
        Additional kernel parameters for network configuration.
        Only needed if DHCP is disabled.
        See: https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.authorizedKeys != [];
        message = "keystone.initrdSshUnlock.authorizedKeys must not be empty when initrd SSH unlock is enabled";
      }
    ];

    boot.initrd = {
      # Enable network and SSH in initrd
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = cfg.port;
          authorizedKeys = cfg.authorizedKeys;
          hostKeys = [cfg.hostKey];
        };
      };
      systemd.users.root.shell = "/bin/systemd-tty-ask-password-agent";

      # Network card kernel module
      availableKernelModules = [cfg.networkModule];
    };

    # Kernel parameters for network configuration
    boot.kernelParams =
      (lib.optionals cfg.dhcp ["ip=dhcp"])
      ++ cfg.kernelParams;
  };
}
