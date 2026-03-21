# Keystone Notes — Home Manager module
#
# Syncs a git-backed notes repository on a timer using repo-sync.
# Designed for human users (agents use the NixOS-level keystone.os.agents.*.notes).
#
# Usage:
#   keystone.notes = {
#     enable = true;
#     repo = "git@github.com:user/notes.git";
#     zk.enable = true;  # Scaffold Zettelkasten structure
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

  # zk config.toml for Zettelkasten notebook scaffold
  zkConfigToml = ''
    [notebook]
    dir = "${cfg.path}"

    [note]
    filename = "{{id}} {{slug title}}"
    extension = "md"
    id-charset = "numbers"
    id-length = 12
    id-case = "lower"
    default-title = "Untitled"

    [note.create]
    template = "default.md"

    [group.inbox]
    paths = ["inbox"]
    [group.inbox.note]
    template = "fleeting.md"

    [group.literature]
    paths = ["literature"]
    [group.literature.note]
    template = "literature.md"

    [group.notes]
    paths = ["notes"]
    [group.notes.note]
    template = "permanent.md"

    [group.decisions]
    paths = ["decisions"]
    [group.decisions.note]
    template = "decision.md"

    [group.index]
    paths = ["index"]
    [group.index.note]
    template = "index.md"

    [format.markdown]
    link-format = "wiki"
    link-encode-path = true
    link-drop-extension = true

    [tool]
    editor = "hx"

    [lsp.diagnostics]
    wiki-title = "hint"
    dead-link = "error"

    [lsp.completion]
    note-label = "{{title}}"
    note-filter-text = "{{title}} {{id}}"
    note-detail = "{{filename}}"
  '';

  # Template for fleeting notes (inbox)
  fleetingTemplate = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: fleeting
    created: "{{format-date now 'RFC3339'}}"
    author: ""
    tags: []
    ---

    {{content}}
  '';

  # Template for literature notes
  literatureTemplate = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: literature
    created: "{{format-date now 'RFC3339'}}"
    author: ""
    tags: []
    source: ""
    ---

    ## Summary

    {{content}}

    ## Key Points

    -

    ## Relevance
  '';

  # Template for permanent notes
  permanentTemplate = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: permanent
    created: "{{format-date now 'RFC3339'}}"
    author: ""
    tags: []
    ---

    {{content}}

    ## Links
  '';

  # Template for decision records
  decisionTemplate = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: decision
    created: "{{format-date now 'RFC3339'}}"
    author: ""
    tags: []
    status: proposed
    ---

    ## Context

    {{content}}

    ## Decision

    ## Consequences

    ## Links
  '';

  # Template for index notes (Maps of Content)
  indexTemplate = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: index
    created: "{{format-date now 'RFC3339'}}"
    author: ""
    tags: []
    ---

    {{content}}

    ## Notes
  '';

  # Default template (used when no group matches)
  defaultTemplate = permanentTemplate;
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

    zk = {
      enable = lib.mkEnableOption "Zettelkasten scaffold via zk";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Notes sync (always active when notes are enabled)
      {
        systemd.user.services.keystone-notes-sync = {
          Unit = {
            Description = "Sync notes repo via repo-sync";
          };

          Service = {
            Type = "oneshot";
            ExecStart = builtins.concatStringsSep " " [
              "${pkgs.keystone.repo-sync}/bin/repo-sync"
              "--repo ${lib.escapeShellArg cfg.repo}"
              "--path ${lib.escapeShellArg cfg.path}"
              "--commit-prefix ${lib.escapeShellArg cfg.commitPrefix}"
              "--log-dir ${config.home.homeDirectory}/.local/state/notes-sync/logs"
            ];
          };
        };

        systemd.user.timers.keystone-notes-sync = {
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
      }

      # Zettelkasten scaffold (when zk is enabled)
      (lib.mkIf cfg.zk.enable {
        # Create .zk/config.toml and templates via home-manager activation
        # SECURITY: Files are written to the notes repo checkout, not Nix store,
        # so they can be committed and shared. Activation script runs at profile
        # switch time and is idempotent (mkdir -p, no clobber on existing files).
        home.activation.zkScaffold = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          notes_path=${lib.escapeShellArg cfg.path}
          zk_dir="$notes_path/.zk"
          tmpl_dir="$zk_dir/templates"

          # Create directories
          run mkdir -p "$zk_dir" "$tmpl_dir"
          run mkdir -p "$notes_path/inbox"
          run mkdir -p "$notes_path/literature"
          run mkdir -p "$notes_path/notes"
          run mkdir -p "$notes_path/decisions"
          run mkdir -p "$notes_path/index"

          # Write config (always overwrite — Nix-managed)
          run cat > "$zk_dir/config.toml" << 'ZKEOF'
          ${zkConfigToml}
          ZKEOF

          # Write templates (always overwrite — Nix-managed)
          run cat > "$tmpl_dir/default.md" << 'ZKEOF'
          ${defaultTemplate}
          ZKEOF

          run cat > "$tmpl_dir/fleeting.md" << 'ZKEOF'
          ${fleetingTemplate}
          ZKEOF

          run cat > "$tmpl_dir/literature.md" << 'ZKEOF'
          ${literatureTemplate}
          ZKEOF

          run cat > "$tmpl_dir/permanent.md" << 'ZKEOF'
          ${permanentTemplate}
          ZKEOF

          run cat > "$tmpl_dir/decision.md" << 'ZKEOF'
          ${decisionTemplate}
          ZKEOF

          run cat > "$tmpl_dir/index.md" << 'ZKEOF'
          ${indexTemplate}
          ZKEOF
        '';
      })
    ]
  );
}
