{
  pkgs,
  lib,
}:
pkgs.runCommand "test-pz-regression"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      git
      gnused
      jq
      yq-go
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_STATE_HOME="$PWD/state"
    export XDG_CACHE_HOME="$PWD/cache"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.git
        pkgs.gnused
        pkgs.jq
        pkgs.yq-go
      ]
    }"
    export VAULT_ROOT="$HOME/notes"

    mkdir -p \
      "$HOME" \
      "$XDG_STATE_HOME" \
      "$XDG_CACHE_HOME" \
      "$VAULT_ROOT" \
      "$PWD/bin" \
      "$HOME/.keystone/repos/example/config"

    cat > "$PWD/bin/pz" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/packages/pz/pz.sh" "$@"
    EOF
    chmod +x "$PWD/bin/pz"

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
          "last_active": "2026-03-31"
        },
        "body": "Build Keystone tooling."
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
      printf '%s\n' 'keystone [Created 00:00]'
      exit 0
    fi

    printf 'unexpected zellij args: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/zellij"

    cat > "$PWD/bin/hostname" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' 'devbox'
    EOF
    chmod +x "$PWD/bin/hostname"

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
      },
      {
        "configName": "remote",
        "hostname": "remote",
        "sshTarget": "remote",
        "fallbackIP": "100.64.0.9"
      }
    ]
    JSON
      exit 0
    fi

    printf 'unexpected nix args: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/nix"

    cat > "$HOME/.keystone/repos/example/config/hosts.nix" <<'EOF'
    {}
    EOF

    default_host="$(pz get-default-host)"
    [[ "$default_host" == "devbox" ]]

    pz set-default-host remote
    [[ "$(pz get-default-host)" == "remote" ]]

    hosts_json="$(pz hosts-json)"
    printf '%s\n' "$hosts_json" | jq -e '
      length == 2
      and any(.[]; .hostname == "devbox")
      and any(.[]; .hostname == "remote" and .fallbackIP == "100.64.0.9")
    ' >/dev/null

    initial_launch_json="$(pz project-launch-json keystone)"
    printf '%s\n' "$initial_launch_json" | jq -e '
      .project == "keystone"
      and .currentHost == "devbox"
      and .effectiveHost == "remote"
      and .provider == ""
      and .model == ""
      and .fallbackModel == ""
    ' >/dev/null

    pz project-set-host keystone devbox
    pz project-set-models keystone openai gpt-5.4 gpt-5.4-mini

    updated_launch_json="$(pz project-launch-json keystone)"
    printf '%s\n' "$updated_launch_json" | jq -e '
      .effectiveHost == "devbox"
      and .provider == "openai"
      and .model == "gpt-5.4"
      and .fallbackModel == "gpt-5.4-mini"
    ' >/dev/null

    launcher_state_json="$(pz launcher-state-json)"
    printf '%s\n' "$launcher_state_json" | jq -e '
      .project_hosts.by_origin_host.devbox == "remote"
      and .interactive_defaults.projects.keystone.host == "devbox"
      and .interactive_defaults.projects.keystone.provider == "openai"
      and .interactive_defaults.projects.keystone.model == "gpt-5.4"
      and .interactive_defaults.projects.keystone.fallback_model == "gpt-5.4-mini"
    ' >/dev/null

    pz export-menu-cache --write-state >/dev/null
    cache_path="$XDG_STATE_HOME/keystone/project-menu/projects-v1.json"
    [[ -f "$cache_path" ]]
    jq -e '
      .schema_version == 1
      and (.projects | length) == 1
      and .projects[0].slug == "keystone"
      and .default_target_host == "remote"
    ' "$cache_path" >/dev/null

    touch "$out"
  ''
