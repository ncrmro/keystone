
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

## Home-Manager File Management

17. Config files that the managed tool modifies at runtime MUST NOT use `home.file` with `.text` or `.source`, because home-manager creates an immutable Nix store symlink that the tool cannot write to.
18. Runtime-writable config files MUST use `home.activation` to write or merge content as a regular file.
19. When a tool stores both Nix-managed keys (e.g., `mcpServers`) and runtime state (e.g., cached feature flags, account data) in the same file, the activation script MUST merge only the Nix-managed keys — preserving all other content the tool has written.
20. Activation scripts that merge into existing files SHOULD use `jq -s '.[0] * {key: .[1]}'` (or equivalent) to replace only the managed key.
21. Activation scripts MUST handle three cases: stale Nix store symlink (remove and create), existing regular file (merge), and missing file (create with defaults).

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
