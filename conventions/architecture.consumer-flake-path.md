# Convention: Consumer-flake path (architecture.consumer-flake-path)

The Keystone consumer flake — the per-deployment configuration that imports
keystone modules and declares hosts and users — has exactly one filesystem
location, derived deterministically from `$USER` and `$HOME`. There is no
pointer file, no environment override, no resolution cascade. This rule has
been violated and reverted repeatedly because the violations match
NixOS-idiomatic patterns; the convention exists to keep agents from
reinventing them.

## The canonical path

1. The Keystone consumer flake MUST live at
   `$HOME/.keystone/repos/$USER/keystone-config`.
2. `ks` and all keystone shell scripts MUST derive this path from `$USER`
   directly. They MUST NOT read a pointer file, environment variable, or
   filesystem heuristic.
3. When running through `sudo`, `$SUDO_USER` MUST take precedence over
   `$USER` so the canonical path resolves to the invoker's checkout, not
   `/root/.keystone/...`.
4. The `--flake <path>` CLI flag MUST NOT exist on `ks`. Worktree-based
   development uses the separate `keystone-dev` wrapper, not `ks`.
5. The NixOS module tree MUST NOT define an option whose purpose is to
   parameterize the consumer-flake path (e.g., `keystone.systemFlake.path`).
   The path is a fleet invariant.

## Rationale

6. The consumer-flake path is a pure function of `$USER` (or `$SUDO_USER`)
   and `$HOME`. Any mechanism that recovers the same value through a
   side channel adds zero information and several failure modes
   (stale pointer file after activation, drift between callers,
   testability gymnastics).
7. Agents primed on NixOS idioms tend to reinvent pointer-file resolution
   because it matches training-corpus patterns for `current-system/`
   metadata. The convention is the structural reason to stop, not a code
   review afterthought.
8. PRs #450, #451, and #453 each added or proposed a pointer-file
   mechanism; #451 and #453 were closed as not-planned and #461 reverted
   the pointer-file portion of #450.

## CI regression gate

9. `flake.nix` `checks.<system>.consumer-flake-path-regression` MUST fail
   when any of the following tokens appears in the source tree outside
   `conventions/` and `flake.nix`:
   - `/run/current-system/keystone-system-flake`
   - `keystone-current-system-flake`
   - `KEYSTONE_SYSTEM_FLAKE` (any variant — `_POINTER_FILE`, `_PATH`, ...)
   - `KEYSTONE_CONFIG_REPO`
   - `keystone.systemFlake` (NixOS option path)
10. The check MUST run as part of `nix flake check` and the CI script
    matrix.
11. New legitimate uses of any token MUST add an explicit allowlist with
    a code comment justifying the exception; the regression gate MUST be
    updated alongside.

## Legacy shim exception

12. `NIXOS_CONFIG_DIR` is NOT in the regression-gate banned list, but
    new code MUST NOT introduce it. The single legacy consumer is
    `packages/ks-legacy/ks.sh`, which pre-dates this convention and
    documents its cascade in the script header.
13. New shell scripts MUST resolve the consumer flake via the canonical
    path and MUST NOT read `NIXOS_CONFIG_DIR`.

## Test overrides

14. Test harnesses that need to redirect the canonical-path lookup MUST
    do so by overriding `$HOME` (and `$USER`, where the test fixture
    needs a stable username). They MUST NOT introduce a pointer file or
    pointer-file-aware env var as a back door.

## Golden example

```rust
// repo.rs — single resolver, no parameters, no cascade.
pub fn canonical_consumer_flake_path() -> Result<PathBuf> {
    let user = std::env::var("SUDO_USER")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| std::env::var("USER").ok().filter(|value| !value.is_empty()))
        .context("Cannot determine current user: $USER is unset.")?;
    let home = home_dir().context("Failed to get home directory")?;
    Ok(home
        .join(".keystone")
        .join("repos")
        .join(user)
        .join("keystone-config"))
}
```

```bash
# pz.sh — the same rule expressed in shell.
local _root="$HOME/.keystone/repos/${USER}/keystone-config"
if [[ -f "$_root/hosts.nix" ]]; then
  readlink -f "$_root"
  return 0
fi
echo "error: Keystone consumer flake not found at canonical path: $_root" >&2
return 1
```
