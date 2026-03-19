# Keystone Git Workflow

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

**Format**: `<type>([scope]): <description>`

**Types**: `feat`, `fix`, `chore`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `revert`.

**Scopes**: `agent`, `os`, `desktop`, `terminal`, `server`, `tpm`, `cli`.

**Examples**:
```
feat(os): add ZFS auto-scrub scheduling
fix(agent): correct mail password secret path
chore(cli): relock keystone + agenix-secrets
docs(server): document nginx access presets
refactor(terminal): extract shell aliases to module
```

Reference specs in commit messages when applicable:
```
fix(os): [REQ-003] correct Secure Boot key enrollment flow
```

## Branch Naming

Branches should be descriptive and use kebab-case:

```
feat/os-zfs-auto-scrub
fix/agent-mail-password-path
chore/relock-flake-inputs
docs/server-nginx-access-presets
refactor/terminal-shell-aliases
```

For spec-referenced work:
```
feat/req-014-ks-agent-command
```

## Worktree Workflow

When working on a feature that requires isolated builds (e.g., modifying keystone while
also needing to test nixos-config changes), use git worktrees to keep work separate:

```bash
# Create a worktree for a new feature branch
git worktree add ../keystone-feat-foo feat/foo

# Work in the worktree
cd ../keystone-feat-foo
# ... make changes, build, test ...

# Override keystone input in nixos-config to use the worktree
cd ~/nixos-config
ks build --dev  # auto-detects .repos/keystone or .submodules/keystone
```

For changes spanning both keystone and nixos-config:
1. Make changes in the local keystone repo (`.repos/keystone` or `.submodules/keystone`)
2. `ks build --dev` automatically overrides the flake input to use the local clone
3. Once verified, commit and push keystone changes
4. Run `ks update` (lock mode) to relock and deploy

## Pull Request Process

### Keystone Contributions

1. **Branch**: Create a feature branch from `main`
2. **Develop**: Make changes, build with `ks build --dev`, run tests with `make test`
3. **Commit**: Follow conventional commits; keep commits focused and atomic
4. **Push**: `git push -u origin <branch-name>`
5. **PR**: Open a pull request against `main`
   - Title follows conventional commit format
   - Description references any specs (REQ-xxx) or issues
   - Include testing notes (how was this verified?)

### nixos-config Changes

For changes to the nixos-config (not keystone):
1. Branch from `main`
2. Make changes and verify with `ks build --dev`
3. Commit and push — **do not** update `flake.lock` manually
4. `ks update` (lock mode) will pull, lock, build, and deploy in one step

### Flake.lock Updates

`flake.lock` is managed exclusively by `ks update`:
- Never manually run `nix flake update` and commit the result
- `ks update` handles the full cycle: pull → verify → lock → build → push → deploy
- The commit message for flake.lock updates is always: `chore: relock keystone + agenix-secrets`

## Code Comment Conventions

### File-Level Documentation

Every non-trivial file starts with a header block:
- **What** the module does
- **Security model** (if applicable)
- **Usage examples**

For Nix files, use a `#` comment block at the top of the file.

### Inline Comment Prefixes

| Prefix | Meaning |
|--------|---------|
| `# SECURITY:` | Security-critical decision; name the specific threat being mitigated |
| `# CRITICAL:` | Cross-module invariant that breaks silently if violated |
| `# TODO:` | Known gap with consequences explained |

Comments should explain **why**, not **what** — code is self-documenting; comments explain
the rationale for non-obvious choices.

## Linting and Testing

Before opening a PR:

```bash
make fmt          # Format Nix files
make test         # Run NixOS integration tests
make ci           # Full CI check (fmt + test)
```

Build and smoke-test locally first:
```bash
ks build --dev           # Build only (no deploy)
ks update --dev          # Build and deploy locally (dev mode)
ks update --dev --boot   # Apply on next reboot
```
