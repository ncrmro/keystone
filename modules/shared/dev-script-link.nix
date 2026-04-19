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
      pkgs,
      commandName,
      relativePath,
      package,
      runtimeInputs ? [ ],
      extraEnvSetup ? "",
      repoFlakeInput ? "keystone",
    }:
    let
      repoCheckout = resolveRepoCheckout config repoFlakeInput;
      liveScript = "${repoCheckout}/${relativePath}";
      runtimePath = lib.makeBinPath runtimeInputs;
      commandWrapper = pkgs.writeShellScript "hm_${commandName}.sh" ''
        export PATH="${runtimePath}:$PATH"
        ${extraEnvSetup}
        if [ -f "${liveScript}" ]; then
          exec ${pkgs.bash}/bin/bash "${liveScript}" "$@"
        fi

        exec "${package}/bin/${commandName}" "$@"
      '';
      # In packaged (non-dev) mode, wrap the package to embed extraEnvSetup so
      # build-time configuration (e.g. KEYSTONE_MENU_SHOW_AGENTS) is always
      # applied regardless of keystone.development. Without this wrap, env vars
      # set only in the dev-mode commandWrapper are silently absent in production,
      # causing capability-gated menu entries to fall back to their false defaults.
      packageWithEnv =
        if extraEnvSetup == "" then
          package
        else
          pkgs.writeShellScriptBin commandName ''
            ${extraEnvSetup}
            exec "${package}/bin/${commandName}" "$@"
          '';
    in
    lib.mkMerge [
      (lib.mkIf (repoCheckout == null) {
        home.packages = [ packageWithEnv ];
      })
      (lib.mkIf (repoCheckout != null) {
        home.file.".local/bin/${commandName}" = {
          source = commandWrapper;
          executable = true;
        };
      })
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
      runtimeInputs ? [ ],
      extraEnvSetup ? "",
      repoFlakeInput ? "keystone",
    }:
    let
      liveCheckout = resolveNixOSRepoCheckout config repoFlakeInput;
      liveScript = if liveCheckout != null then "${liveCheckout}/${relativePath}" else "";
      runtimePath = lib.makeBinPath runtimeInputs;
    in
    pkgs.writeShellScriptBin commandName ''
      export PATH="${runtimePath}:$PATH"
      ${extraEnvSetup}
      if [ -f "${liveScript}" ]; then
        exec ${pkgs.bash}/bin/bash "${liveScript}" "$@"
      fi

      exec ${pkgs.bash}/bin/bash "${nixStorePath}" "$@"
    '';
}
