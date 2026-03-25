# REQ-018: Keystone Home Directory and Repo Management

Standardize all keystone-managed local state under `~/.keystone/`. Replace
the fragile git-submodule pattern with a declarative repo registry
(`keystone.repos`) and a convention-based directory layout. Unify notes
paths for both human users and OS agents under the same root.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules
- `packages/ks/ks.sh` — repo discovery, pull, push, override-input, lock
- `modules/notes/default.nix` — user notes path default
- `modules/os/agents/types.nix` — agent notes path default
- `modules/terminal/projects.nix` — project repo resolution (REQ-010)
- New: `modules/repos.nix` — `keystone.repos` option declaration

## Directory Layout

```
~/.keystone/
├── repos/
│   ├── ncrmro/
│   │   ├── nixos-config/        # flakeInput: (self — the consumer flake)
│   │   ├── keystone/            # flakeInput: "keystone"
│   │   └── agenix-secrets/      # flakeInput: "agenix-secrets"
│   └── Unsupervisedcom/
│       └── deepwork/            # flakeInput: "deepwork" (via keystone)
└── notes/                       # user's notes repo (synced via cron)

/home/agent-{name}/.keystone/
└── notes/                       # agent's notes repo (synced via cron)
```

## Requirements

### Keystone Home

**REQ-018.1** `~/.keystone/` MUST be the root directory for all
keystone-managed local state (repos, notes). The path MUST be derivable
from the user's home directory, not hardcoded as an absolute path in
scripts.

**REQ-018.2** The keystone home convention MUST apply equally to human
users and OS agents. For agent `drago`, the keystone home is
`/home/agent-drago/.keystone/`.

### Repo Registry

**REQ-018.3** A new option `keystone.repos` MUST declare managed
repositories as an attrset keyed by `owner/repo` (e.g.,
`"ncrmro/keystone"`) with the following per-repo options:
- `url` (string, REQUIRED) — git remote URL
- `flakeInput` (string, nullable, default `null`) — corresponding input
  name in the consumer's `flake.nix`. When set, `ks` generates
  `--override-input` flags in dev mode and locks this input in lock mode.
- `branch` (string, default `"main"`) — default branch for pull/push

**REQ-018.4** All managed repos MUST be cloned to
`~/.keystone/repos/{owner}/{repo}/` following the `owner/repo` key
structure.

**REQ-018.5** The registry MUST support repos that are NOT flake inputs
(e.g., repos used only for project context or reference). These repos
are pulled by `ks update --pull` but skipped during flake lock operations.

**REQ-018.6** The following repos MUST be declared for core keystone
operation:
- `ncrmro/nixos-config` — the consumer NixOS configuration
- `ncrmro/agenix-secrets` — encrypted secrets (`flakeInput: "agenix-secrets"`)
- `ncrmro/keystone` — keystone modules (`flakeInput: "keystone"`)

### Dev Mode

**REQ-018.7** When dev mode is active (`ks build` without `--lock`,
`ks update --dev`), `ks` MUST use local `~/.keystone/repos/{owner}/{repo}/`
directories as `--override-input` for every repo that has a non-null
`flakeInput`, without requiring clean or pushed state.

**REQ-018.7a** When dev mode is active, Home Manager-managed user shell
entrypoints backed by checked-in repo scripts MUST resolve from the local
checkout path instead of immutable Nix store copies. The initial link setup
MUST be performed automatically by NixOS or Home Manager activation.

**REQ-018.7b** After activation, editing a linked repo-backed shell script in
development mode MUST NOT require a rebuild for the change to take effect.

**REQ-018.8** Dev mode MUST NOT modify, commit, or push any managed repo.

**REQ-018.9** `ks doctor` and `ks agent` MUST report dev mode status for
each managed repo: path, branch, dirty state, commits ahead/behind remote.

### Lock Mode

**REQ-018.10** Lock mode (`ks build --lock`, `ks update` default) MUST,
for each repo with a non-null `flakeInput`:
1. Verify the local checkout is clean and fully pushed
2. Push if needed (with fork fallback per REQ-016.9)
3. Run `nix flake update <flakeInput>` to lock the input

**REQ-018.11** Lock mode MUST commit `flake.lock` changes and push
nixos-config only after a successful build (fail-safe ordering).

**REQ-018.12** `ks update --pull` MUST pull ALL managed repos (not just
keystone and agenix-secrets), including repos without a `flakeInput`.

### Notes Under `~/.keystone/`

**REQ-018.13** `keystone.notes.path` (REQ-009.3) MUST default to
`~/.keystone/notes` (currently defaults to `~/notes`).

**REQ-018.14** Agent notes path (`keystone.os.agents.*.notes.path`) MUST
default to `/home/agent-{name}/.keystone/notes` (currently defaults to
`/home/agent-{name}/notes`).

**REQ-018.15** The repo-sync cron job and timer (REQ-009) MUST continue
to function unchanged — only the default path value changes. Existing
users who override `notes.path` MUST NOT be affected.

### Migration from Submodules

**REQ-018.16** `ks` MUST support a migration path from the legacy
submodule layout. If `.submodules/keystone` or `agenix-secrets/` exist
inside the nixos-config repo, `ks` SHOULD emit a deprecation warning and
continue to use them via `--override-input`. `~/.keystone/repos/` MUST
take precedence when both exist.

**REQ-018.17** nixos-config's `flake.nix` MUST reference repos via
remote URLs (GitHub, Forgejo SSH), never via `path:` or
`git+file:...?submodules=1`. Local overrides are applied at build time
via `--override-input`, never baked into `flake.nix`.

### Future: Auto-Fork for Non-Collaborators

**REQ-018.18** (TODO) `ks` commands SHOULD automatically set up forks
for users who are not collaborators on a managed repo, using
`gh repo fork`. The fork remote SHOULD be configured alongside `origin`
so the user can push changes and submit pull requests upstream.

### Integration with Projects (REQ-010)

**REQ-018.19** Project repo declarations (REQ-010.11 `repos:` frontmatter)
SHOULD be resolvable against the `keystone.repos` registry, allowing
projects to reference managed repos by `owner/repo` key rather than
absolute filesystem paths.

## Supersedes

REQ-016.7 through REQ-016.10 (Lock Workflow Enhancement) are superseded
by this spec's repo registry and lock mode requirements (REQ-018.10
through REQ-018.12). REQ-016's dev mode requirements (REQ-016.1 through
REQ-016.6) and agent/doctor awareness (REQ-016.11 through REQ-016.13)
remain in effect.

## Edge Cases

- If `gh` CLI is not available, lock mode MUST fall back to direct
  `git push` and emit a warning if push fails.
- If a managed repo does not exist locally, `ks update --pull` MUST
  clone it. `ks build` MUST skip it with a warning rather than fail.
- Owner names are case-sensitive to match GitHub/Forgejo conventions
  (e.g., `Unsupervisedcom` not `unsupervisedcom`).
- Notes path migration: if `~/notes` exists and `~/.keystone/notes` does
  not, `ks doctor` SHOULD suggest moving the directory.
