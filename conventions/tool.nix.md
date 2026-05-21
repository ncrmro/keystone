## Nix

## Flakes

1. All projects MUST use flakes (`flake.nix` at repo root).
2. `flake.lock` MUST be committed to the repository.
3. Flake inputs SHOULD be pinned to specific revisions or branches for reproducibility.
4. You MUST NOT run `nix flake update` (full update) when only specific inputs changed — use `nix flake update <input-name>` for targeted updates.

## Dev Shells

5. Every project MUST provide a `devShells.default` in its flake.
6. Dev shells MUST include all build, test, and development dependencies.
7. Shell hooks MAY set environment variables needed by the project.

## Packages & Modules

8. NixOS modules MUST follow the `{ config, lib, pkgs, ... }:` argument pattern.
9. Module options MUST use `lib.mkOption` with type, default, and description. For boolean enable options, see `process.enable-by-default` rule 1 regarding default values.
10. Package derivations SHOULD use `stdenv.mkDerivation` or appropriate builder. For shell script packaging, see `code.shell-scripts` rules 23-27.

## Style

11. Nix files MUST use 2-space indentation.
12. Attribute sets with more than 3 keys SHOULD be broken across multiple lines.
13. `let ... in` blocks SHOULD be used for local bindings — avoid deeply nested `with` scopes.
14. File-level comments MUST explain the module's purpose using `#` comment blocks.

## Testing

15. NixOS modules SHOULD have VM tests (`nixos/tests`) for non-trivial behavior.
16. Flake checks (`nix flake check`) MUST pass before pushing.

## NixOS System Activation

For NixOS `system.activationScripts` vs `systemd.services` oneshots, see
`os.systemd-over-activation`. Default to systemd; activation scripts are the
narrow exception.

## Home-Manager File Management

17. Config files that the managed tool modifies at runtime MUST NOT use `home.file` with `.text` or `.source`, because home-manager creates an immutable Nix store symlink that the tool cannot write to.
18. Runtime-writable config files MUST use `home.activation` to write or merge content as a regular file.
19. When a tool stores both Nix-managed keys (e.g., `mcpServers`) and runtime state (e.g., cached feature flags, account data) in the same file, the activation script MUST merge only the Nix-managed keys — preserving all other content the tool has written.
20. Activation scripts that merge into existing files SHOULD use `jq -s '.[0] * {key: .[1]}'` (or equivalent) to replace only the managed key.
21. Activation scripts MUST handle three cases: stale Nix store symlink (remove and create), existing regular file (merge), and missing file (create with defaults).
22. Keystone secret management MUST distinguish at least four classes of agenix secrets: os-level secrets, service secrets, user-home secrets, and custom secrets.
23. Os-level secrets SHOULD use stable host-oriented names and recipient sets derived from the machines or operating-system roles that need the secret at runtime.
24. Service secrets SHOULD use stable service-oriented names and recipient sets derived from the machines or services that actually need the secret at runtime.
25. User-home secrets MUST be modeled around the Home Manager principal that consumes them, not around a single machine, when that user profile is intentionally deployed on multiple hosts.
26. A user-home secret MUST include every system key for hosts where that Home Manager user is installed; otherwise the profile is not portable across that user's declared deployment surface.
27. The corresponding `age.secrets.<name>` runtime declaration MUST exist on every host where that Home Manager user is installed when the user-home profile expects `/run/agenix/<name>` to exist there.
28. User-home secrets SHOULD follow a shared naming convention rooted in the username so the ownership is obvious from the secret name, for example `${username}-github-token`, `${username}-forgejo-token`, or `${username}-immich-api-key`.
29. Secret-backed environment variables in Home Manager MUST NOT be set with `home.sessionVariables` when the value would be embedded in the Nix store. Non-secret values MAY use `home.sessionVariables`, but secret values MUST be read from runtime files such as `/run/agenix/<name>` in a shell init hook or another runtime-only execution path.
30. When a tool needs both a public endpoint and a secret credential, the public endpoint SHOULD be set declaratively with `home.sessionVariables`, while the secret credential SHOULD be exported from the agenix runtime file at shell startup.
31. Secret-management surfaces such as Walker menus or future `ks secrets` commands SHOULD expose os-level secrets, service secrets, user-home secrets, and custom secrets as first-class categories so users can discover the intended scope before editing recipients or values.

### Golden Example

Claude Code stores MCP server config alongside runtime state (feature flags, OAuth account cache, subscription data) in `~/.claude.json`. The Nix module must manage `mcpServers` without destroying runtime state:

```nix
# WRONG — creates immutable symlink, Claude Code hangs in infinite retry loop
home.file.".claude.json".text = builtins.toJSON { mcpServers = cfg.mcpServers; };

# RIGHT — merges mcpServers into existing file, preserves runtime state
claudeJsonMcpServers = pkgs.writeText "claude-mcp-servers.json"
  (builtins.toJSON cfg.mcpServers);

home.activation.claudeJsonConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  claudeJson="$HOME/.claude.json"

  if [ -L "$claudeJson" ]; then
    rm -f "$claudeJson"
  fi

  if [ -f "$claudeJson" ]; then
    ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' \
      "$claudeJson" ${claudeJsonMcpServers} > "$claudeJson.tmp" \
      && mv "$claudeJson.tmp" "$claudeJson"
  else
    ${pkgs.jq}/bin/jq -n --slurpfile s ${claudeJsonMcpServers} \
      '{mcpServers: $s[0]}' > "$claudeJson"
  fi
'';
```

When a user-level Home Manager profile needs reusable credentials across multiple hosts, the user PAT secret recipients and runtime exports must follow the user rather than a single machine. The keystone module that implements this (`keystone.terminal.github`) and the convention for naming, scope, and recipient discipline are documented in `tool.github-pats`. The adopter declares one `age.secrets.<name>` entry per host and enables the keystone module; do not write a bespoke `programs.zsh.initExtra` block.

## Os-level GitHub access tokens for the nix daemon

32. The nix daemon authenticating to GitHub for flake fetches (`nix flake update`, `ks update`) MUST use an **os-level** agenix secret distinct from the user-PAT secret described in `tool.github-pats`. The daemon runs as root and cannot read a `mode 0400 owner=<user>` file; even if it could, daemon-level access requires its own recipient set drawn from system keys.
33. The os-level secret basename MUST follow one of:
    - `nix-flake-github-token` — portable, recommended default.
    - `<hostname>-nix-flake-github-token` — host-scoped when blast radius must be smaller. `<hostname>` is the agenix `systems.*` key.
34. The recipient set for the os-level secret MUST include the **system** keys of every host that runs `nix flake update` against `github:` inputs. It MUST NOT include user or yubikey keys — those are user-PAT territory.
35. The `age.secrets.<name>` declaration MUST set `owner = "root"; mode = "0400";`.
36. The keystone module `keystone.os.githubTokenNix` MUST be used to wire the secret into `nix.conf`. The module materializes `/etc/nix/access-tokens.conf` from the runtime file via a hardened systemd oneshot and appends `!include` to `nix.extraOptions` — the token value never enters the Nix store.
37. The os-level secret MAY share its plaintext PAT value with the user-readable agents PAT (`github-agents-token`) during bootstrap, but SHOULD be rotated to a distinct, narrowly-scoped token before relying on the audit trail. Distinct secret names with distinct recipient sets and distinct file ownership are required regardless of whether the underlying token value is shared.

### Golden example: os-level nix-daemon token

```nix
# agenix-secrets/secrets.nix
"secrets/nix-flake-github-token.age".publicKeys = adminKeys ++ [
  systems.ncrmro-workstation
  systems.ncrmro-laptop
];

# nixos host that runs `ks update` / `nix flake update`
age.secrets.nix-flake-github-token = {
  file = "${inputs.agenix-secrets}/secrets/nix-flake-github-token.age";
  owner = "root";
  mode = "0400";
};

keystone.os.githubTokenNix = {
  enable = true;
  # tokenFile defaults to /run/agenix/nix-flake-github-token
};
```

### Darwin parity (per-user nix.conf)

On Darwin keystone hosts there is no nix-darwin system module — `mkDarwinInventoryHost` produces standalone home-manager only. `nix flake update` runs as the user, so the equivalent wiring is per-user. Use `keystone.terminal.githubTokenNix` (the home-manager module) with `source = "gh-auth"` to materialize `~/.config/nix/access-tokens.conf` at activation time from the existing `gh auth` login. No additional agenix secret is required on macOS for this path.

```nix
keystone.terminal.githubTokenNix = {
  enable = true;
  # source defaults to "gh-auth"
};
```
