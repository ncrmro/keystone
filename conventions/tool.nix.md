
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
9. Module options MUST use `lib.mkOption` with type, default, and description.
10. Package derivations SHOULD use `stdenv.mkDerivation` or appropriate builder. For shell script packaging, see `code.shell-scripts` rules 23-27.

## Style

11. Nix files MUST use 2-space indentation.
12. Attribute sets with more than 3 keys SHOULD be broken across multiple lines.
13. `let ... in` blocks SHOULD be used for local bindings — avoid deeply nested `with` scopes.
14. File-level comments MUST explain the module's purpose using `#` comment blocks.

## Testing

15. NixOS modules SHOULD have VM tests (`nixos/tests`) for non-trivial behavior.
16. Flake checks (`nix flake check`) MUST pass before pushing.
