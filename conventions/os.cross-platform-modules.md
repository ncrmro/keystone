# Convention: Cross-platform `keystone.os.*` modules (os.cross-platform-modules)

Standards for organising `keystone.os.*` Nix modules across NixOS and
nix-darwin. Keystone supports both `nixosConfigurations` (Linux) and
`darwinConfigurations` (macOS via nix-darwin). The two host kinds evaluate
in separate `lib.evalModules` invocations, but the option *surface* under
`keystone.os.*` must remain consistent so adopters can configure once and
have the value flow to every host that consumes it.

This convention exists because, without it, every shared concern gets
re-declared in each platform entry file and the schemas silently drift.
Rediscovered when `modules/os/darwin.nix` (PR #556) re-declared
`keystone.os.enable` and `keystone.os.adminUsername` independently of
`modules/os/default.nix`, masking the shared-admin derivation that NixOS
hosts already do.

## Three sharing patterns

There are three ways `keystone.os.*` modules can support multiple
platforms. Pick the right one based on what is being shared.

### Pattern 1 — Shared option declarations

1. Cross-platform option declarations MUST live in `modules/os/shared.nix`.
   Both `modules/os/default.nix` (NixOS) and `modules/os/darwin.nix`
   (Darwin) MUST import `./shared.nix` so the option names, types, and
   defaults are a single source of truth.
2. `shared.nix` MUST declare options only — it MUST NOT have a `config`
   block, because the derivation/assertion logic that fills an option
   is typically platform-specific (e.g. the NixOS `adminUsername`
   derivation reads `keystone.os.users.<name>.admin = true`, which has
   no Darwin equivalent yet).
3. Use this pattern when an option's name, type, and default surface
   are identical across platforms even if the `config` body differs.
   Canonical examples: `keystone.os.enable`, `keystone.os.adminUsername`.

### Pattern 2 — Runtime platform detection inside one module

4. A single module that emits different *resources* on each platform from
   the same enable flag SHOULD use runtime platform detection inside its
   `config` block. Detection MUST be done via the option tree, not via
   `pkgs.stdenv.isDarwin`, because module evaluation happens before
   platform-specific module sets are merged.
5. The canonical detection idiom is `options ? launchd` (truthy on
   nix-darwin, falsy on NixOS). Example:

   ```nix
   { config, lib, options, pkgs, ... }:
   let
     cfg = config.keystone.os.<feature>;
     hasLaunchdOptions = options ? launchd;
   in
   {
     config = lib.mkIf cfg.enable (
       { /* shared config */ }
       // lib.optionalAttrs (!hasLaunchdOptions) {
         systemd.services.<name> = { /* NixOS */ };
       }
       // lib.optionalAttrs hasLaunchdOptions {
         launchd.daemons.<name> = { /* Darwin */ };
       }
     );
   }
   ```
6. Modules using Pattern 2 MUST be imported from both `modules/os/default.nix`
   AND `modules/os/darwin.nix` so they are reachable on each platform.
7. Pattern 2 modules MUST NOT declare options that overlap with
   `shared.nix` — declare them in `shared.nix` instead. Pattern 2
   handles platform-specific *resource emission*; Pattern 1 handles
   the *option schema*.

### Pattern 3 — Strictly per-platform modules

8. When an option set has no cross-platform meaning, the module MAY
   live exclusively in one platform's entry tree. Examples on NixOS:
   `keystone.os.storage` (ZFS/disko), `keystone.os.tpm`,
   `keystone.os.secure-boot`. Future Darwin-only surfaces (Touch ID
   for sudo, declarative Homebrew, `system.defaults`) live exclusively
   in `modules/os/darwin.nix` (or its imports) and are not shared.
9. Per-platform modules MUST NOT redeclare options that already exist
   in `shared.nix`. If a Darwin-side counterpart of a Linux option ever
   makes sense, promote the option to `shared.nix` rather than
   duplicating it under a different namespace.

## Anti-patterns

10. The same option name MUST NOT be declared in both
    `modules/os/default.nix` and `modules/os/darwin.nix`. The Nix
    module system tolerates it only because the two trees never
    co-evaluate; the silent schema drift between platforms is the real
    cost (`adminUsername` derived on NixOS vs hardcoded on Darwin is
    the canonical drift this convention prevents).
11. Platform-shared values MUST NOT be threaded through helper-function
    arguments in `lib/templates.nix` when the same value is already
    available as a `keystone.os.<name>` option. Read from
    `config.keystone.os.*` instead — single source of truth.
12. nix-darwin options (e.g. `system.primaryUser`) that mirror a
    `keystone.os.*` value MUST be assigned from the shared option, not
    from a helper-local variable. Example: when nix-darwin gains
    `system.primaryUser` in the keystone pin, the assignment should be
    `system.primaryUser = config.keystone.os.adminUsername;`, not
    `system.primaryUser = username;` where `username` is a builder arg.

## When to promote an option to `shared.nix`

13. An option SHOULD be promoted to `shared.nix` as soon as a second
    platform's entry file needs the same name, type, and default
    semantics. Speculative promotion (declaring options in `shared.nix`
    that only one platform actually uses) MUST be avoided — keep
    `shared.nix` lean and migrate options into it lazily as parity
    appears.
14. The migration MUST happen atomically with the second-platform
    adoption: declare in `shared.nix`, remove from
    `modules/os/default.nix`, import from `modules/os/darwin.nix`
    (or vice-versa). Half-migrations leave a redeclaration in place
    and re-introduce the drift this convention prevents.

## Reference implementations

- `modules/os/shared.nix` — current scope: `keystone.os.enable`,
  `keystone.os.adminUsername`.
- `modules/os/github-token-nix.nix` — Pattern 2 example. Same module
  emits `systemd.services.nix-github-access-token` on NixOS and
  `launchd.daemons.nix-github-access-token` on Darwin from one
  `keystone.os.githubTokenNix.enable` flag.
- `modules/os/default.nix` — NixOS entry file. Imports `./shared.nix`
  and the Pattern 2 modules; declares NixOS-only options
  (`storage`, `tpm`, `users` schema, etc.) directly.
- `modules/os/darwin.nix` — Darwin entry file. Imports `./shared.nix`
  and the Pattern 2 modules; declares no overlapping options.

## See also

- `tool.nix` — module style, option declaration conventions.
- `process.enable-by-default` — guidance for the `enable` flag's
  default value across modules.
- `docs/macos.md` — adopter-facing guide to keystone's Darwin support;
  references this convention.
