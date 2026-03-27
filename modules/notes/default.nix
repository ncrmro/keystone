# Keystone Notes — Home Manager module
#
# Syncs a git-backed notes repository on a timer using repo-sync.
# Optionally initializes a zk Zettelkasten notebook structure.
# Used by both human users and agents.
#
# See conventions/tool.zk.md
# See conventions/process.knowledge-management.md
# Implements REQ-009
# See specs/REQ-018-repo-management/requirements.md
#
# Usage:
#   keystone.notes = {
#     enable = true;
#     repo = "git@github.com:user/notes.git";
#     zk.enable = true;
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.keystone.notes;
  sshAuthSock =
    if
      lib.hasAttrByPath [
        "keystone"
        "terminal"
        "ssh"
        "authSock"
      ] config
    then
      config.keystone.terminal.ssh.authSock
    else
      "%t/ssh-agent";

  # Canonical .zk/config.toml content for the Zettelkasten notebook.
  # This is written to the notes repo (not /nix/store) so it travels with git.
  zkConfigToml = ''
    [note]
    id = "{{format-date now '%Y%m%d%H%M'}}"
    filename = "{{id}} {{slug title}}"
    extension = "md"

    [format.markdown]
    link-format = "wiki"
    hashtags = true

    [group.fleeting]
    paths = ["inbox"]
    [group.fleeting.note]
    template = "fleeting.md"

    [group.literature]
    paths = ["literature"]
    [group.literature.note]
    template = "literature.md"

    [group.permanent]
    paths = ["notes"]
    [group.permanent.note]
    template = "permanent.md"

    [group.decision]
    paths = ["decisions"]
    [group.decision.note]
    template = "decision.md"

    [group.index]
    paths = ["index"]
    [group.index.note]
    template = "index.md"

    [lsp.diagnostics]
    wiki-title = "hint"
    dead-link = "error"
  '';

  notesGitignore = ''
    # zk local index state
    .zk/notebook.db
    .zk/notebook.db-journal

    # Local shell and environment state
    .direnv/
    .env
    .env.local
    .venv/
    __pycache__/

    # Nix local outputs
    result
    result-*

    # OS/editor junk
    .DS_Store
    Thumbs.db
  '';

  # Template: fleeting note
  templateFleeting = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: fleeting
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    tags: []
    ---

    # {{title}}

    {{content}}
  '';

  # Template: literature note
  templateLiterature = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: literature
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    source: ""
    source_url: ""
    tags: []
    ---

    # {{title}}

    ## Summary



    ## Key Points

    -

    ## Links

    -
  '';

  # Template: permanent note
  templatePermanent = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: permanent
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    tags: []
    ---

    # {{title}}



    ## Links

    -
  '';

  # Template: decision record
  templateDecision = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: decision
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    status: proposed
    supersedes: ""
    tags: [decision]
    ---

    # {{title}}

    ## Context



    ## Decision



    ## Consequences



    ## Links

    -
  '';

  # Template: index note (Map of Content)
  templateIndex = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: index
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    tags: [index]
    ---

    # {{title}}

    ## Notes

    -
  '';

  # Scaffold script: creates .zk/ structure if absent
  zkScaffoldScript = pkgs.writeShellScript "zk-scaffold" ''
    NOTES_PATH="${cfg.path}"

    if [ ! -d "$NOTES_PATH/.zk" ]; then
      echo "Scaffolding zk notebook at $NOTES_PATH"

      # Initialize zk (creates .zk/ directory)
      ${pkgs.zk}/bin/zk init --no-input "$NOTES_PATH"

      # Write canonical config
      cat > "$NOTES_PATH/.zk/config.toml" << 'ZKEOF'
    ${zkConfigToml}
    ZKEOF

      cat > "$NOTES_PATH/.gitignore" << 'IGNOREEOF'
    ${notesGitignore}
    IGNOREEOF

      # Create template directory and files
      mkdir -p "$NOTES_PATH/.zk/templates"

      cat > "$NOTES_PATH/.zk/templates/fleeting.md" << 'TPLEOF'
    ${templateFleeting}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/literature.md" << 'TPLEOF'
    ${templateLiterature}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/permanent.md" << 'TPLEOF'
    ${templatePermanent}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/decision.md" << 'TPLEOF'
    ${templateDecision}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/index.md" << 'TPLEOF'
    ${templateIndex}
    TPLEOF

      # Create note directories with .gitkeep
      for dir in inbox literature notes decisions index; do
        mkdir -p "$NOTES_PATH/$dir"
        touch "$NOTES_PATH/$dir/.gitkeep"
      done

      echo "zk notebook scaffolded successfully"
    else
      echo "zk notebook already exists at $NOTES_PATH/.zk — skipping scaffold"
    fi

    # Fix permissions for agent-admins group access (setgid + group-writable)
    if [ -d "$NOTES_PATH/.zk" ]; then
      chmod -R g+w "$NOTES_PATH/.zk"
      chmod g+s "$NOTES_PATH/.zk"
    fi
  '';
in
{
  options.keystone.notes = {
    enable = lib.mkEnableOption "Keystone notes sync";

    repo = lib.mkOption {
      type = lib.types.str;
      description = "Git repository URL for the notes repo.";
      example = "git@github.com:user/notes.git";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/notes";
      description = "Local checkout path for the notes repo.";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/5";
      description = "Systemd calendar spec for the sync timer. Default: every 5 minutes.";
    };

    commitPrefix = lib.mkOption {
      type = lib.types.str;
      default = "vault sync";
      description = "Commit message prefix used by repo-sync.";
    };

    sync = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the systemd sync service and timer. Disable when another mechanism handles sync (e.g. NixOS-level agent sync).";
      };
    };

    zk = {
      enable = lib.mkEnableOption "zk Zettelkasten notebook initialization";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.keystone-notes-sync = lib.mkIf cfg.sync.enable {
      Unit = {
        Description = "Sync notes repo via repo-sync";
      };

      Service = {
        Type = "oneshot";
        Environment = [
          "SSH_AUTH_SOCK=${sshAuthSock}"
        ];
        ExecStart = builtins.concatStringsSep " " [
          "${pkgs.keystone.repo-sync}/bin/repo-sync"
          "--repo ${lib.escapeShellArg cfg.repo}"
          "--path ${lib.escapeShellArg cfg.path}"
          "--commit-prefix ${lib.escapeShellArg cfg.commitPrefix}"
          "--log-dir ${config.home.homeDirectory}/.local/state/notes-sync/logs"
        ];
        ExecStartPost = "${pkgs.bash}/bin/bash -lc 'if command -v pz >/dev/null 2>&1; then pz export-menu-cache --write-state >/dev/null 2>&1 || true; fi'";
      };
    };

    systemd.user.timers.keystone-notes-sync = lib.mkIf cfg.sync.enable {
      Unit = {
        Description = "Timer for notes repo sync";
      };

      Timer = {
        OnCalendar = cfg.syncInterval;
        Persistent = true;
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };

    # Scaffold zk notebook structure on activation (if enabled and not already present)
    home.activation.zkScaffold = lib.mkIf cfg.zk.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Only scaffold if the notes repo directory exists (it may not be cloned yet)
        if [ -d "${cfg.path}" ]; then
          ${zkScaffoldScript}
        fi
      ''
    );
  };
}
