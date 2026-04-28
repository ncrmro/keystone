{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
with lib;
let
  terminalCfg = config.keystone.terminal;
  isDev = config.keystone.development;
  isAgent = lib.hasPrefix "agent-" config.home.username;
  devScripts = import ../shared/dev-script-link.nix { inherit lib; };
  repoCheckout = if isAgent then null else devScripts.resolveRepoCheckout config "keystone";
  # agentsLib reads `config.keystone.os.*`, so it must be constructed with the
  # NixOS config (osConfig), not the home-manager config tree.
  agentsLib =
    if osConfig != null then
      import ../os/agents/lib.nix {
        inherit lib pkgs;
        config = osConfig;
      }
    else
      null;
  # `keystone.os.agents` is a NixOS-level option, not a home-manager option,
  # so reading it from `config` always returned { } here and the manifest
  # never reflected the host's agent set. Bridge via `osConfig` (the standard
  # home-manager pattern, used elsewhere in keystone for keystone.development
  # and keystone.repos) so the generated agent-assets.json matches reality.
  osAgents =
    if osConfig != null && osConfig.keystone ? os && osConfig.keystone.os ? agents then
      osConfig.keystone.os.agents
    else
      { };
  manifestRelPath = ".config/keystone/agent-assets.json";
  scriptRelPath = "modules/terminal/scripts/keystone-sync-agent-assets.sh";
  scriptPackage = pkgs.writeShellScriptBin "keystone-sync-agent-assets" (
    builtins.readFile ./scripts/keystone-sync-agent-assets.sh
  );
  agentsWithMcp = mapAttrs (name: agentCfg: {
    inherit (agentCfg) host archetype;
    notesPath = agentCfg.notes.path;
    mcpServers = {
      deepwork = {
        command = "${pkgs.keystone.deepwork}/bin/deepwork";
        args = [
          "serve"
          "--path"
          "."
          "--platform"
          "claude"
        ];
      };
    }
    // optionalAttrs (agentCfg.chrome.enable && agentCfg.chrome.mcp.enable) {
      chrome-devtools = {
        command = "${pkgs.keystone.chrome-devtools-mcp}/bin/chrome-devtools-mcp";
        args = [
          "--browserUrl"
          "http://127.0.0.1:${toString (agentsLib.globalAgentChromeDebugPort name agentCfg)}"
        ];
      };
    };
  }) osAgents;
  manifestContent = builtins.toJSON {
    developmentMode = isDev;
    repoCheckout = repoCheckout;
    fallbackConventionsDir = ../../conventions;
    fallbackTemplatesDir = ./agent-assets;
    archetype = terminalCfg.conventions.archetype;
    resolvedCapabilities = config.keystone.terminal.aiExtensions.resolvedCapabilities or [ ];
    publishedCommands = config.keystone.terminal.aiExtensions.publishedCommands or [ ];
    repos = attrNames (config.keystone.repos or { });
    agents = agentsWithMcp;
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

    (devScripts.mkHomeScriptCommand {
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

    (mkIf (isDev && !isAgent) {
      home.activation.keystoneSyncAgentAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.git
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
