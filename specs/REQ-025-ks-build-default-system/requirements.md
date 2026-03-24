# REQ-025: ks build defaults to full system

`ks build` previously defaulted to home-manager-only builds. This inverts
the default so operators can verify system-level NixOS changes (e.g.
`keystone.desktop.obs.gpuType`) without side effects.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHOULD, MAY, REQUIRED, OPTIONAL).

## Affected Modules
- `packages/ks/ks.sh` — CLI script
- `specs/REQ-019-ks-cli/requirements.md` — updated REQ-019.3, REQ-019.4

## Requirements

### Build command

**REQ-025.1** `ks build` (no flags) MUST build the full NixOS system
toplevel (`nixosConfigurations.*.config.system.build.toplevel`) for all
target hosts. It MUST NOT lock, commit, or push.

**REQ-025.2** `ks build --home-only` MUST build only home-manager
activation packages (the previous default behaviour).

**REQ-025.3** `ks build --lock` behaviour MUST remain unchanged (full
system build + lock + commit + push).

**REQ-025.4** `--dev` MUST be accepted as a deprecated alias for
`--home-only` in both `ks build` and `ks update`.

### Update command

**REQ-025.5** `ks update --home-only` MUST build and activate only
home-manager profiles across all target hosts, skipping the full NixOS
system rebuild. `--dev` is a deprecated alias.

### Path overrides

**REQ-025.6** `ks build` and `ks update` MUST accept `--config-path PATH`
to override nixos-config repo discovery. The path MUST be resolved via
`readlink -f`.

**REQ-025.7** `ks build` and `ks update` MUST accept `--keystone-path PATH`
to add an extra `--override-input keystone path:PATH` to all `nix build`
and `nixos-rebuild` invocations. The path MUST be resolved via `readlink -f`.

## Supersedes

- Previous `ks build` default (home-manager only) — REQ-019.3 updated
- `--dev` flag on `ks update` — replaced by `--home-only` (REQ-019.13 updated)
