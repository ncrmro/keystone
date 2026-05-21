# Keystone

@CONTRIBUTOR.md — development workflow, verification commands, and deployment flow

Keystone is a NixOS-based self-sovereign infrastructure platform for deploying secure,
encrypted infrastructure on any hardware. It provides declarative modules for OS
configuration, desktop environments, terminal tooling, and server services.

## Fleet model

A keystone system is a **fleet of hosts configured as a whole** in a single
git-committed consumer flake (e.g., `nixos-config` or `keystone-config`).
Enabling a service wires up both the server and its clients across the fleet.
A typical deployment:

- **Workstation** — primary desktop, GPU, agents, full development environment
- **Laptop** — thin client, remotes into workstation via SSH or Eternal Terminal
- **Server/NAS** — headless services (Forgejo, Grafana, Immich, mail, DNS, monitoring)
- **Offsite/VPS** — backup target, public-facing reverse proxy, or Headscale coordinator

`ks update --lock` deploys the current host by default. Pass a comma-separated
list to deploy multiple: `ks update --lock ocean,mercury`.

## Modules

- `modules/os/` — Core OS: storage, Secure Boot, TPM, users, SSH, agents, containers, Tailscale
- `modules/os/agents/` — Autonomous agent service accounts: task loop, scheduler, desktop, mail
- `modules/terminal/` — Home-manager terminal: shell, editor, AI tools, mail, calendar, DeepWork
- `modules/desktop/` — Hyprland desktop environment: theming, keybindings, components
- `modules/server/` — Server services: DNS, mail, monitoring, Forgejo, Grafana, Immich, Vaultwarden
- `modules/notes/` — Zettelkasten notebook management via zk

## Packages

- `packages/ks/` — Keystone CLI/TUI: build, deploy, notifications, tasks, projects, doctor
- `packages/fetch-email-source/` — Email notification fetcher (himalaya)
- `packages/fetch-github-sources/` — GitHub notification fetcher (gh API)
- `packages/fetch-forgejo-sources/` — Forgejo notification fetcher (curl)
- `packages/keystone-ha/` — Home-assistant integration
- `packages/ks-legacy/` — Legacy shell-based ks commands

## Flake Exports

### NixOS Modules (`keystone.nixosModules.*`)

| Module | Description |
|---|---|
| `operating-system` | Core OS — storage, Secure Boot, TPM, users, agents (includes disko + lanzaboote) |
| `server` | Server services (includes domain) |
| `desktop` | Hyprland desktop environment |
| `binaryCacheClient` | Attic binary cache client |
| `hardwareKey` | YubiKey/FIDO2 support |
| `isoInstaller` | Bootable installer |
| `experimental` | Experimental feature flag (`keystone.experimental`) |
| `domain`, `hosts`, `repos`, `services`, `keys` | Shared options modules |
| `headscale-dns` | Consume server DNS records on headscale host |

### Home-Manager Modules (`keystone.homeModules.*`)

`terminal`, `desktop`, `desktopHyprland`, `notes`

### Overlay (`pkgs.keystone.*`)

`claude-code`, `gemini-cli`, `codex`, `opencode`, `deepwork`, `keystone-deepwork-jobs`,
`keystone-conventions`, `chrome-devtools-mcp`, `grafana-mcp`, `google-chrome`, `ghostty`,
`yazi`, `himalaya`, `calendula`, `cardamum`, `comodoro`, `cfait`, `agenix`, `slidev`

## Important Notes

- ZFS pool is **always** named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- Terminal and desktop modules are home-manager based, not NixOS system modules
- `keystone.repos` auto-populates from flake inputs; `keystone.development` enables local checkout paths
- `keystone.experimental` (default `false`) gates experimental features. Defined in `modules/shared/experimental.nix`.

## Keystone Config Repo

The **keystone config repo** is `nixos-config` — the consumer flake that imports keystone
modules and declares per-host/per-user configuration. All keystone-managed repos live
under `~/.keystone/repos/OWNER/REPO/`.

## Pull request workflow

Agents shepherd PRs end-to-end per the `process.pr-shepherding` skill
(24 rules covering draft delivery, CI stabilization, Copilot iteration,
merge queue, post-merge verification). The operational loop has three
stages.

### Stage 1 — Draft

```bash
gh pr create --draft --title "type(scope): subject" --body "...Closes #N..."
gh pr checks --watch                 # watch PR-event CI to green
```

PR-event CI runs the cheap checks for fast feedback: `changes`, `eval`,
`ks`, `scripts`, `desktop`, `agents`, `nixfmt`, `shellcheck`,
`warm-cache`. The expensive `iso-build` is deferred to the merge queue
(Stage 3) and will appear `skipping` on PR-event runs — that is
expected.

Do NOT undraft while CI is failing or in progress.

### Issue and milestone linkage

Every PR MUST link to its originating issue and, when one exists for
the current work stream, be assigned to the milestone — milestones
are the unit of stakeholder-visible progress and an unassigned PR is
invisible on the project board.

```bash
# Issue linkage lives in the PR body. Use a closing keyword
# (Closes / Fixes / Resolves) ONLY if this PR fully resolves the issue;
# the forge auto-closes the issue on merge. For partial work or PRs
# under a tracking issue / epic, use a plain reference instead so the
# issue stays open after merge:
gh pr edit <PR> --body "...Closes #N..."         # full resolution
gh pr edit <PR> --body "...Part of #N..."        # partial / epic

# Milestone assignment is a separate field — no closing keyword in
# the body. Set it on both the PR and its originating issue:
gh pr edit <PR> --milestone "<milestone name>"
gh issue edit <ISSUE> --milestone "<milestone name>"
```

Cross-repo references MUST use `owner/repo#N`; bare `#N` is ambiguous.
If no milestone fits, check with the product agent before creating one
— milestones are a product artifact, not an engineering convenience.
Merging a PR does not close its milestone; the forge closes a milestone
only when every contained issue is closed.

### Stage 2 — Ready for review + Copilot

```bash
gh pr ready <PR>
gh pr edit <PR> --add-reviewer copilot-pull-request-reviewer
```

After Copilot files inline comments, address each on a follow-up commit
with the conventional subject `<type>(scope): address Copilot review on
PR #<PR>` (or `address post-merge Copilot review on PR #<PR>` for issues
caught after a fast merge). Reply on the PR thread for each comment,
then push and re-watch CI to green before re-requesting review.

### Stage 3 — Merge queue

```bash
gh pr merge <PR> --auto --squash --delete-branch

gh run list --event merge_group --limit 3       # find the queue run
gh run watch <RUN_ID>                           # watch it to completion
gh run view <RUN_ID> --log-failed               # if iso-build or another
                                                # merge_group check fails
# Fix, push — the merge queue automatically re-queues.

gh pr view <PR> --json state,mergedAt           # verify merge landed
```

`iso-build` only runs under the `merge_group` event, against the final
merged tree. Required gating checks for merge: all of the PR-event
checks plus `iso-build` under merge_group.

After the PR exits the queue, verify the default-branch CI is green on
the merge commit.
