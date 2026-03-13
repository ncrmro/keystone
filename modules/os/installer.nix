# Keystone OS Installer Module
#
# Auto-collects SSH keys from configured wheel users and hardware root keys
# to produce a bootable installer ISO with SSH access pre-configured.
#
# Keys are collected from:
# - keystone.os.users with "wheel" in extraGroups (authorizedKeys + hardwareKeys)
# - keystone.hardwareKey.rootKeys
#
# Usage (in consumer flake):
#   packages.x86_64-linux.installer-iso =
#     self.nixosConfigurations.myhost.config.keystone.os.installer.isoImage;
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
  hwKeyCfg = config.keystone.hardwareKey;
  installerCfg = osCfg.installer;

  # Resolve hardware key names to SSH public keys
  resolveHwKeys = names:
    map (name: hwKeyCfg.keys.${name}.sshPublicKey)
    (filter (name: hwKeyCfg.keys ? ${name}) names);

  # Collect keys from wheel users (authorizedKeys + resolved hardwareKeys)
  wheelUserKeys = concatLists (mapAttrsToList (_: u:
    optionals (elem "wheel" u.extraGroups)
    (u.authorizedKeys ++ resolveHwKeys u.hardwareKeys))
  osCfg.users);

  # Collect SSH public keys from hardware root keys
  rootHwKeys = optionals hwKeyCfg.enable (resolveHwKeys hwKeyCfg.rootKeys);

  # All auto-collected keys, deduplicated
  autoCollectedKeys = unique (wheelUserKeys ++ rootHwKeys);
in {
  options.keystone.os.installer = {
    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        SSH public keys for root access on the installer ISO.
        Auto-collected from wheel users and hardware root keys when not
        explicitly set.
      '';
    };

    isoImage = mkOption {
      type = types.package;
      readOnly = true;
      description = "The installer ISO image derivation with SSH keys baked in.";
    };
  };

  config = mkIf osCfg.enable {
    # Auto-collect from wheel users + hardware root keys unless overridden
    keystone.os.installer.sshKeys = mkDefault autoCollectedKeys;

    keystone.os.installer.isoImage = let
      isoSystem = import "${pkgs.path}/nixos/lib/eval-config.nix" {
        system = pkgs.stdenv.hostPlatform.system;
        modules = [
          "${pkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ../iso-installer.nix
          {
            keystone.installer.sshKeys = installerCfg.sshKeys;
            # Force kernel 6.12 — must override minimal CD default
            boot.kernelPackages = mkForce pkgs.linuxPackages_6_12;
          }
        ];
      };
    in
      isoSystem.config.system.build.isoImage;
  };
}
