{
  pkgs,
  lib,
}:
pkgs.runCommand "test-pz-host-launcher-state"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      git
      gnugrep
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
        pkgs.gnugrep
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

    cat > "$HOME/.keystone/repos/example/config/projects.yaml" <<'EOF'
    keystone:
      mission: "Build Keystone tooling."
      repos:
        - ncrmro/keystone
    EOF

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

    [[ "$(pz get-default-host)" == "devbox" ]]

    pz set-default-host remote
    pz project-set-host keystone devbox
    pz project-set-models keystone codex gpt-5 gpt-5-mini

    launch_json="$(pz project-launch-json keystone)"
    printf '%s\n' "$launch_json" | jq -e '
      .project == "keystone"
      and .currentHost == "devbox"
      and .effectiveHost == "devbox"
      and .provider == "codex"
      and .model == "gpt-5"
      and .fallbackModel == "gpt-5-mini"
      and (.hosts | length) == 2
    ' >/dev/null

    cache_json="$(pz export-menu-cache)"
    printf '%s\n' "$cache_json" | jq -e '
      .current_host == "devbox"
      and .default_target_host == "remote"
      and (.hosts | length) == 2
      and (.projects | length) == 1
      and .projects[0].slug == "keystone"
      and .projects[0].effective_host == "devbox"
      and .projects[0].sessions[0].slug == "main"
    ' >/dev/null

    launcher_state_json="$(pz launcher-state-json)"
    printf '%s\n' "$launcher_state_json" | jq -e '
      .project_hosts.by_origin_host.devbox == "remote"
      and .interactive_defaults.projects.keystone.host == "devbox"
      and .interactive_defaults.projects.keystone.provider == "codex"
      and .interactive_defaults.projects.keystone.model == "gpt-5"
      and .interactive_defaults.projects.keystone.fallback_model == "gpt-5-mini"
    ' >/dev/null

    touch "$out"
  ''
