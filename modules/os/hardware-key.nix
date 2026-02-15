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
