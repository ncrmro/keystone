# Convention: Testing strategy (process.testing)

Standards for how Keystone validates changes through `nix flake check`,
focused deterministic checks, and canonical example-configuration integration
checks.

## Core validation path

1. `nix flake check` MUST be the default repository-native validation path and CI contract.
2. Checks that are intended to gate routine development and pull requests MUST live under `checks` in `flake.nix`.
3. Ad hoc wrapper scripts MUST NOT be the only validation path for behavior that can be covered by `flake.nix` checks.

## Focused deterministic checks

4. Critical backend, CLI, and launcher-adapter behavior SHOULD have focused deterministic checks that isolate one contract at a time.
5. Focused checks SHOULD prefer mocked inputs and machine-readable assertions so failures are easy to diagnose.
6. Focused checks MUST remain in place even when a broader integration check exists for the same feature area.

## Standard example configuration checks

7. When Keystone has a canonical standard example configuration for a feature area, integration-style checks SHOULD evaluate against that config instead of relying only on synthetic fixtures.
8. Standard example configuration checks SHOULD verify expected module wiring, generated assets, packaged commands, and other declarative integration surfaces.
9. Standard example configuration checks MUST NOT replace focused deterministic checks for backend logic or command contracts.
10. When multiple example configs exist, checks SHOULD prefer the most canonical path that reflects normal Keystone usage rather than a development shortcut.

## Host integration boundary

11. Agents MUST run `ks build` when a change affects host integration, generated assets, or runtime behavior that deterministic `flake.nix` checks cannot validate.
12. Agents MUST NOT treat `ks build` as a substitute for adding a deterministic flake check when one can be added.

## Golden example

Walker menu work uses two layers of coverage:

- a focused script contract check for `keystone-secrets-menu` JSON output and dispatch behavior,
- a standard desktop config integration check that evaluates the canonical desktop example config and verifies Walker and Elephant launcher wiring.
