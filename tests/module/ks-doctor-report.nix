{ pkgs }:
pkgs.runCommand "ks-doctor-report"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      git
      hostname
      gnugrep
      jq
      gnused
    ];
  }
  ''
    set -euo pipefail

    export HOME="$PWD/home"
    export PATH="${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.git
        pkgs.hostname
        pkgs.gnugrep
        pkgs.jq
        pkgs.gnused
      ]
    }"

    mkdir -p "$HOME/.keystone/repos/acme/app" "$HOME/repos/acme/service" "$HOME/.worktrees/acme/service/feat-clean" "$HOME/notes" "$HOME/nixos-config"
    mkdir -p "$HOME/.claude/plugins/cache/deepwork-plugins/example" "$HOME/.local/share/uv/tools/deepwork"
    cat > "$HOME/nixos-config/hosts.nix" <<'EOF'
    {}
    EOF
    cat > "$HOME/.claude.json" <<'EOF'
    {
      "mcpServers": {
        "deepwork": {
          "command": "/nix/store/example/bin/deepwork",
          "args": ["serve", "--path", ".", "--platform", "claude"]
        }
      }
    }
    EOF
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/installed_plugins.json" <<'EOF'
    [
      "deepwork/learning-agents"
    ]
    EOF
    cat > "$HOME/nixos-config/.mcp.json" <<'EOF'
    {
      "mcpServers": {
        "deepwork": {
          "command": "uvx",
          "args": ["deepwork", "serve"]
        }
      }
    }
    EOF

    git init -b main "$HOME/.keystone/repos/acme/app" >/dev/null
    (
      cd "$HOME/.keystone/repos/acme/app"
      git config user.name test
      git config user.email test@example.com
      touch README.md
      git add README.md
      git commit -m "init" >/dev/null
    )

    git init -b main "$HOME/repos/acme/service" >/dev/null
    (
      cd "$HOME/repos/acme/service"
      git config user.name test
      git config user.email test@example.com
      touch README.md
      git add README.md
      git commit -m "init" >/dev/null
    )

    git init -b feat-clean "$HOME/.worktrees/acme/service/feat-clean" >/dev/null
    (
      cd "$HOME/.worktrees/acme/service/feat-clean"
      git config user.name test
      git config user.email test@example.com
      touch README.md
      git add README.md
      git commit -m "init" >/dev/null
    )

    git init -b main "$HOME/notes" >/dev/null
    (
      cd "$HOME/notes"
      git config user.name test
      git config user.email test@example.com
      touch README.md
      mkdir .agents
      git add README.md
      git commit -m "init" >/dev/null
    )

    export NOTES_DIR="$HOME/notes"
    export CODE_DIR="$HOME/repos"
    export WORKTREE_DIR="$HOME/.worktrees"
    export DEEPWORK_ADDITIONAL_JOBS_FOLDERS="$HOME/.keystone/repos/ncrmro/keystone/.deepwork/jobs:$HOME/missing-jobs"
    export NIXOS_CONFIG_DIR="$HOME/nixos-config"

    output="$(${pkgs.bash}/bin/bash ${../../packages/ks/doctor-report.sh} \
      --repo-root "$HOME/nixos-config" \
      --hosts-nix "$HOME/nixos-config/hosts.nix" \
      --current-host "" \
      --scope agent \
      --agent-name drago)"

    printf '%s\n' "$output" | grep -F "## Scripted preflight report" >/dev/null
    printf '%s\n' "$output" | grep -F "**scope**: agent" >/dev/null
    printf '%s\n' "$output" | grep -F "**agent**: drago" >/dev/null
    printf '%s\n' "$output" | grep -F "### Managed repos" >/dev/null
    printf '%s\n' "$output" | grep -F "### Project repos" >/dev/null
    printf '%s\n' "$output" | grep -F "### DeepWork MCP" >/dev/null
    printf '%s\n' "$output" | grep -F '$HOME/.claude.json' >/dev/null
    printf '%s\n' "$output" | grep -F '$HOME/.local/share/uv/tools/deepwork' >/dev/null
    printf '%s\n' "$output" | grep -F '$HOME/.claude/installed_plugins.json' >/dev/null
    printf '%s\n' "$output" | grep -F "provider status" | grep -F "conflict" >/dev/null
    printf '%s\n' "$output" | grep -F "### Notes repo" >/dev/null
    printf '%s\n' "$output" | grep -F "**legacy artifacts**: .agents" >/dev/null
    printf '%s\n' "$output" | grep -F "### Worktrees" >/dev/null
    printf '%s\n' "$output" | grep -F '$HOME/missing-jobs' >/dev/null

    touch "$out"
  ''
