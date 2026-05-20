# Keystone Notes — Home Manager module  [EXPERIMENTAL]
#
# EXPERIMENTAL: This module is not part of the stable v1 surface.
# It may change significantly or be restructured in future releases.
#
# Declares the canonical notes path and optionally initializes a zk
# Zettelkasten notebook structure. Used by both human users and agents.
#
# See conventions/tool.zk.md
# See conventions/process.knowledge-management.md
# Implements REQ-009
# See specs/REQ-018-repo-management/requirements.md
#
# Usage:
#   keystone.notes = {
#     enable = true;
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
  imports = [ ../shared/experimental.nix ];

  options.keystone.notes = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.keystone.experimental;
      description = "Enable Keystone notes module (EXPERIMENTAL). Auto-enabled when keystone.experimental = true.";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/notes";
      description = "Local checkout path for the notes repo.";
    };

    zk = {
      enable = lib.mkEnableOption "zk Zettelkasten notebook initialization";
    };
  };

  config = lib.mkIf cfg.enable {
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
