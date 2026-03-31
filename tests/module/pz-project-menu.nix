{
  pkgs,
  lib,
}:
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
      yq-go
      zsh
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_STATE_HOME="$PWD/state"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.yq-go
        pkgs.zsh
      ]
    }"
    export VAULT_ROOT="$HOME/notes"

    mkdir -p "$HOME" "$XDG_STATE_HOME" "$VAULT_ROOT" "$PWD/bin"

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

    cat > "$PWD/bin/zk" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "$*" == *"list index/"* ]]; then
      cat <<'JSON'
    [
      {
        "absPath": "/tmp/notes/index/keystone.md",
        "metadata": {
          "type": "index",
          "project": "keystone",
          "description": "Build Keystone tooling.",
          "last_active": "2026-03-31",
          "milestones": [
            {
              "name": "Fix pz completion",
              "date": "2026-04-01"
            }
          ]
        },
        "body": "Build Keystone tooling."
      },
      {
        "absPath": "/tmp/notes/index/agents.md",
        "metadata": {
          "type": "index",
          "tags": [
            "project",
            "agents"
          ],
          "last_active": "2026-03-30"
        },
        "body": "Coordinate agent workflows.\n\nArchive notes."
      }
    ]
    JSON
      exit 0
    fi

    printf 'unexpected zk args: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/zk"

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

    projects_json="$(keystone-project-menu projects-json)"
    printf '%s\n' "$projects_json" | jq -e '
      length == 2
      and .[0].Text == "keystone"
      and .[0].Subtext == "1 session active"
      and .[1].Text == "agents"
      and .[1].Subtext == "1 session active"
    ' >/dev/null

    touch "$out"
  ''
