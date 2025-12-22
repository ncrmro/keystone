# Keystone OS Mac - Remote Unlock Module
#
# SSH remote disk unlock in initrd for Apple Silicon Macs.
# No TPM fallback available - manual password entry only.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
  cfg = osCfg.remoteUnlock;

  # Collect SSH keys from users if not explicitly provided
  sshKeys =
    if cfg.authorizedKeys != []
    then cfg.authorizedKeys
    else
      flatten (
        mapAttrsToList
        (_: userCfg: userCfg.authorizedKeys)
        (filterAttrs (_: u: u.authorizedKeys != []) osCfg.users)
      );
in {
  config = mkIf (osCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = sshKeys != [];
        message = "Remote unlock requires at least one SSH key (from remoteUnlock.authorizedKeys or user config)";
      }
    ];

    boot.initrd = {
      # Network configuration in initrd
      availableKernelModules = [cfg.networkModule];
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = cfg.port;
          authorizedKeys = sshKeys;
          hostKeys = ["/etc/secrets/initrd/ssh_host_ed25519_key"];
        };
      };

      # Use DHCP if configured
      network.udhcpc.enable = cfg.dhcp;
    };

    # Generate initrd SSH host key on first boot
    system.activationScripts.initrdSshHostKey = ''
      if [ ! -f /etc/secrets/initrd/ssh_host_ed25519_key ]; then
        mkdir -p /etc/secrets/initrd
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/secrets/initrd/ssh_host_ed25519_key -N "" -C "initrd"
        chmod 600 /etc/secrets/initrd/ssh_host_ed25519_key
      fi
    '';
  };
}
