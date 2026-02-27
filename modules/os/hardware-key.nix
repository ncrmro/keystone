# Keystone OS Hardware Key Module
#
# Enables FIDO2/YubiKey integration for system authentication.
# Provides support for:
# - GPG/SSH agent with hardware key support
# - age-plugin-yubikey for agenix secrets
#
# TODO: Physical touch for sudo authentication (PAM U2F)
# TODO: LUKS disk encryption enrollment (slot configuration)
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.hardwareKey;
in {
  options.keystone.hardwareKey = {
    enable = mkEnableOption "Hardware key (FIDO2/YubiKey) system integration";

    keys = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable description of this hardware key";
            example = "Primary YubiKey (USB-A, black)";
          };

          sshPublicKey = mkOption {
            type = types.str;
            description = "SSH public key for this hardware key (e.g., sk-ssh-ed25519 or sk-ecdsa-sha2-nistp256)";
            example = "sk-ssh-ed25519@openssh.com AAAAGnNr... user@host";
          };

          ageIdentity = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "age-plugin-yubikey identity string for age encryption/decryption";
            example = "AGE-PLUGIN-YUBIKEY-...";
          };
        };
      });
      default = {};
      description = ''
        Named hardware keys with their SSH and age key material.
        Declare once, reference by name from users and rootKeys.
      '';
    };

    rootKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Names of hardware keys (from keys.<name>) whose SSH public keys
        should be added to root's authorized_keys.
      '';
      example = ["yubi-black"];
    };

    # TODO: LUKS support
    # luksSlot = mkOption {
    #   type = types.int;
    #   default = 2;
    #   description = "LUKS keyslot to use for hardware key enrollment";
    # };

    # TODO: Sudo touch authentication
    # sudoTouchAuth = mkEnableOption "Require physical touch on hardware key for sudo";

    gpgAgent = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GPG agent with SSH support for hardware key authentication";
      };

      enableSSHSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SSH support through GPG agent (use hardware key for SSH)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Validate rootKeys references exist in keys
    assertions = map (name: {
      assertion = cfg.keys ? ${name};
      message = "keystone.hardwareKey.rootKeys references '${name}' but no such key exists in keystone.hardwareKey.keys";
    }) cfg.rootKeys;

    # Wire hardware key SSH keys into root's authorized_keys
    users.users.root.openssh.authorizedKeys.keys =
      map (name: cfg.keys.${name}.sshPublicKey) cfg.rootKeys;

    # TODO: LUKS slot assertion
    # assertions = [
    #   {
    #     assertion = cfg.luksSlot >= 0 && cfg.luksSlot <= 7;
    #     message = "LUKS keyslot must be in the range 0-7";
    #   }
    # ];

    # Enable smart card daemon for hardware key communication
    services.pcscd.enable = true;

    # Enable udev rules for YubiKey
    hardware.gpgSmartcards.enable = true;

    # TODO: PAM U2F authentication for sudo
    # security.pam.services.sudo.u2fAuth = cfg.sudoTouchAuth;

    # Required packages for hardware key management
    environment.systemPackages = with pkgs; [
      yubikey-manager         # ykman CLI for YubiKey configuration
      age-plugin-yubikey      # age encryption with YubiKey (for agenix)
      pam_u2f                 # PAM module for FIDO2 authentication
      yubico-piv-tool         # PIV operations
      yubikey-personalization # Personalization tools
    ];

    # GPG agent with optional SSH support
    programs.gnupg.agent = mkIf cfg.gpgAgent.enable {
      enable = true;
      enableSSHSupport = cfg.gpgAgent.enableSSHSupport;
    };
  };
}
