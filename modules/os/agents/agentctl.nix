# agentctl: unified CLI for managing agent services and mail.
# Dispatches to the per-agent Nix store helper via sudo (no SETENV needed).
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg cfg topDomain;
  inherit (agentsLib) globalAgentVncPort agentSvcHelper;
in
{
  config = mkIf (osCfg.enable && cfg != { }) {
    environment.systemPackages =
      let
        agentOllamaConfig =
          name:
          let
            username = "agent-${name}";
            userCfg =
              if config ? home-manager && builtins.hasAttr username config.home-manager.users then
                config.home-manager.users.${username}.keystone.terminal.ai.ollama
              else
                {
                  enable = false;
                  host = "http://localhost:11434";
                  defaultModel = null;
                };
          in
          userCfg;
        # Nix-generated static lookup: agent name -> helper store path
        agentHelperCases = concatStringsSep "\n" (
          mapAttrsToList (name: _: "          ${name}) HELPER=\"${agentSvcHelper name}\" ;;") cfg
        );
        # Nix-generated static lookup: agent name -> notes directory path
        agentNotesCases = concatStringsSep "\n" (
          mapAttrsToList (name: agentCfg: "          ${name}) NOTES_DIR=\"${agentCfg.notes.path}\" ;;") cfg
        );
        # Nix-generated static lookup: agent name -> VNC port (all agents, for remote VNC)
        agentVncCases = concatStringsSep "\n" (
          mapAttrsToList (
            name: agentCfg: "          ${name}) VNC_PORT=\"${toString (globalAgentVncPort name agentCfg)}\" ;;"
          ) cfg
        );
        # Nix-generated static lookup: agent name -> host (for remote dispatch)
        agentHostCases = concatStringsSep "\n" (
          mapAttrsToList (
            name: agentCfg: "          ${name}) AGENT_HOST=\"${toString agentCfg.host}\" ;;"
          ) cfg
        );
        agentOllamaCases = concatStringsSep "\n" (
          mapAttrsToList (
            name: _:
            let
              ollamaCfg = agentOllamaConfig name;
              defaultModel = if ollamaCfg.defaultModel != null then ollamaCfg.defaultModel else "";
            in
            ''
              ${name}) OLLAMA_ENABLED="${boolToString ollamaCfg.enable}"; OLLAMA_HOST="${ollamaCfg.host}"; OLLAMA_DEFAULT_MODEL="${defaultModel}" ;;
            ''
          ) cfg
        );
        # Nix-generated static lookup: agent name -> provision metadata
        # Bakes agent host, mail.provision flag, and mail server host into the script.
        mailHost =
          if config.keystone.services.mail.host != null then config.keystone.services.mail.host else "";
        agentProvisionCases = concatStringsSep "\n" (
          mapAttrsToList (
            name: agentCfg:
            "          ${name}) PROVISION_AGENT_HOST=\"${toString agentCfg.host}\"; MAIL_PROVISION=${boolToString agentCfg.mail.provision} ;;"
          ) cfg
        );
        knownAgents = concatStringsSep ", " (attrNames cfg);

        tasksFormatter = ./scripts/tasks-formatter.py;

        agentctl = pkgs.writeShellScriptBin "agentctl" (
          builtins.readFile (
            pkgs.replaceVars ./scripts/agentctl.sh {
              agentHelperCases = agentHelperCases;
              agentNotesCases = agentNotesCases;
              agentVncCases = agentVncCases;
              agentHostCases = agentHostCases;
              agentOllamaCases = agentOllamaCases;
              agentProvisionCases = agentProvisionCases;
              knownAgents = knownAgents;
              python3 = "${pkgs.python3}/bin/python3";
              tasksFormatter = "${tasksFormatter}";
              openssh = "${pkgs.openssh}";
              virtViewer = "${pkgs.virt-viewer}";
              yqBin = "${pkgs.yq-go}/bin/yq";
              inherit topDomain mailHost;
              openssl = "${pkgs.openssl}";
              coreutils = "${pkgs.coreutils}";
              gnugrep = "${pkgs.gnugrep}";
              gnused = "${pkgs.gnused}";
              nix = "${pkgs.nix}";
              zellij = "${pkgs.zellij}/bin/zellij";
              podmanAgent = "${pkgs.keystone.podman-agent}/bin/podman-agent";
            }
          )
        );

        # Per-agent wrapper scripts: `drago claude` = `agentctl drago claude`
        agentAliases = mapAttrsToList (
          name: _:
          pkgs.writeShellScriptBin name ''
            exec agentctl "${name}" "$@"
          ''
        ) cfg;
      in
      [ agentctl ] ++ agentAliases;

  };
}
