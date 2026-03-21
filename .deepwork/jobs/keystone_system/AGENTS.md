# Keystone System Job

This job manages the keystone NixOS module development lifecycle.

## Slash Commands

The workflows are accessible as Claude Code slash commands:

- `/ks.develop <goal>` — Full development lifecycle (plan → implement → review → build → merge → deploy → validate)
- `/ks.convention <topic>` — Create or update a convention (draft → cross-reference → apply → commit to main)
- `/ks.doctor [context]` — Standalone fleet health check across all hosts

See `.claude/commands/ks.develop.md`, `.claude/commands/ks.convention.md`, and `.claude/commands/ks.doctor.md`.

## Workflows

| Workflow | Steps | Purpose |
|----------|-------|---------|
| `develop` | plan → implement → review → build → merge → deploy → validate | Full lifecycle |
| `convention` | draft_convention → cross_reference → apply_convention → commit_convention | Convention CRUD |
| `doctor` | validate | Standalone fleet health check |

## Key Conventions

- **All work in worktrees**: Never commit directly to main. See `steps/plan.md` for branch naming.
- **Fast-path builds**: Use `ks build` (home-manager only) when changes don't touch OS modules. See `steps/build.md` for the tiered verification strategy.
- **Multi-host validation**: After deploy, check ALL affected hosts, not just the current one. See `steps/validate.md`.
- **Human-in-the-loop deploy**: Only `steps/deploy.md` requires sudo — everything else is agent-driven.

## Bespoke Learnings

### v1.1.0 — Initial creation (2026-03-20)

- The workflow is designed for non-trivial multi-step development. Trivial 1-line fixes (like the SC2155 shellcheck fix) can bypass the workflow.
- `nix-instantiate --parse` only works on `.nix` files — don't use it for shell scripts. Use `shellcheck` for `.sh` files.
- After merge, worktrees are cleaned up. If validation fails and requires a fix, a new worktree is created via the plan step — this is by design (clean worktree per change).

### v1.2.0 — Doctor run learnings (2026-03-20)

- The validate step must check **agent health**, not just host services. Use `agentctl <agent> status/tasks/email` and check Tailscale status for offline agents.
- Tailscale offline agents (e.g., agent-drago offline 13d) should be flagged as needing attention.

### v1.4.0 — Convention workflow (2026-03-21)

- The convention workflow commits directly to main (no worktree) because conventions are documentation files.
- Cross-reference bidirectionality is enforced by the quality gate — if convention A references B, B must reference A.
- When pushing to main, the remote may have new commits from other workflows. The commit step must handle rebase (stash → pull --rebase → stash pop → push).
- When asking which archetypes to wire into, show the user which roles already reference related conventions to help them make informed placement decisions.
- The convention workflow scanned 38 conventions for overlap on first test — the cross-reference step is thorough but found only 2 cross-ref opportunities (no duplicates), which is expected for a genuinely new domain.

## Nix Eval for System Context

The standard way to get hosts/users/agents/services is via `nix eval` against `~/.keystone/repos/nixos-config`. This is the canonical path — agents MUST use this, not hardcoded paths.

### Agents (compact)
```bash
nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.agents \
  --json --apply 'a: builtins.mapAttrs (_: v: {
    fullName = v.fullName; host = v.host or null;
    archetype = v.archetype; desktop = v.desktop.enable;
    mail = v.mail.provision; chrome = v.chrome.enable;
  }) a'
```

### Users (compact)
```bash
nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.users \
  --json --apply 'u: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; }) u'
```

### Hosts
```bash
nix eval -f ~/.keystone/repos/nixos-config/hosts.nix --json
```

### Enabled Services
```bash
nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.server._enabledServices \
  --json 2>/dev/null
```

Replace `<HOST>` with the host key from `hosts.nix` (e.g., `ncrmro-workstation`, `ocean`).

**Future improvement**: These evals should be wrapped into a single `ks status` command. See `packages/ks/ks.sh:770` (`build_user_table`) for the existing partial implementation.

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
3. **Run `/deepwork learn`** after executing the workflow to capture new learnings
