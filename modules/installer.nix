# Keystone OS Installer Module
#
# Auto-collects SSH keys from configured wheel users via keystone.keys
# and hardware root keys to produce a bootable installer ISO with SSH
# access pre-configured.
#
# Keys are collected from:
# - keystone.keys.<username> for all wheel users (all host + hardware keys)
# - keystone.hardwareKey.rootKeys (hardware keys for root access)
#
# This module lives outside modules/os/ to avoid recursion: the nested ISO
# eval imports modules/os/ (for keystone.os), so if this file were inside
# modules/os/ it would re-import itself and try to build another ISO.
#
# Usage:
#   build-iso              # builds the ISO to ./installer-iso/
#   build-iso --verbose    # passes extra flags to nix build
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  hwKeyCfg = config.keystone.hardwareKey;
  keysCfg = config.keystone.keys;
  installerCfg = osCfg.installer;
  keystoneInputs = installerCfg._keystoneInputs;

  # Resolve "username/keyname" hardware key references to SSH public keys
  resolveHwKeyRef =
    ref:
    let
      parts = splitString "/" ref;
      username = elemAt parts 0;
      keyname = elemAt parts 1;
    in
    keysCfg.${username}.hardwareKeys.${keyname}.publicKey;

  # Collect keys from wheel users via keystone.keys
  wheelUserKeys = concatLists (
    mapAttrsToList (
      username: u:
      optionals (elem "wheel" u.extraGroups) (
        if keysCfg ? ${username} then keysCfg.${username}.allKeys else [ ]
      )
    ) osCfg.users
  );

  # Collect SSH public keys from hardware root keys
  rootHwKeys = optionals (hwKeyCfg.enable && hwKeyCfg.rootKeys != [ ]) (
    map resolveHwKeyRef hwKeyCfg.rootKeys
  );

  # All auto-collected keys, deduplicated
  autoCollectedKeys = unique (wheelUserKeys ++ rootHwKeys);
in
{
  options.keystone.os.installer = {
    _keystoneInputs = mkOption {
      type = types.raw;
      default = { };
      internal = true;
      description = "Keystone flake inputs for the installer's nested ISO eval. Set by the operating-system nixosModule in flake.nix.";
    };

    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        SSH public keys for root access on the installer ISO.
        Auto-collected from wheel users and hardware root keys when not
        explicitly set.
      '';
    };

    tui.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the installer ISO should include and auto-start the ks.";
    };

    isoImage = mkOption {
      type = types.package;
      readOnly = true;
      description = "The installer ISO image derivation with SSH keys baked in.";
    };

    sdImage = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        The aarch64 Raspberry Pi SD-image installer derivation with SSH keys
        baked in. Build via `build-pi-installer` or reference from a consumer
        flake to flash a ready-to-boot installer card.
      '';
    };
  };

  config = mkIf osCfg.enable {
    # Auto-collect from wheel users + hardware root keys unless overridden
    keystone.os.installer.sshKeys = mkDefault autoCollectedKeys;

    keystone.os.installer.isoImage =
      let
        isoSystem = import "${pkgs.path}/nixos/lib/eval-config.nix" {
          system = pkgs.stdenv.hostPlatform.system;
          modules = [
            "${pkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            keystoneInputs.disko.nixosModules.disko
            keystoneInputs.lanzaboote.nixosModules.lanzaboote
            keystoneInputs.home-manager.nixosModules.default
            # agenix provides the `age` option namespace — users.nix references
            # age.secrets even behind mkIf false, and NixOS checks option paths exist
            keystoneInputs.agenix.nixosModules.default
            ./domain.nix
            ./services.nix
            ./hosts.nix
            ./os
            ./iso-installer.nix
            {
              nixpkgs.overlays = [ keystoneInputs.keystoneOverlay ];
              _module.args.keystoneInputs = keystoneInputs;

              keystone.installer = {
                sshKeys = installerCfg.sshKeys;
                tui.enable = installerCfg.tui.enable;
              };

              keystone.os = {
                enable = true;
                storage.enable = false;
                secureBoot.enable = false;
                tpm.enable = false;
                services.eternalTerminal.enable = false;
                services.avahi.enable = false;
              };

              # Terminal environment for root user (helix, zsh, starship, shell tools)
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.root = {
                imports = [ ./terminal/default.nix ];
                _module.args.keystoneInputs = keystoneInputs;
                home.stateVersion = "24.11";
                keystone.terminal = {
                  enable = true;
                  ai.enable = false;
                  sandbox.enable = false;
                  git = {
                    userName = "Keystone Installer";
                    userEmail = "installer@keystone.local";
                  };
                };
                keystone.projects.enable = false;
              };

              # Force kernel 6.12 — must override minimal CD default
              boot.kernelPackages = mkForce pkgs.linuxPackages_6_12;
            }
          ];
        };
      in
      isoSystem.config.system.build.isoImage;

    # Pi SD-image installer — nested aarch64 eval, same SSH keys as the ISO.
    # Always built for aarch64-linux regardless of host arch; requires an
    # aarch64 builder or boot.binfmt.emulatedSystems = [ "aarch64-linux" ]
    # on the building host.
    keystone.os.installer.sdImage =
      let
        sdSystem = import "${pkgs.path}/nixos/lib/eval-config.nix" {
          system = "aarch64-linux";
          modules = [
            "${pkgs.path}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
            ./sd-installer.nix
            {
              nixpkgs.overlays = [ keystoneInputs.keystoneOverlay ];
              keystone.piInstaller.sshKeys = installerCfg.sshKeys;
            }
          ];
        };
      in
      sdSystem.config.system.build.sdImage;

    # System-wide build commands.
    # Uses unsafeDiscardStringContext so images aren't built during nixos-rebuild —
    # the .drv file exists from evaluation, but outputs are only realized on demand.
    environment.systemPackages =
      let
        isoDrv = builtins.unsafeDiscardStringContext installerCfg.isoImage.drvPath;
        sdDrv = builtins.unsafeDiscardStringContext installerCfg.sdImage.drvPath;
      in
      [
        (pkgs.writeShellScriptBin "build-iso" ''
          echo "Building installer ISO (${toString (length installerCfg.sshKeys)} SSH keys)..."
          nix build '${isoDrv}^*' -o installer-iso "$@"
          iso=$(find installer-iso/iso -name '*.iso' 2>/dev/null | head -1)
          if [ -n "$iso" ]; then
            echo "ISO: $iso ($(du -h "$iso" | cut -f1))"
          fi
        '')
        (pkgs.writeShellScriptBin "build-pi-installer" ''
          echo "Building Pi SD-image installer (${toString (length installerCfg.sshKeys)} SSH keys)..."
          echo "Note: requires aarch64 builder or boot.binfmt.emulatedSystems = [ \"aarch64-linux\" ]."
          nix build '${sdDrv}^*' -o pi-installer "$@"
          img=$(find pi-installer/sd-image -name '*.img.zst' 2>/dev/null | head -1)
          if [ -n "$img" ]; then
            echo "Image: $img ($(du -h "$img" | cut -f1))"
            echo "Flash: zstdcat \"$img\" | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync"
          fi
        '')
      ];
  };
}
