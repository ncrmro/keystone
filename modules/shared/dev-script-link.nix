{ lib }:
let
  resolveRepoCheckout =
    config: repoFlakeInput:
    let
      repos = config.keystone.repos or { };
      homeDir = config.home.homeDirectory;
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
    in
    if (config.keystone.development or false) && repoEntry != null then
      "${homeDir}/.keystone/repos/${repoEntry}"
    else
      null;

  # NixOS system-level counterpart to resolveRepoCheckout.
  # Derives the live checkout path from keystone.os.users to locate the home directory.
  # Returns null when development mode is off or the repo is not registered.
  resolveNixOSRepoCheckout =
    config: repoFlakeInput:
    let
      repos = config.keystone.repos or { };
      keystoneUsers = config.keystone.os.users or { };
      userNames = lib.attrNames keystoneUsers;
      mainUserName = if userNames != [ ] then lib.head userNames else null;
      homeDir = if mainUserName != null then "/home/${mainUserName}" else null;
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
    in
    if (config.keystone.development or false) && repoEntry != null && homeDir != null then
      "${homeDir}/.keystone/repos/${repoEntry}"
    else
      null;

  mkHomeRepoFile =
    {
      config,
      targetPath,
      relativePath,
      sourcePath,
      repoFlakeInput ? "keystone",
      executable ? null,
    }:
    let
      repoCheckout = resolveRepoCheckout config repoFlakeInput;
      fileValue =
        if repoCheckout != null then
          {
            source = config.lib.file.mkOutOfStoreSymlink "${repoCheckout}/${relativePath}";
          }
        else
          {
            source = sourcePath;
          };
    in
    {
      home.file.${targetPath} =
        fileValue // lib.optionalAttrs (executable != null) { inherit executable; };
    };

  mkHomeRepoFiles =
    {
      config,
      files,
      repoFlakeInput ? "keystone",
    }:
    lib.mkMerge (
      map (
        file:
        mkHomeRepoFile (
          {
            inherit config;
            repoFlakeInput = file.repoFlakeInput or repoFlakeInput;
          }
          // file
        )
      ) files
    );
in
{
  inherit
    resolveRepoCheckout
    resolveNixOSRepoCheckout
    mkHomeRepoFile
    mkHomeRepoFiles
    ;

  mkHomeScriptCommand =
    {
      config,
      commandName,
      relativePath,
      package,
      repoFlakeInput ? "keystone",
    }:
    let
      repoCheckout = resolveRepoCheckout config repoFlakeInput;
    in
    lib.mkMerge [
      (lib.mkIf (repoCheckout == null) {
        home.packages = [ package ];
      })
      (lib.mkIf (repoCheckout != null) (mkHomeRepoFile {
        inherit config relativePath repoFlakeInput;
        targetPath = ".local/bin/${commandName}";
        sourcePath = "${package}/bin/${commandName}";
      }))
    ];

  # NixOS system-level counterpart to mkHomeScriptCommand.
  # Returns a derivation suitable for environment.systemPackages that execs the
  # script from the live checkout in dev mode, or the Nix store copy in production.
  #
  # Arguments:
  #   config        — NixOS module config
  #   pkgs          — nixpkgs
  #   commandName   — name of the resulting binary
  #   relativePath  — path relative to the repo root (e.g. "modules/os/agents/scripts/agentctl.sh")
  #   nixStorePath  — Nix path literal for the store copy (e.g. ./scripts/agentctl.sh)
  #   extraEnvSetup — optional shell lines to export env vars before exec (default "")
  #   repoFlakeInput — flake input name to resolve (default "keystone")
  mkSystemScriptPackage =
    {
      config,
      pkgs,
      commandName,
      relativePath,
      nixStorePath,
      extraEnvSetup ? "",
      repoFlakeInput ? "keystone",
    }:
    let
      liveCheckout = resolveNixOSRepoCheckout config repoFlakeInput;
      scriptPath = if liveCheckout != null then "${liveCheckout}/${relativePath}" else "${nixStorePath}";
    in
    pkgs.writeShellScriptBin commandName ''
      ${extraEnvSetup}
      exec ${pkgs.bash}/bin/bash ${scriptPath} "$@"
    '';
}
