{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.client.services.system;
in
{
  options.keystone.client.services.system = {
    enable = mkEnableOption "System services and configuration";
  };

  config = mkIf cfg.enable {
    # Enable CUPS for printing
    services.printing.enable = true;

    # Enable locate service for file searching
    services.locate = {
      enable = true;
      package = pkgs.mlocate;
      localuser = null; # Allow all users to access locate database
    };

    # Enable automatic garbage collection
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    # Enable flakes and new nix command
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Allow unfree packages (for some hardware drivers)
    nixpkgs.config.allowUnfree = true;

    # Create /bin/bash symlink for script compatibility
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    ];

    # System-wide shell aliases and environment
    environment.shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      grep = "grep --color=auto";
    };

    # Enable command-not-found
    programs.command-not-found.enable = true;

    # Enable direnv for development environments
    programs.direnv.enable = true;
  };
}
