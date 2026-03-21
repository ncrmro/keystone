# REQ-024: NixOS Evaluation Warning Triage

When `ks update --lock` runs, NixOS emits evaluation warnings for deprecated
APIs, renamed options, and pending removals. Today these warnings scroll past
silently and accumulate as untracked technical debt. This spec defines (1) the
immediate fixes for warnings that originate in keystone's own source files, and
(2) a `.deepreview` rule that catches new deprecations before they merge.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a Keystone operator, I want `ks update --lock` to produce clean output
with zero evaluation warnings from keystone's own modules, so that I can
trust the warning stream as signal (upstream churn) rather than noise
(unfixed keystone debt), and so that new deprecation warnings are caught
and fixed or tracked before they reach main.

## Architecture

```
ks update --lock
    │
    ▼
nix build (evaluation)
    │
    ├── warnings from keystone modules  ← fixable in this repo
    │     ├── modules/terminal/shell.nix       nixfmt-rfc-style
    │     ├── modules/os/mail.nix              services.stalwart-mail
    │     └── packages/cfait/default.nix       buildFeatures / buildNoDefaultFeatures
    │
    └── warnings from upstream nixpkgs  ← not fixable in keystone
          ├── hostPlatform / buildPlatform renamed in nixpkgs stdenv
          ├── xorg.lndir deprecated (within nixpkgs package set)
          ├── useFetchCargoVendor (nixpkgs Rust infrastructure)
          └── sabnzbd.configFile (nixos-config host file, not keystone)

                  ▼
.deepreview rule: nixos-eval-warnings
    │
    ├── scan changed .nix files for known deprecated patterns
    │
    ├── SIMPLE (rename-only fix in keystone source)
    │     └── auto-fix inline → commit → continue
    │
    └── COMPLEX (upstream, multi-file, or config-repo change)
          └── surface as review finding → human creates ks.issue
```

## Affected Modules

- `modules/terminal/shell.nix` — Replace `nixfmt-rfc-style` with `nixfmt`
- `modules/os/mail.nix` — Replace `services.stalwart-mail` with `services.stalwart`
- `packages/cfait/default.nix` — Replace `buildFeatures`/`buildNoDefaultFeatures`
  with `withFeatures`/`withNoDefaultFeatures`
- `.deepwork/jobs/keystone_system/.deepreview` (or repo-root `.deepreview`) —
  New review rule `nixos-eval-warnings` that checks for known deprecated patterns

## Requirements

### Immediate Fixes — Keystone Source Files

**REQ-024.1** `modules/terminal/shell.nix` MUST reference `nixfmt` instead of
`nixfmt-rfc-style`. The `nixfmt-rfc-style` attribute was merged into `pkgs.nixfmt`
and the old name now emits an evaluation warning on every build.

**REQ-024.2** `modules/os/mail.nix` MUST use `services.stalwart` (the new NixOS
module name) instead of `services.stalwart-mail`. The old option name was removed
upstream and now triggers a warning on every evaluation.

**REQ-024.3** `packages/cfait/default.nix` MUST replace `buildFeatures` with
`withFeatures`. The `buildFeatures` attribute is deprecated in `buildRustPackage`
and will be removed in a future nixpkgs release.

**REQ-024.4** `packages/cfait/default.nix` MUST replace `buildNoDefaultFeatures`
with `withNoDefaultFeatures`. Same deprecation cycle as `buildFeatures`.

**REQ-024.5** After applying REQ-024.1–4, `nix flake check --no-build` MUST
produce zero evaluation warnings that originate from keystone module paths
(i.e., paths inside the keystone store derivation).

### DeepReview Rule

**REQ-024.6** A `.deepreview` rule named `nixos-eval-warnings` MUST be added to
the keystone repository. The rule MUST trigger on any changed `.nix` file.

**REQ-024.7** The rule MUST check each changed `.nix` file for the following
known simple-fix patterns:

| Deprecated pattern | Replacement | Category |
|--------------------|-------------|----------|
| `nixfmt-rfc-style` | `nixfmt` | package rename |
| `services.stalwart-mail` | `services.stalwart` | option rename |
| `buildFeatures` (in `buildRustPackage`) | `withFeatures` | attr rename |
| `buildNoDefaultFeatures` (in `buildRustPackage`) | `withNoDefaultFeatures` | attr rename |
| `useFetchCargoVendor = true` (in `buildRustPackage`) | remove attribute | redundant since 25.05 |
| `xorg.lndir` | `lndir` | package rename |

**REQ-024.8** For each simple-fix pattern found, the rule MUST report the file,
line number, and the replacement to apply. The review finding MUST classify the
change as `AUTO-FIX: rename only, no semantic change`.

**REQ-024.9** For patterns that cannot be auto-fixed (e.g., `hostPlatform`/
`buildPlatform` rename — only relevant inside nixpkgs-internal callPackage
expressions, not consumer modules), the rule MUST classify findings as
`UPSTREAM: not fixable in keystone; originates from a nixpkgs dependency`.
These SHOULD be surfaced as informational only and MUST NOT block the review.

**REQ-024.10** The rule SHOULD include a reference to this spec (`REQ-024`) so
reviewers understand the triage classification criteria.

### Categorization of Current Warnings

**REQ-024.11** The following warnings from the 2026-03-21 `ks update --lock`
run are classified UPSTREAM (not fixable in keystone) and MUST NOT be treated
as open keystone bugs:

- `'system' has been renamed to/replaced by 'stdenv.hostPlatform.system'` —
  emitted by nixpkgs stdenv internals when building packages that use the
  deprecated `pkgs.system` shorthand; not present in keystone source.
- `'hostPlatform'/'buildPlatform' has been renamed to stdenv.*` — same cause;
  emitted by nixpkgs packaging of third-party dependencies.
- `The xorg package set has been deprecated, 'xorg.lndir' has been renamed to
  'lndir'` — emitted by a nixpkgs package that keystone pulls in transitively;
  the package maintainer upstream must fix this.
- `buildRustPackage: 'useFetchCargoVendor' is non-optional and enabled by
  default as of 25.05, remove it` — emitted by nixpkgs Rust crates that
  keystone imports via flake inputs; not present in `packages/cfait/default.nix`
  or other keystone Rust packages.
- `sabnzbd.configFile is deprecated` — defined in nixos-config host files
  (not keystone); the fix belongs in the nixos-config repo.
- `buildFeatures`/`buildNoDefaultFeatures` (from nixpkgs-internal packages) —
  separate from the same patterns in `packages/cfait/default.nix`, which IS
  fixable in keystone (covered by REQ-024.3–4).

**REQ-024.12** Each upstream warning that appears consistently SHOULD be tracked
in a comment block in the `.deepreview` rule so future reviewers understand it
is known and classified.

### Warning Suppression Policy

**REQ-024.13** Keystone MUST NOT suppress evaluation warnings using
`--suppress-warnings` or equivalent flags. Warnings from upstream packages
provide upgrade signal; suppression hides legitimate future work.

**REQ-024.14** The `ks update --lock` output SHOULD NOT be filtered to hide
evaluation warnings. They MUST remain visible so operators can monitor
upstream package health.

### Configuration

No new Nix options are required. The `.deepreview` rule is a documentation
and review artifact consumed by the DeepWork review system.

```
# .deepreview (keystone repo root) — add new rule block:
[[rules]]
name = "nixos-eval-warnings"
trigger = "*.nix"
description = "Check for deprecated NixOS API patterns that cause evaluation warnings"
ref = "REQ-024"
```

### Integration

**REQ-024.15** The `.deepreview` rule MUST integrate with the existing
`ks.develop` workflow. The `review` step in `ks.develop` already runs
`.deepreview` rules; no new workflow step is required.

**REQ-024.16** When `ks.develop` is invoked to implement a change that touches
`.nix` files, the `nixos-eval-warnings` rule MUST run and report any deprecated
patterns found in changed files before the merge step.

**REQ-024.17** This spec (REQ-024) SHOULD be referenced from the `sweng/review`
step in `.deepwork/jobs/sweng/steps/review.md` as a checklist item for Nix
evaluation cleanliness.

### Security

No security implications. This spec addresses code quality and maintainability
only. Deprecated API fixes are rename-only changes with no semantic effect on
runtime behavior or security posture.

## Known Warning Inventory (2026-03-21 baseline)

| Warning | Source | Fixable in keystone | REQ |
|---------|--------|---------------------|-----|
| `nixfmt-rfc-style` deprecated | `modules/terminal/shell.nix:233` | YES | REQ-024.1 |
| `services.stalwart-mail` renamed | `modules/os/mail.nix:90` | YES | REQ-024.2 |
| `buildFeatures` deprecated | `packages/cfait/default.nix:21` | YES | REQ-024.3 |
| `buildNoDefaultFeatures` deprecated | `packages/cfait/default.nix:20` | YES | REQ-024.4 |
| `hostPlatform`/`buildPlatform` renamed | nixpkgs stdenv internals | NO | REQ-024.11 |
| `xorg.lndir` deprecated | nixpkgs transitive dep | NO | REQ-024.11 |
| `useFetchCargoVendor` (nixpkgs crates) | nixpkgs Rust packages | NO | REQ-024.11 |
| `sabnzbd.configFile` deprecated | nixos-config host file | NO (config repo) | REQ-024.11 |
| `stalwart-mail` (NixOS module name) | same as stalwart-mail above | YES | REQ-024.2 |

## References

- `modules/terminal/shell.nix:233` — `nixfmt-rfc-style` usage
- `modules/os/mail.nix:90` — `services.stalwart-mail` usage
- `packages/cfait/default.nix:20-21` — `buildNoDefaultFeatures`/`buildFeatures` usage
- `.deepwork/jobs/sweng/steps/review.md` — existing DeepWork review step
- NixOS 25.05 release notes — `nixfmt` merge, stalwart rename, Rust packaging changes
