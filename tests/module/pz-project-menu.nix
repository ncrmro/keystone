{
  pkgs,
  lib,
}:
let
  lua = pkgs.lua5_4.withPackages (
    ps: with ps; [
      dkjson
    ]
  );
in
pkgs.runCommand "test-pz-project-menu"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      jq
      lua
      yq-go
      zsh
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_STATE_HOME="$PWD/state"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    # pz resolves the consumer flake from the canonical path
    # $HOME/.keystone/repos/$USER/keystone-config; override $USER too so
    # the harness controls the lookup without a pointer-file or env-var.
    export USER="ncrmro"
    NIXOS_CONFIG_DIR="$HOME/.keystone/repos/ncrmro/keystone-config"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        lua
        pkgs.yq-go
        pkgs.zsh
      ]
    }"
    export VAULT_ROOT="$HOME/notes"

    mkdir -p "$HOME" "$HOME/.local/bin" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$VAULT_ROOT" "$PWD/bin"
    mkdir -p "$NIXOS_CONFIG_DIR"

    cat > "$NIXOS_CONFIG_DIR/hosts.nix" <<'EOF'
    {
      devbox = {
        hostname = "devbox";
        sshTarget = "devbox";
      };
    }
    EOF

    cat > "$PWD/bin/pz" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/packages/pz/pz.sh" "$@"
    EOF
    chmod +x "$PWD/bin/pz"

    cat > "$PWD/bin/keystone-project-menu" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/desktop/home/scripts/keystone-project-menu.sh" "$@"
    EOF
    chmod +x "$PWD/bin/keystone-project-menu"
    ln -s "$PWD/bin/keystone-project-menu" "$HOME/.local/bin/keystone-project-menu"

    cat > "$NIXOS_CONFIG_DIR/projects.yaml" <<'EOF'
    keystone:
      mission: "Build Keystone tooling."
      repos:
        - ncrmro/keystone
      milestones:
        - name: "Fix pz completion"
          date: "2026-04-01"
    agents:
      mission: "Coordinate agent workflows."
      repos:
        - ncrmro/keystone
    EOF

    cat > "$PWD/bin/zellij" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "''${1:-}" == "list-sessions" ]]; then
      cat <<'SESSIONS'
    keystone [Created 00:00]
    agents-review [Created 00:00] (current)
    SESSIONS
      exit 0
    fi

    printf 'unexpected zellij args: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/zellij"

    cat > "$PWD/bin/git" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "''${1:-}" == "rev-parse" && "''${2:-}" == "--show-toplevel" ]]; then
      printf '%s\n' "$REPO_ROOT"
      exit 0
    fi

    printf 'unexpected git args: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/git"

    cat > "$PWD/bin/nix" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "''${1:-}" == "eval" ]]; then
      cat <<'JSON'
    [
      {
        "configName": "devbox",
        "hostname": "devbox",
        "sshTarget": "devbox",
        "fallbackIP": null
      }
    ]
    JSON
      exit 0
    fi

    printf 'unexpected nix args: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/nix"

    cat > "$PWD/bin/hostname" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' 'devbox'
    EOF
    chmod +x "$PWD/bin/hostname"

    ${pkgs.bash}/bin/bash -lc '
      source <(pz completion)
      complete -p pz | grep -F "_pz_completion"
    '

    ${pkgs.zsh}/bin/zsh -lc '
      autoload -Uz compinit
      compinit
      source =(pz completion)
      whence -w _pz_completion | grep -F "function"
    '

    ${pkgs.zsh}/bin/zsh -lc '
      autoload -Uz compinit
      compinit
      source =(pz completion)
      setopt KSH_ARRAYS

      typeset -ga captured
      captured=()
      compadd() {
        local item
        for item in "$@"; do
          [[ "$item" == "--" ]] && continue
          captured+=("$item")
        done
      }

      words=(pz agents re)
      CURRENT=3
      _pz_completion
      print -l -- "''${captured[@]}" | grep -Fx "review"
      print -l -- "''${captured[@]}" | grep -Fx "new"
      ! print -l -- "''${captured[@]}" | grep -Fx "list"
      ! print -l -- "''${captured[@]}" | grep -Fx "agent"
      ! print -l -- "''${captured[@]}" | grep -Fx "info"
      ! print -l -- "''${captured[@]}" | grep -Fx "completion"
    '

    projects_json="$(keystone-project-menu projects-json)"
    printf '%s\n' "$projects_json" | jq -e '
      length == 2
      and .[0].Text == "keystone"
      and .[0].Subtext == "1 session active"
      and .[1].Text == "agents"
      and .[1].Subtext == "1 session active"
    ' >/dev/null

    keystone-project-menu set-current-project keystone
    current_project="$(keystone-project-menu get-current-project)"
    [[ "$current_project" == "keystone" ]]

    details_json="$(keystone-project-menu project-details-json keystone)"
    printf '%s\n' "$details_json" | jq -e '
      map(.Text) as $texts
      | ($texts | index("Open main session")) != null
      and ($texts | index("New session")) != null
      and ($texts | index("Notes")) != null
    ' >/dev/null

    cat > "$PWD/check-project-details.lua" <<'EOF'
    local json = require("dkjson")

    function jsonDecode(value)
      return json.decode(value)
    end

    function lastMenuValue(name)
      return ""
    end

    dofile(os.getenv("REPO_ROOT") .. "/modules/desktop/home/components/keystone-project-details.lua")

    local entries = GetEntries()
    local current = io.popen("keystone-project-menu get-current-project"):read("*l") or ""
    assert(type(entries) == "table", "details entries must decode to a table")
    assert(#entries >= 3, "details menu should expose action rows; got " .. tostring(#entries) .. " current=" .. tostring(current))
    assert(entries[1].Text == "Open main session", "first details row should open the main session")
    assert(entries[2].Text == "New session", "second details row should create a named session")
    assert(entries[3].Text == "Notes", "third details row should open project notes")
    EOF

    keystone-project-menu set-current-project $'open-details\tkeystone'
    lua "$PWD/check-project-details.lua"
    normalized_project="$(keystone-project-menu get-current-project)"
    [[ "$normalized_project" == "keystone" ]]

    touch "$out"
  ''
