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
  # Consumer-flake agent-assets root. Skills/subagents are materialized here
  # by `ks sync-agent-assets`; home-manager activation symlinks each tool's
  # home-dir subdir into the corresponding path. See
  # conventions/tool.cli-coding-agents.md § "Consumer Flake Agent Assets".
  consumerFlakeAgents =
    if
      osConfig != null && osConfig.keystone ? systemFlake && osConfig.keystone.systemFlake.path != null
    then
      "${osConfig.keystone.systemFlake.path}/agents"
    else
      null;
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
    consumerFlakeAgents = consumerFlakeAgents;
  };
  # Tool subdirs the activation script links into the user's home dir.
  # Each tuple is `(tool, subdir, home-dir-path)`; the link is
  # `$HOME/<home-dir-path>/<subdir>` → `<consumerFlakeAgents>/<tool>/<subdir>`.
  toolSymlinks = [
    {
      tool = "claude";
      subdir = "skills";
      homePath = ".claude";
    }
    {
      tool = "claude";
      subdir = "agents";
      homePath = ".claude";
    }
    {
      tool = "gemini";
      subdir = "skills";
      homePath = ".gemini";
    }
    {
      tool = "codex";
      subdir = "skills";
      homePath = ".codex";
    }
  ];
  toolSymlinkShellPairs = concatStringsSep " " (
    map (s: "${s.tool}:${s.subdir}:${s.homePath}") toolSymlinks
  );
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

    # Symlink each tool's home-dir agent-asset subdir (e.g. ~/.claude/skills)
    # at the consumer flake's `agents/<tool>/<subdir>/` path. Runs for both
    # admin and OS agent users — the L1→L2 inheritance contract in
    # conventions/tool.cli-coding-agents.md rule 18. The actual *content*
    # under that path is written by `ks sync-agent-assets` (manual), not by
    # this activation. Activation never modifies file content; it only
    # ensures the symlink topology is correct.
    {
      home.activation.keystoneAgentAssetSymlinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${
          lib.makeBinPath [
            pkgs.coreutils
          ]
        }:$PATH"

        # Resolve consumer-flake agents root at runtime. Prefer the runtime
        # symlink (survives Nix evaluation, follows the active system flake)
        # so re-evaluating with a different flake doesn't strand the symlinks.
        consumer_flake=""
        if [ -L /run/current-system/keystone-system-flake ]; then
          consumer_flake="$(readlink -f /run/current-system/keystone-system-flake 2>/dev/null || true)"
        fi
        if [ -z "$consumer_flake" ]; then
          # Fall back to the Nix-eval-time value if available.
          ${
            if consumerFlakeAgents != null then
              ''consumer_flake="${osConfig.keystone.systemFlake.path}"''
            else
              ''consumer_flake=""''
          }
        fi
        if [ -z "$consumer_flake" ]; then
          echo "keystone-agent-asset-symlinks: keystone.systemFlake.path is unset and /run/current-system/keystone-system-flake is missing; skipping symlink activation" >&2
          exit 0
        fi
        agents_root="$consumer_flake/agents"

        is_agent_user=${if isAgent then "1" else "0"}

        for entry in ${toolSymlinkShellPairs}; do
          tool="''${entry%%:*}"
          rest="''${entry#*:}"
          subdir="''${rest%%:*}"
          home_path="''${rest##*:}"

          target="$agents_root/$tool/$subdir"
          link="$HOME/$home_path/$subdir"

          # Admin pre-creates the consumer-flake target dir so agents (which
          # cannot write inside the admin's home) find it ready. Agents skip
          # this step and just install their symlink at their own home.
          if [ "$is_agent_user" = "0" ]; then
            mkdir -p "$target"
          elif [ ! -d "$target" ]; then
            echo "keystone-agent-asset-symlinks: consumer-flake target $target does not exist yet; skipping $link (admin should run home-manager activation first)" >&2
            continue
          fi

          # Ensure the parent of the link exists (~/.claude, ~/.gemini, ~/.codex).
          mkdir -p "$HOME/$home_path"

          if [ -L "$link" ]; then
            current="$(readlink "$link")"
            if [ "$current" = "$target" ]; then
              continue
            fi
            rm -f "$link"
          elif [ -d "$link" ]; then
            if [ -z "$(ls -A "$link" 2>/dev/null)" ]; then
              rmdir "$link"
            else
              echo "keystone-agent-asset-symlinks: refusing to replace non-empty directory $link with symlink to $target" >&2
              echo "  Move or remove the existing directory, then re-run home-manager activation." >&2
              continue
            fi
          elif [ -e "$link" ]; then
            echo "keystone-agent-asset-symlinks: $link exists and is not a directory or symlink; leaving untouched" >&2
            continue
          fi

          ln -s "$target" "$link"
        done
      '';
    }
  ]);
}
