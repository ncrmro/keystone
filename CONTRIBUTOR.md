# Contributor guide

The goal of every keystone contribution is a clean `ks update --lock` — your
change lands in keystone `main`, the consumer flake relocks, and the full system
rebuilds and deploys with no manual intervention. Everything below serves that
goal.

## Happy path

```
1. Develop in a worktree branch or consumer flake (never dirty main)
2. Push branch → PR → agent review (at least one)
3. Squash-merge to main
4. ks update --lock   ← pulls main, relocks, builds, pushes, deploys
```

`ks update --lock` is the finish line. If it succeeds, the feature is live on
every host that runs it. If it fails, something upstream wasn't validated.

## Where to develop

| Change type | Develop in | Why |
|---|---|---|
| Keystone module/package | Worktree branch off main | Keeps main checkout clean for `ks build` |
| Per-host or per-user config | Consumer flake (`ncrmro/nixos-config`) | Not a platform change |
| Experimental / exploratory | Consumer flake with `keystone.experimental = true` | Safe to iterate without affecting other adopters |

The main keystone checkout (`~/.keystone/repos/ncrmro/keystone/`) MUST stay on
`main` with a clean working tree. `ks build` and `ks update --dev` operate on
this checkout — a dirty tree produces unpredictable builds.

### Worktree branches

```bash
git worktree add ~/.worktrees/ncrmro/keystone/<branch> -b <branch>
cd ~/.worktrees/ncrmro/keystone/<branch>
# develop, commit, push
git push origin <branch>
gh pr create
```

### Consumer flake changes

For changes specific to your fleet (host config, user preferences, secrets),
edit `ncrmro/nixos-config` directly. These don't need a keystone PR — just
commit and `ks update --lock`.

### Consumer flake resolution

`ks update` and `ks switch` resolve the consumer flake at the canonical
path `$HOME/.keystone/repos/$USER/keystone-config`. The path is a
deterministic function of `$USER` and `$HOME` — no pointer file, env var,
CWD walk, or `--flake` flag is involved. See
`conventions/architecture.consumer-flake-path.md` for the rationale and
the regression gate.

When developing on a branch, do the work in a worktree and either symlink
or move the canonical path to the worktree, or operate from the canonical
checkout itself.

## Review before merge

Worktree branches MUST be reviewed by at least one agent (via PR) before merging
to main. This catches regressions early, creates an audit trail, and ensures the
change validates against CI before `ks update --lock` consumes it.

## After merge: `ks update --lock`

Once your PR is squash-merged to keystone `main`:

```bash
# From the consumer flake (nixos-config)
ks update --lock
```

This runs the full cycle: pull latest inputs, relock `flake.lock` (picking up
your keystone change), build, push lock, and deploy. Even when the local system
has `keystone.development = true`, `--lock` ensures the consumer flake lock
points to the merged commit on GitHub — not the local checkout.

## Verifying changes

Before merging, validate your branch passes CI locally:

```bash
nix flake check --no-build  # Fast probe: evaluate outputs without building
nix flake check             # Full: repo-native checks and CI parity
ks build                    # Home-manager profiles when host integration matters
```

Agents MUST run `ks build` when a change affects host integration, generated
assets, or behavior that isolated flake checks cannot validate.

For agenix user-home secrets, agents MUST ensure both sides of the contract are
updated together: the encrypted secret recipients must include every host where
that Home Manager user is installed, and the corresponding `age.secrets.<name>`
declaration must exist on each of those hosts.

### Validation commands

```bash
nix flake check --no-build  # Fast local probe
nix flake check             # CI parity
ks build                    # Build home-manager profiles for current host
ks build --lock             # Full system build + lock + push (requires sudo)
ks update --dev             # Deploy home-manager profiles only
ks update                   # Full: pull, lock, build, push, deploy
ks update --lock            # Pull, lock, build, push, deploy (human-only)
ks switch                   # Fast deploy current local state
ks doctor                   # Diagnose system health
```

### E2E testing

`bin/test-e2e` runs a VM test pipeline from the keystone repo.  It
generates a consumer-flake fixture from the default template, locks it
to the current keystone checkout, and delegates to the fixture's
`test-iso`. The fixture is cached at `/tmp/keystone-e2e-fixture/` and
refreshed automatically on each run.  See
[ISO and OS virtual machine testing](docs/testing/iso-os-virtual-machine.md)
for the full reference.

There are two paths; pick the one that matches your change:

**Direct qcow2 (2-10 min)** — NixOS modules, storage, boot chain,
anything below the installer:

```bash
bin/test-e2e --direct laptop --headless   # build + boot + SSH check, clean up
bin/test-e2e --direct --headless          # same; host defaults to 'laptop'
bin/test-e2e --direct laptop              # keep SPICE window open for debugging
```

**Full ISO + installer (20-30 min)** — installer TUI, `ks install`,
post-reboot desktop validation:

```bash
bin/test-e2e                  # Full e2e (build + boot + install + validate)
bin/test-e2e --build-only     # ISO build only (CI parity)
bin/test-e2e --clean          # Regenerate fixture before running
bin/test-e2e --no-build       # Reuse existing ISO
```

`bin/test-e2e` forwards user-supplied flags to `test-iso`, so anything
in `test-iso --help` (e.g. `--luks-passphrase`, `--port`, `--memory`)
generally works with `bin/test-e2e` too. It may also add wrapper
defaults such as `--dev` and a default mode (`--e2e --headless`) when
no mode flag is provided.

## AI instruction regeneration

AI instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) are automatically
regenerated from `archetypes.yaml` and the `conventions/` directory during
`ks build`, `ks switch`, and `ks update --dev`. In development mode
(`keystone.development = true`), these files are symlinked from the repository,
and `ks switch` regenerates them as committable git diffs.

## DeepWork job sync

Shared DeepWork jobs are discovered through `DEEPWORK_ADDITIONAL_JOBS_FOLDERS`.
In development mode, Keystone sets that env var to two live job roots:

- `~/.keystone/repos/Unsupervisedcom/deepwork/library/jobs` — shared library
- `~/.keystone/repos/ncrmro/keystone/.deepwork/jobs` — keystone-native

Outside development mode, those resolve to packaged derivations. Edits to job
files in development mode take effect immediately without rebuild.

DeepWork `keystone_system/issue` draft bodies are temporary artifacts — write
them under `.deepwork/tmp/`, not `.deepwork/jobs/`.

## llm-agents input strategy

AI agent packages (`claude-code`, `gemini-cli`, `codex`, `opencode`) come from
the `llm-agents` flake input pinned at nightly-latest. Consumer flakes choose:

- **Nightly-latest**: `llm-agents.follows = "keystone/llm-agents"` — relocking
  keystone bumps agent versions automatically.
- **Stable**: declare independent `llm-agents` input and override with
  `keystone.inputs.llm-agents.follows = "llm-agents"`.

See `modules/terminal/AGENTS.md` § "llm-agents input strategy" for examples.

## VM testing

For the full automated ISO and desktop testing workflow, see
[ISO and OS virtual machine testing](docs/testing/iso-os-virtual-machine.md).

`bin/virtual-machine` is the canonical VM tool (Q35 + EDK2 SecureBoot + TPM + QXL).
The template e2e test (`./bin/test-iso --dev --headless --e2e`) validates the full
new-user journey. Changes to NixOS modules do NOT require an ISO rebuild — only
`ks` binary or installer module changes do.

`--post-install-reboot` creates a `post-install` qcow2 snapshot; restore with
`--restore <vm> post-install` to skip reinstallation when debugging. Consolidation
tracked in #339.
