{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  terminalCfg = config.keystone.terminal;
  isDev = config.keystone.development;
  agentsLib = import ../shared/dev-script-link.nix { inherit lib; };
  repoCheckout = agentsLib.resolveRepoCheckout config "keystone";
  manifestRelPath = ".config/keystone/agent-assets.json";
  scriptRelPath = "modules/terminal/scripts/keystone-sync-agent-assets.sh";
  scriptPackage = pkgs.writeShellScriptBin "keystone-sync-agent-assets" (
    builtins.readFile ./scripts/keystone-sync-agent-assets.sh
  );
  manifestContent = builtins.toJSON {
    developmentMode = isDev;
    repoCheckout = repoCheckout;
    archetype = terminalCfg.conventions.archetype;
    resolvedCapabilities = config.keystone.terminal.aiExtensions.resolvedCapabilities or [ ];
    publishedCommands = config.keystone.terminal.aiExtensions.publishedCommands or [ ];
    repos = attrNames (config.keystone.repos or { });
  };
  syncScriptPath =
    if repoCheckout != null then
      "${repoCheckout}/${scriptRelPath}"
    else
      "${scriptPackage}/bin/keystone-sync-agent-assets";
in
{
  config = mkIf terminalCfg.enable (mkMerge [
    {
      home.file.${manifestRelPath}.text = manifestContent;
    }

    (agentsLib.mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-sync-agent-assets";
      relativePath = scriptRelPath;
      package = scriptPackage;
      runtimeInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.yq-go
      ];
    })

    (mkIf isDev {
      home.activation.keystoneSyncAgentAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.jq
            pkgs.yq-go
          ]
        }:$PATH"
        if [ -f "${syncScriptPath}" ]; then
          KEYSTONE_AGENT_ASSETS_MANIFEST="$HOME/${manifestRelPath}" \
            ${pkgs.bash}/bin/bash "${syncScriptPath}"
        else
          KEYSTONE_AGENT_ASSETS_MANIFEST="$HOME/${manifestRelPath}" \
            ${scriptPackage}/bin/keystone-sync-agent-assets
        fi
      '';
    })
  ]);
}
