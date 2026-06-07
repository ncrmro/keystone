# Internal FAQ — v1 Stabilization

> Leadership / contributor questions about v1. Update before release.

## What ships in v1?

The "Stable v1 surface" enumerated in [`README.md`](README.md): OS, terminal,
desktop, server, declarative project config, `ks` CLI, `pz` CLI.

## What does NOT ship in v1?

- `keystone.notes` (notes/zk module) — gated by `keystone.experimental`
- `archetypes.yaml` convention-based agent instruction composition
- Agent-workflow features (tracked under
  [Post-v1 milestone #14](https://github.com/ncrmro/keystone/milestone/14))

## How does an operator opt into experimental features?

Set `keystone.experimental = true;` on the host. See
[`docs/experimental.md`](../../experimental.md) for the gate semantics.

## What's the release tag scheme?

`vX.Y.Z` git tags. v1 stabilization branch is `release/1.0`. See
[`docs/releasing.md`](../../releasing.md) for the full workflow.

## What's deferred to v1.1?

See the **Moved to v1.1** section in [`tracker.md`](tracker.md). High-level:
1Password integration, walker docs entry, walker package-add flow, dependabot,
explicit session-kill on hyprlock failure.

## How are agent-workflow features handled?

They live on the [Post-v1 milestone](https://github.com/ncrmro/keystone/milestone/14)
and intentionally do not gate v1. Stability + click-to-update is the bar.
