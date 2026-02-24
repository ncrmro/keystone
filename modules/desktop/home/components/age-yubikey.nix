{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.ageYubikey;
in
{
  options.keystone.desktop.ageYubikey = {
    enable = mkEnableOption "age-plugin-yubikey identity file management";

    keys = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          serial = mkOption {
            type = types.str;
            description = "YubiKey serial number (from `ykman info`)";
          };
          slot = mkOption {
            type = types.int;
            default = 1;
            description = "PIV slot used for the age identity";
          };
        };
      });
      default = { };
      description = "YubiKeys to generate age identities for. Each entry produces one identity line in the combined file.";
    };

    identityPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.age/yubikey-identity.txt";
      description = "Path where the combined age-plugin-yubikey identity file is stored";
    };
  };

  config = mkIf cfg.enable {
    home.activation.ageYubikeyIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      IDENTITY_DIR="$(dirname "${cfg.identityPath}")"
      mkdir -p "$IDENTITY_DIR"
      : > "${cfg.identityPath}"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: key: ''
        # ${name}
        ${pkgs.age-plugin-yubikey}/bin/age-plugin-yubikey \
          --identity --serial ${key.serial} --slot ${toString key.slot} \
          >> "${cfg.identityPath}"
      '') cfg.keys)}
      chmod 600 "${cfg.identityPath}"
    '';

    home.sessionVariables = {
      AGE_IDENTITIES_FILE = cfg.identityPath;
    };
  };
}
