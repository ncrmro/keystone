# Deployment Configuration Contract
#
# This file serves as the canonical contract definition for a Keystone
# server deployment configuration. It uses NixOS module system types to
# enforce the contract at evaluation time.
{lib, ...}:
with lib; {
  # This is a contract specification, not a runnable module
  # It documents the required structure for deployment configurations

  options.deployment.contract = {
    # System architecture - REQUIRED
    # Must match target hardware platform
    system = mkOption {
      type = types.enum ["x86_64-linux" "aarch64-linux"];
      example = "x86_64-linux";
      description = ''
        Target system architecture. Must be compatible with both the
        build machine and the deployment target.
      '';
    };

    # Hostname - REQUIRED
    # Must be unique within the network
    hostname = mkOption {
      type = types.strMatching "[a-zA-Z0-9-]+";
      example = "test-server";
      description = ''
        System hostname. Used for network identification and mDNS advertisement.
        Must be valid DNS hostname (alphanumeric and hyphens only).
      '';
    };

    # Disk device - REQUIRED
    # Must point to actual disk on target system
    diskDevice = mkOption {
      type = types.str;
      example = "/dev/vda";
      description = ''
        Absolute path to the disk device for installation.

        Common values:
        - VMs (QEMU/KVM): /dev/vda
        - VMs (VirtualBox): /dev/sda
        - Physical (recommended): /dev/disk/by-id/nvme-...
        - Physical (legacy): /dev/nvme0n1 or /dev/sda

        WARNING: This disk will be completely erased during installation.
      '';
    };

    # SSH authorized keys - REQUIRED
    # At least one key must be provided for post-installation access
    sshAuthorizedKeys = mkOption {
      type = types.listOf types.str;
      example = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJl... user@workstation"
      ];
      description = ''
        List of SSH public keys authorized to access the system as root.

        At least one key is required to enable post-deployment access.
        Keys should be ed25519 or rsa format with identifying comments.
      '';
    };

    # Encrypted swap - OPTIONAL
    # Defaults to enabled
    enableEncryptedSwap = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to create an encrypted swap partition.

        Swap is encrypted with random key on each boot (no persistence).
        Useful for systems with limited RAM that need swap space.
      '';
    };

    # Swap size - OPTIONAL
    # Only relevant if enableEncryptedSwap is true
    swapSize = mkOption {
      type = types.str;
      default = "64G";
      example = "128G";
      description = ''
        Size of the encrypted swap partition.

        Common values:
        - 64G: Default, suitable for most VMs
        - 128G: Large VMs or workstations
        - 0G or disable swap: Memory-only systems
      '';
    };

    # ESP size - OPTIONAL
    # Rarely needs changing
    espSize = mkOption {
      type = types.str;
      default = "1G";
      example = "2G";
      description = ''
        Size of the EFI System Partition (ESP).

        1G is sufficient for most use cases. Only increase if using
        multiple boot entries or custom kernel images.
      '';
    };

    # Server module enable - OPTIONAL
    # Defaults to enabled in server module
    enableServerModule = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable the Keystone server module.

        Server module provides:
        - SSH server with key-only authentication
        - mDNS/Avahi for network discovery
        - Firewall with SSH access
        - Server-optimized kernel parameters
        - Administration tools (vim, git, htop, etc.)

        Should always be true for server deployments.
      '';
    };
  };

  # Contract validation assertions
  config.assertions = [
    {
      assertion = config.deployment.contract.hostname != "";
      message = "Deployment contract violation: hostname must be set";
    }
    {
      assertion = config.deployment.contract.diskDevice != "";
      message = "Deployment contract violation: diskDevice must be set";
    }
    {
      assertion = hasPrefix "/dev/" config.deployment.contract.diskDevice;
      message = "Deployment contract violation: diskDevice must be absolute path starting with /dev/";
    }
    {
      assertion = length config.deployment.contract.sshAuthorizedKeys > 0;
      message = "Deployment contract violation: at least one SSH authorized key required";
    }
    {
      assertion = elem config.deployment.contract.system ["x86_64-linux" "aarch64-linux"];
      message = "Deployment contract violation: system must be x86_64-linux or aarch64-linux";
    }
  ];
}
