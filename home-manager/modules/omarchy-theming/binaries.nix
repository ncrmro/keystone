{ config, lib, pkgs, ... }:

let
  cfg = config.programs.omarchy-theming;
  
  # Discover all binaries in the omarchy bin directory
  omarchyBinaries = builtins.attrNames (builtins.readDir "${cfg.package}/bin");
  
  # Generate home.file entries for each binary
  binaryFiles = builtins.listToAttrs (
    map (binFile: {
      name = ".local/share/omarchy/bin/${binFile}";
      value = {
        source = "${cfg.package}/bin/${binFile}";
        executable = true;
      };
    }) omarchyBinaries
  );
in
{
  config = lib.mkIf cfg.enable {
    # Install all omarchy binaries to ~/.local/share/omarchy/bin/
    home.file = binaryFiles;

    # Add omarchy bin directory to PATH
    home.sessionPath = [
      "${config.home.homeDirectory}/.local/share/omarchy/bin"
    ];
  };
}
