# REQ-010: Projects

Home Manager module (`keystone.projects`) for managing per-project working
environments with terminal sessions, AI agent integration, and optional
desktop launcher support. Portable across NixOS and macOS.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Standard

**REQ-010.1** An active project MUST have exactly one active hub note in
`index/` with `type: index`, `status/active`, a canonical project slug in
frontmatter and tags, and a `repos:` frontmatter list when the project uses one
or more VCS repositories.

**REQ-010.2** Project slugs MUST be lowercase, hyphen-separated strings
(e.g., `nixos-config`, `plant-caravan`).

**REQ-010.3** Archived or inactive hub notes MUST be excluded from project
discovery.

### Discovery

**REQ-010.4** The module MUST discover projects via
`zk --notebook-dir {notes_path} list index/ --tag "status/active" --format json`,
deriving the notes path from `keystone.notes.path` (see REQ-009).

**REQ-010.5** The module MUST expose `keystone.projects.enable` (bool,
default `true`) to activate project management. When enabled,
`keystone.notes.enable` MUST also be `true`.

### Sessions

**REQ-010.6** The module MUST provide a `pz` command that creates or attaches
to a Zellij session named `{slug}` for the default project session or
`{slug}-{session-slug}` for a named project session.

**REQ-010.8** A `pz` session MUST persist across terminal disconnections.
Re-running `pz {slug}` MUST attach to the existing session rather than
creating a new one.

### Environment

**REQ-010.9** Inside a project session, the module MUST export the following
environment variables: `PROJECT_NAME` (slug), `PROJECT_PATH` (absolute path
to the legacy project directory when present), `PROJECT_README` (path to the
legacy `README.md` when present), `VAULT_ROOT` (notes repo root),
`CLAUDE_CONFIG_DIR` (project-scoped Claude configuration directory), and
`AGENTS_MD` (path to aggregated agents context file).

**REQ-010.10** The module MUST create a project-scoped Claude configuration
directory at `{notes_path}/.claude-projects/{slug}/` and symlink shared
credentials from the user's home directory.

### Repo Declarations

**REQ-010.11** Active project hub notes MUST declare associated repositories via
a `repos:` frontmatter list when the project uses one or more VCS repositories.
The hub note is the source of truth for project-to-repo relationships for both
humans and agents.

**REQ-010.12** Each `repos:` entry MUST be a full remote repository URL. SSH and
HTTPS forms are both valid, including GitHub and Forgejo URLs such as
`git@github.com:ncrmro/website.git` and
`ssh://forgejo@git.ncrmro.com:2222/drago/notes.git`.

**REQ-010.12a** Tooling that consumes `repos:` MUST normalize each supported
remote URL into a canonical `owner/repo` identifier by stripping scheme, user,
host, port, and an optional `.git` suffix. Malformed or unsupported URLs MUST
fail validation instead of being guessed.

**REQ-010.12b** Repo-scoped note tags and local checkout conventions MUST be
derived from the normalized `owner/repo` identifier, not handwritten as
alternate forms.

**REQ-010.12c** When `repos:` is declared, the module MUST aggregate
`AGENTS.md` files from each declared repository into a single context file
available at `$AGENTS_MD`.

### AI Agent Integration

**REQ-010.13** The module MUST provide a `pz agent` command that wraps
`agentctl`, automatically injecting the current project's slug via the
`--project` flag when executed within a project session.

**REQ-010.14** The `pz agent` command MUST support passing arbitrary
arguments and subcommands to the underlying `agentctl` execution.

**REQ-010.15** OS agents (see SPEC-007) MUST be able to use the same project
system without desktop integration, operating in headless mode.

### Tab Completion

**REQ-010.17** The module MUST provide shell completion for `pz` in both
Bash and Zsh, completing project slugs discovered at runtime from the
notes directory.

### Desktop Integration (Optional)

**REQ-010.18** When `keystone.desktop` is enabled, a Walker plugin SHOULD
read from `keystone.notes` configuration to discover projects and present
them as launchable items alongside desktop applications.

**REQ-010.19** When `keystone.desktop` is enabled, the keystone menu
(mod+escape) SHOULD include a "Projects" submenu listing discovered
projects.

**REQ-010.20** Selecting a project from Walker or the keystone menu MUST
open a terminal with the corresponding Zellij session (equivalent to
running `pz {slug}`).

### Portability

**REQ-010.21** The module MUST NOT require NixOS or Hyprland. Desktop
integration (REQ-010.18 through REQ-010.20) is OPTIONAL and MUST degrade
gracefully when desktop features are unavailable.
