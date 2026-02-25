{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.ageYubikey;
in
{
  options.keystone.terminal.ageYubikey = {
    enable = mkEnableOption "age-plugin-yubikey identity file management";

    identities = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Age-plugin-yubikey identity strings. Generate with:
          age-plugin-yubikey --identity
        Each string starts with "AGE-PLUGIN-YUBIKEY-".
      '';
    };

    identityPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.age/yubikey-identity.txt";
      description = "Path where the combined identity file is written";
    };
  };

  config = mkIf cfg.enable {
    home.file.".age/yubikey-identity.txt" = {
      text = concatStringsSep "\n" cfg.identities + "\n";
    };

    home.sessionVariables = {
      AGE_IDENTITIES_FILE = cfg.identityPath;
    };
  };
}
