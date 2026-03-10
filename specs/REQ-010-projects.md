# REQ-010: Projects

Home Manager module (`keystone.projects`) for managing per-project working
environments with terminal sessions, AI agent integration, and optional
desktop launcher support. Portable across NixOS and macOS.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Standard

**REQ-010.1** A project MUST be a directory at `{notes_path}/projects/{slug}/`
containing a `README.md` file.

**REQ-010.2** Project slugs MUST be lowercase, hyphen-separated strings
(e.g., `nixos-config`, `plant-caravan`).

**REQ-010.3** Directories matching `_archive/` or starting with `_` MUST be
excluded from project discovery.

### Discovery

**REQ-010.4** The module MUST discover projects by scanning
`{notes_path}/projects/*/README.md`, deriving the notes path from
`keystone.notes.path` (see REQ-009).

**REQ-010.5** The module MUST expose `keystone.projects.enable` (bool,
default `false`) to activate project management. When enabled,
`keystone.notes.enable` MUST also be `true`.

### Sessions

**REQ-010.6** The module MUST provide a `pz` command that creates or attaches
to a Zellij session named `{prefix}-{slug}` for a given project slug.

**REQ-010.7** The module MUST expose `keystone.projects.sessionPrefix`
(string, default `obs`) for the Zellij session name prefix.

**REQ-010.8** A `pz` session MUST persist across terminal disconnections.
Re-running `pz {slug}` MUST attach to the existing session rather than
creating a new one.

### Environment

**REQ-010.9** Inside a project session, the module MUST export the following
environment variables: `PROJECT_NAME` (slug), `PROJECT_PATH` (absolute path
to project directory), `PROJECT_README` (path to `README.md`), `VAULT_ROOT`
(notes repo root), `CLAUDE_CONFIG_DIR` (project-scoped Claude configuration
directory), and `AGENTS_MD` (path to aggregated agents context file).

**REQ-010.10** The module MUST create a project-scoped Claude configuration
directory at `{notes_path}/.claude-projects/{slug}/` and symlink shared
credentials from the user's home directory.

### Repo Declarations

**REQ-010.11** Projects MAY declare associated repositories via a `repos:`
list in the README.md YAML frontmatter.

**REQ-010.12** When `repos:` is declared, the module MUST aggregate
`AGENTS.md` files from each declared repository into a single context file
available at `$AGENTS_MD`.

### AI Agent Integration

**REQ-010.13** The module MUST provide a `pclaude` command that launches
Claude Code scoped to the current project context (environment variables,
configuration directory, and system prompt).

**REQ-010.14** The `pclaude` command MUST support a `--resume <session-id>`
flag to continue an existing Claude Code session.

**REQ-010.15** The `pclaude` command MUST render a project-specific system
prompt template via `envsubst`, using the environment variables from
REQ-010.9.

**REQ-010.16** OS agents (see SPEC-007) MUST be able to use the same project
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
