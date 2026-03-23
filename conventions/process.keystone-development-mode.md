# Convention: Keystone Development Mode (process.keystone-development-mode)

Keystone development mode (`keystone.development`) enables rapid iteration by
using local repository checkouts instead of immutable Nix store copies. When
enabled, modules derive local paths from the `keystone.repos` registry at
`~/.keystone/repos/{owner}/{repo}/`.

## Top-Level Toggle

1. `keystone.development` is a NixOS boolean that defaults to `false`. This is
   an exception to the default-on principle (see `process.enable-by-default`
   rule 17) because development mode requires local repo checkouts to function
   — enabling it without repos present would break builds.
2. Setting `keystone.development = true` MUST NOT, by itself, change any
   behavior unless `keystone.repos` declares at least one repository with a
   matching `flakeInput`.

## Repository Registry

3. `keystone.repos` is an attrset keyed by `owner/repo` (e.g.,
   `"ncrmro/keystone"`) that declares managed repositories.
4. Each entry MUST specify a `url` (git remote) and MAY specify `flakeInput`
   (the corresponding flake input name) and `branch` (default: `"main"`).
5. Repositories are expected at `~/.keystone/repos/{owner}/{repo}/` — this
   path is computed, never hardcoded per-user.

## Path Resolution

6. When `keystone.development = true`, modules that consume Nix store copies
   (conventions, deepwork jobs, claude-code commands) MUST resolve to the
   local checkout path derived from `keystone.repos` entries whose
   `flakeInput` matches the relevant flake input.
7. When `keystone.development = false` (default), all paths MUST resolve to
   immutable Nix store copies — behavior is identical to a locked build.

## Terminal Module

8. `keystone.terminal.devMode.keystonePath` is auto-derived from the
   `keystone.repos` entry whose `flakeInput == "keystone"` when development
   mode is enabled.
9. `keystone.terminal.devMode.deepworkPath` is auto-derived from the
   `keystone.repos` entry whose `flakeInput == "deepwork"` when development
   mode is enabled.
10. DeepWork library jobs (`DEEPWORK_ADDITIONAL_JOBS_FOLDERS`) swap to local
    checkouts when the corresponding `devMode` path is set.

## Desktop Module

11. (Future) Desktop theme and configuration files MAY use local checkouts for
    rapid iteration when `keystone.development = true`.

## Server Module

12. (Future) Server modules MAY use local checkouts for service configs when
    `keystone.development = true`.

## Safety

13. `keystone.development` MUST only affect path resolution — it MUST NOT
    modify, commit, or push any repository (per REQ-018.8).
14. Modules MUST NOT write to paths derived from `keystone.repos` entries.
    Local checkouts are read-only from the module system's perspective.

## Agent Parity

15. Agents MUST inherit development mode from the global
    `keystone.development` setting via their home-manager config bridge (see
    `process.enable-by-default` rules 9-11).

## Diagnostics

16. `ks doctor` MUST report development mode status: whether it is enabled,
    which repos are declared, and whether their local checkouts exist (per
    REQ-023).
