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
    environment.systemPackages = let
      # Nix-generated static lookup: agent name -> helper store path
      agentHelperCases = concatStringsSep "\n" (mapAttrsToList (name: _:
        "          ${name}) HELPER=\"${agentSvcHelper name}\" ;;"
      ) cfg);
      # Nix-generated static lookup: agent name -> notes directory path
      agentNotesCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
        "          ${name}) NOTES_DIR=\"${agentCfg.notes.path}\" ;;"
      ) cfg);
      # Nix-generated static lookup: agent name -> VNC port (all agents, for remote VNC)
      agentVncCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
        "          ${name}) VNC_PORT=\"${toString (globalAgentVncPort name agentCfg)}\" ;;"
      ) cfg);
      # Nix-generated static lookup: agent name -> host (for remote dispatch)
      agentHostCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
        "          ${name}) AGENT_HOST=\"${toString agentCfg.host}\" ;;"
      ) cfg);
      # Nix-generated static lookup: agent name -> provision metadata
      # Bakes agent host, mail.provision flag, and mail server host into the script.
      mailHost = if config.keystone.services.mail.host != null then config.keystone.services.mail.host else "";
      agentProvisionCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
        "          ${name}) PROVISION_AGENT_HOST=\"${toString agentCfg.host}\"; MAIL_PROVISION=${boolToString agentCfg.mail.provision} ;;"
      ) cfg);
      knownAgents = concatStringsSep ", " (attrNames cfg);

      # Render TASKS.yaml as a sorted table (pending/in_progress first, completed last)
      tasksFormatter = pkgs.writeText "agentctl-tasks-formatter.py" ''
        import sys, re

        lines = sys.stdin.read()

        tasks = []
        current = {}
        in_tasks = False
        for line in lines.splitlines():
            if line.strip() == "tasks:":
                in_tasks = True
                continue
            if not in_tasks:
                continue
            m = re.match(r"^\s+-\s+([\w_]+):\s*(.*)", line)
            if m:
                if current:
                    tasks.append(current)
                current = {m.group(1): m.group(2).strip().strip('"').strip("'")}
                continue
            m = re.match(r"^\s+([\w_]+):\s*(.*)", line)
            if m:
                current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
        if current:
            tasks.append(current)

        if not tasks:
            print("No tasks found.")
            sys.exit(0)

        # Active tasks first, then completed in reverse order (latest first)
        order = {"in_progress": 0, "pending": 1, "blocked": 2, "error": 3, "completed": 4}
        for i, t in enumerate(tasks):
            t["_orig_idx"] = i
        tasks.sort(key=lambda t: (order.get(t.get("status", ""), 5), -t["_orig_idx"]))

        icons = {"completed": "done", "in_progress": "run ", "pending": "wait", "blocked": "blkd", "error": "err "}

        hdr = ["#", "STATUS", "NAME", "PROJECT", "SOURCE", "MODEL", "DESCRIPTION"]
        rows = []
        for i, t in enumerate(tasks):
            rows.append([
                str(i + 1),
                icons.get(t.get("status", ""), t.get("status", "")[:4]),
                t.get("name", "")[:30],
                t.get("project", "-")[:15],
                t.get("source", "-")[:10],
                t.get("model", "-")[:6],
                t.get("description", "")[:50],
            ])

        widths = [len(h) for h in hdr]
        for row in rows:
            for j, cell in enumerate(row):
                widths[j] = max(widths[j], len(cell))

        def fmt(row):
            return "  ".join(cell.ljust(widths[j]) for j, cell in enumerate(row))

        print(fmt(hdr))
        print("  ".join("-" * w for w in widths))
        for row in rows:
            print(fmt(row))
      '';

      agentctl = pkgs.writeShellScriptBin "agentctl" (builtins.readFile (pkgs.replaceVars ./scripts/agentctl.sh {
        agentHelperCases = agentHelperCases;
        agentNotesCases = agentNotesCases;
        agentVncCases = agentVncCases;
        agentHostCases = agentHostCases;
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
      }));

      # Per-agent wrapper scripts: `drago claude` = `agentctl drago claude`
      agentAliases = mapAttrsToList (name: _:
        pkgs.writeShellScriptBin name ''
          exec agentctl "${name}" "$@"
        ''
      ) cfg;
    in [ agentctl ] ++ agentAliases;

  };
}
