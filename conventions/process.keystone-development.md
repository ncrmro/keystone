# Convention: Keystone Development Workflow (process.keystone-development)

Standards for efficiently developing and deploying changes across the keystone
platform repos: `ncrmro/keystone`, `ncrmro/nixos-config`, and
`Unsupervisedcom/deepwork`. All repos live under `~/.keystone/repos/{owner}/{repo}/`.

For the technical rules governing how `keystone.development = true` resolves paths
at the Nix module level, see `process.keystone-development-mode`.

## Repo roles

1. **`ncrmro/keystone`** is the upstream platform — reusable NixOS modules any user
   can adopt. Changes here affect all adopters. Put things here when they are
   broadly useful and not specific to ncrmro's setup.
2. **`ncrmro/nixos-config`** is the consumer flake — per-host and per-user config
   that imports keystone modules. Put things here when they are specific to this
   fleet (host names, secrets, user preferences).
3. **`Unsupervisedcom/deepwork`** is the DeepWork framework and shared job library.
   Edit `library/jobs/` here for shared library jobs. Keystone-native jobs live in
   `ncrmro/keystone/.deepwork/jobs/`.

## `ks` commands

4. `ks build` MUST be used to verify changes compile before deploying. It builds
   the full system for the current host using local keystone checkouts in dev mode.
5. `ks update --dev` deploys **home-manager profiles only** (fast, no sudo). Use
   this after editing terminal config, conventions, or deepwork jobs.
6. `ks update` runs the full update cycle: pull, lock, build, push, deploy. Requires
   sudo. Use after keystone or nixos-config changes that affect NixOS system config.
7. `ks doctor` MUST be run when diagnosing fleet health or after a failed deploy.
8. `ks switch` (alias for the NixOS rebuild path) applies immediately, requires sudo.

## Keystone dev workflow (in-repo iteration)

9. To test keystone module changes without committing to GitHub, use `keystone-dev`:
   ```bash
   keystone-dev --build   # verify changes compile (no deploy)
   keystone-dev           # nixos-rebuild switch with local keystone (deploys immediately)
   keystone-dev --boot    # nixos-rebuild boot (safe for dbus/init changes)
   ```
10. When `keystone.development = true`, `ks build` and `ks update --dev` automatically
    use the live `ncrmro/keystone` checkout — no `keystone-dev` wrapper needed for
    home-manager profile changes.

## Change flow: keystone → nixos-config

11. When a change ships to the `ncrmro/keystone` GitHub repo, nixos-config must
    update its flake lock to pick it up:
    ```bash
    nix flake update keystone   # update keystone input only — NEVER bare nix flake update
    git add flake.lock && git commit -m "feat: update keystone (<description>)"
    ```
12. `nix flake update` WITHOUT a target input MUST NOT be used — it pulls new nixpkgs
    and all inputs, causing massive unrelated rebuilds.

## Conventions and AI instruction files

13. Convention files (`conventions/*.md`) and `archetypes.yaml` in `ncrmro/keystone`
    are the source of truth for agent instructions. Edit them here; the Nix build
    regenerates all downstream instruction files (`~/.claude/CLAUDE.md`, etc.).
14. After editing a convention or archetype, run `ks update --dev` to regenerate
    instruction files. In development mode, regenerated files appear as git diffs
    in the live repo checkout — commit them to persist the change.

## DeepWork jobs

15. `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` (set by keystone in dev mode) points at two
    live job roots:
    - `~/.keystone/repos/Unsupervisedcom/deepwork/library/jobs/` — shared library jobs
    - `~/.keystone/repos/ncrmro/keystone/.deepwork/jobs/` — keystone-native jobs
16. Edits to job files in these directories take effect immediately without rebuild.
17. When fixing or extending a shared library job, edit it in
    `Unsupervisedcom/deepwork/library/jobs/`. For keystone-specific jobs, edit in
    `ncrmro/keystone/.deepwork/jobs/`.
