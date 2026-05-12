---
title: Keeping packages up to date
description: How Keystone tracks nixpkgs, why packages drift, and how to keep security-critical apps like Chromium and Signal current
---

# Keeping packages up to date

Keystone pins every package through Nix flake inputs. Once `flake.lock` is committed, every package — kernel, browser, system library — stays at whatever revision was current when the lock was last refreshed. This page explains the channels Keystone tracks, why packages drift, and the supported ways to keep security-critical apps fresh.

## Channels Keystone tracks

NixOS publishes three relevant channels:

| Channel | Cadence | Security backports | Typical use |
|---|---|---|---|
| `nixos-X.Y` (e.g. `nixos-25.11`) | new every ~6 months, then maintenance | yes — security only | conservative servers |
| `nixos-unstable` | rolling, daily Hydra builds | no — newer revs supersede | desktops, developer workstations |
| `nixpkgs-unstable` | rolling, smaller increments | no | same role as nixos-unstable, smaller per-bump diff |

Keystone's main `nixpkgs` input (`flake.nix:5`) tracks `nixos-unstable`. Switching it to a stable channel is not viable for the current toolchain:

- **Hyprland** ships against bleeding-edge `wayland-protocols`, `mesa`, and `wlroots`. Stable channels diverge from Hyprland's expectations within weeks.
- **`llm-agents`** requires nixpkgs ≥ 2026-02-15 for `buildNpmPackage` with `fetcherVersion = 2`. Stable branches don't carry it.
- **Most other inputs** (`home-manager`, `disko`, `agenix`, `lanzaboote`) declare `inputs.nixpkgs.follows = "nixpkgs"`. Their development branches expect unstable.

The lever Keystone needs to pull is *bump cadence*, not channel choice.

## Why packages drift

`flake.lock` pins specific revisions. Nothing relocks them automatically — neither `ks update` nor `ks update --approve` calls `nix flake update`. A package only moves when:

1. A contributor runs `nix flake update <input>` manually, or
2. A scheduled bot opens a PR.

A few months without either, and the system runs against a frozen snapshot. Recent example: Chromium 145 in a `flake.lock` from February 2026, against upstream 148. Signal Desktop sliding toward its forced-deprecation window. Missed CVE patches across the entire closure.

## Two layers of planned automation

Keystone is moving toward a two-layer strategy. Both layers are open at the time of writing.

### Layer 1 — Dependabot for every flake input

[Issue #441](https://github.com/ncrmro/keystone/issues/441) proposes enabling GitHub's native Dependabot Nix-flake support. One PR per outdated input weekly, including the main `nixpkgs`. Bumping main `nixpkgs` refreshes the whole system — kernel, glibc, Chromium, every leaf.

- Strength: system-wide currency. Nothing is left behind.
- Trade-off: every bump is a large rebuild surface. Realistic merge cadence depends on review bandwidth and CI stability.

### Layer 2 — Curated fresh-pin for high-cadence packages

[PR #516](https://github.com/ncrmro/keystone/pull/516) introduces a dedicated `nixpkgs-fresh` flake input that tracks `nixos-unstable` independently of the main pin. A scheduled workflow runs `nix flake update nixpkgs-fresh` weekly. Selected packages — initially Chromium and Signal Desktop — are re-exported via the keystone overlay.

- Strength: Chromium and Signal stay fresh independently of when weekly `nixpkgs` PRs are merged.
- Trade-off: each fresh-pinned package's transitive dependencies duplicate in `/nix/store` (tens to hundreds of MB per package). The list must stay short.

The layers compose. Layer 1 keeps the whole system from rotting indefinitely. Layer 2 guarantees the security-critical leaves stay current even when Layer 1 PRs sit unmerged.

## When to add a package to the fresh-pin

A package belongs in the fresh-pin only when both conditions hold:

- Upstream releases faster than the realistic main-`nixpkgs` merge cadence.
- Staleness has real cost — security CVEs, forced client deprecation (Signal expires old clients), or breaking protocol changes.

Good candidates: browsers (Chromium, Firefox), security-critical desktop apps (Signal, password managers, sync clients), networking clients with frequent protocol churn.

Bad candidates:

- System libraries baked into the closure (`glibc`, `openssh`, kernel) — these can't be selectively overridden without breaking ABI assumptions.
- GNOME desktop components — already move on the nixpkgs cadence; nothing to gain.
- Packages already auto-bumped through other inputs (AI CLI agents come from `llm-agents`, Google Chrome from `browser-previews`).

To add a package once PR #516 lands, append to the overlay's `inherit (nixpkgsFreshPkgs) …` block in `overlays/default.nix`:

```nix
inherit (nixpkgsFreshPkgs)
  chromium
  signal-desktop
  firefox  # new
  ;
```

## Consumer-side overrides

You don't have to wait for Keystone to merge anything. Any consumer flake — your own `keystone-config` or `nixos-config` — can pull a fresher revision of a single package by adding a dedicated input and a small overlay:

```nix
# flake.nix
inputs.nixpkgs-fresh.url = "github:NixOS/nixpkgs/nixos-unstable";
```

```nix
# wherever your overlays are wired (configuration.nix or a host module)
nixpkgs.overlays = [
  (final: prev:
    let
      freshPkgs = import inputs.nixpkgs-fresh {
        inherit (final.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    in {
      inherit (freshPkgs) chromium signal-desktop;
    })
];
```

Refresh whenever needed:

```bash
nix flake update nixpkgs-fresh
```

This bypasses Keystone entirely. Use it for emergency CVE response, validating a fresher Chromium without coordinating upstream, or pinning a package your machine cares about (`inherit (freshPkgs) tailscale` to ride newer Tailscale features, for example).

## What to do today

Until [#441](https://github.com/ncrmro/keystone/issues/441) and [#516](https://github.com/ncrmro/keystone/pull/516) land:

1. Run `nix flake update nixpkgs` in your `keystone-config` flake monthly, or whenever you hit a stale-package symptom. Commit the resulting `flake.lock` change.
2. For Chromium specifically, consider switching to the `keystone.google-chrome` package — it's sourced from the `browser-previews` flake input and bumps on a faster cadence than the main `nixpkgs` pin.
3. For other security-critical packages, use the consumer-side override pattern above.

Once both layers ship, manual bumps become unnecessary for the curated packages; weekly Dependabot PRs handle the rest.

## Caching impact

Packages pulled from `nixos-unstable` — whether via the main `nixpkgs` or `nixpkgs-fresh` — are built by Hydra and served from `cache.nixos.org` (a default Nix substituter). Refreshing Chromium or Signal usually means downloading a pre-built binary, not building locally.

The Keystone Attic cache (`modules/binary-cache-client.nix`) republishes anything a host materializes, so the fleet cache fills naturally. Closure bloat from Layer 2 is bounded to the duplicated transitive deps of the curated packages and clears whenever the main `nixpkgs` catches up.

## Related

- [Releasing](releasing.md) — Keystone's own release model (branches, tags)
- `flake.nix` — flake input definitions
- `overlays/default.nix` — package overrides
- [Issue #441](https://github.com/ncrmro/keystone/issues/441) — Dependabot for flake inputs
- [PR #516](https://github.com/ncrmro/keystone/pull/516) — Initial `nixpkgs-fresh` infrastructure for Chromium and Signal
