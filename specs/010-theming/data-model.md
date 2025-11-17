# Data Model: Dynamic Theming System

**Feature**: 010-theming
**Date**: 2025-11-07
**Purpose**: Define entities and their relationships for Omarchy theming integration

## Overview

The theming system manages visual configuration across terminal applications using a filesystem-based model with symlinks for active theme selection. This model is intentionally simple - themes are directories of configuration files, not database records or complex objects.

## Entity Definitions

### Theme

**Description**: A directory containing application-specific configuration files that define visual styling

**Location**: `~/.config/omarchy/themes/<theme-name>/`

**Structure**:
```
<theme-name>/
├── helix.toml           # Helix editor configuration (optional)
├── ghostty.conf         # Ghostty terminal configuration (optional)
├── neovim.lua           # Neovim configuration (optional, not used in Keystone)
├── btop.theme           # System monitor theme (optional)
├── hyprland.conf        # Compositor configuration (optional, future use)
├── waybar.css           # Status bar styling (optional, future use)
├── backgrounds/         # Wallpaper images (optional)
│   └── *.png, *.jpg
└── preview.png          # Theme preview image (optional)
```

**Attributes**:
- `name` (string): Theme directory name, derived from directory name
- `path` (absolute path): Full path to theme directory
- `available_configs` (set of strings): Which application config files exist in this theme

**Validation Rules**:
- Directory MUST exist in `~/.config/omarchy/themes/`
- No specific files are required (themes can be partial)
- Directory name MUST NOT contain path separators or special shell characters

**State Transitions**: None (themes are immutable after installation)

**Lifecycle**:
- **Created**: Via `omarchy-theme-install <repo-url>` or Nix installation
- **Updated**: By reinstalling same theme name (replaces directory)
- **Deleted**: Manual removal of directory or `omarchy-theme-remove` (if implemented)
- **Activated**: By updating `current/theme` symlink to point to this theme

### Theme Registry

**Description**: Collection of all installed themes, represented as a directory hierarchy

**Location**: `~/.config/omarchy/themes/`

**Structure**:
```
themes/
├── default/             # Default theme (installed by Nix)
│   ├── helix.toml
│   └── ghostty.conf
├── catppuccin/          # User-installed theme
│   ├── helix.toml
│   ├── ghostty.conf
│   └── backgrounds/
└── gruvbox/             # User-installed theme
    ├── helix.toml
    └── ghostty.conf
```

**Attributes**:
- `path` (absolute path): `~/.config/omarchy/themes/`
- `themes` (list of Theme): All subdirectories that are valid themes

**Validation Rules**:
- Directory MUST be writable by user
- Each subdirectory represents a potential theme
- No maximum theme count (limited only by filesystem)

**Operations**:
- **List themes**: `ls ~/.config/omarchy/themes/`
- **Add theme**: Create new subdirectory with config files
- **Remove theme**: Delete subdirectory

### Active Theme

**Description**: The currently selected theme, indicated by a symlink

**Location**: `~/.config/omarchy/current/theme` (symlink)

**Target**: Points to one of the themes in `~/.config/omarchy/themes/<theme-name>/`

**Attributes**:
- `symlink_path` (absolute path): `~/.config/omarchy/current/theme`
- `target_theme` (Theme): The theme this symlink points to
- `resolved_path` (absolute path): Result of following the symlink

**Validation Rules**:
- Symlink MUST point to valid theme directory
- If symlink is broken or missing, system should recreate pointing to default theme
- Symlink MUST be readable by all applications

**State Transitions**:
```
[None] --[initial activation]--> [default theme]
[theme-a] --[omarchy-theme-next]--> [theme-b]
[theme-a] --[omarchy-theme-set theme-c]--> [theme-c]
[broken] --[validation]--> [default theme]
```

**Lifecycle**:
- **Created**: During home-manager activation if not present
- **Updated**: Via theme-next, theme-set, or theme-install commands
- **Validated**: On each system rebuild (recreated if broken)
- **Preserved**: Never overwritten by Nix rebuilds (user state)

### Omarchy Binary

**Description**: Executable bash script for theme management operations

**Location**: `~/.local/share/omarchy/bin/<script-name>`

**Available Binaries**:
- `omarchy-theme-next`: Cycle to next theme alphabetically
- `omarchy-theme-set <name>`: Set specific theme by name
- `omarchy-theme-install <url>`: Install theme from git repository
- Other utilities: May include theme-bg-next, theme-remove, etc.

**Attributes**:
- `name` (string): Binary filename
- `path` (absolute path): Full path to executable
- `source` (Nix derivation path): Location in Nix store
- `permissions` (octal): Must be executable (755)

**Validation Rules**:
- Binary MUST be executable by user
- Binary MUST be in PATH (via `~/.local/share/omarchy/bin`)
- Binary source MUST come from Omarchy flake input (no local modifications)

**Operations**:
- **Install**: Copy from Omarchy source to `~/.local/share/omarchy/bin/` via `home.file`
- **Execute**: Run directly from shell (in PATH)
- **Update**: Re-copy from updated Omarchy source on rebuild

### Application Theme Configuration

**Description**: Application-specific config file loaded from active theme

**Location**: `~/.config/omarchy/current/theme/<app-config-file>`

**Examples**:
- Helix: `~/.config/omarchy/current/theme/helix.toml`
- Ghostty: `~/.config/omarchy/current/theme/ghostty.conf`

**Attributes**:
- `application` (enum): Which application this config belongs to {helix, ghostty, lazygit, ...}
- `config_file` (relative path): Filename within theme directory
- `full_path` (absolute path): Resolved path through symlink
- `exists` (boolean): Whether file exists in active theme

**Validation Rules**:
- File MUST be readable by application
- File format MUST match application's expected configuration syntax
- Missing file is acceptable (application uses defaults)

**Integration Patterns**:

**Helix**:
```toml
# Base helix config managed by Nix
[editor]
line-number = "relative"

# Theme config included from omarchy
# (Method TBD: could be theme = "omarchy-current" or include directive)
```

**Ghostty**:
```
# Base ghostty config managed by Nix
font-size = 12

# Include theme configuration
config-file = ~/.config/omarchy/current/theme/ghostty.conf
```

**Lifecycle**:
- **Accessed**: When application starts and loads configuration
- **Changed**: When active theme symlink is updated
- **Applied**: On next application restart (no hot-reload)

## Entity Relationships

```
┌─────────────────────────────────────────┐
│        Theme Registry                   │
│  (~/.config/omarchy/themes/)            │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │  Theme   │  │  Theme   │  ... (1:N) │
│  │ default/ │  │ custom/  │            │
│  └──────────┘  └──────────┘            │
└─────────────────────────────────────────┘
                    ▲
                    │
                    │ points to (1:1)
                    │
            ┌───────────────┐
            │ Active Theme  │
            │ (symlink)     │
            └───────────────┘
                    │
                    │ contains (1:N)
                    ▼
    ┌──────────────────────────────────┐
    │  Application Theme Configurations │
    │                                   │
    │  - helix.toml                    │
    │  - ghostty.conf                  │
    │  - lazygit.yml (future)          │
    └──────────────────────────────────┘
                    │
                    │ read by (N:N)
                    ▼
        ┌─────────────────────────┐
        │   Applications          │
        │                         │
        │  - Helix Editor         │
        │  - Ghostty Terminal     │
        │  - Lazygit (future)     │
        └─────────────────────────┘


┌────────────────────────────────┐
│   Omarchy Binaries             │
│   (~/.local/share/omarchy/bin/)│
│                                │
│   - omarchy-theme-next         │
│   - omarchy-theme-set          │
│   - omarchy-theme-install      │
└────────────────────────────────┘
            │
            │ manipulates (N:1)
            ▼
    ┌───────────────┐
    │ Active Theme  │
    │ (symlink)     │
    └───────────────┘
```

**Relationship Cardinalities**:
- Theme Registry : Theme = 1 : N (one registry contains many themes)
- Active Theme : Theme = 1 : 1 (symlink points to exactly one theme)
- Theme : Application Config = 1 : N (one theme can have configs for multiple apps)
- Application Config : Application = 1 : 1 (each config file is for one app)
- Omarchy Binary : Active Theme = N : 1 (multiple binaries manipulate single active theme symlink)

## Data Flow

### Theme Installation Flow

```
User runs: omarchy-theme-install <repo-url>
                    │
                    ▼
         ┌──────────────────────┐
         │  git clone repo to   │
         │  ~/.config/omarchy/  │
         │  themes/<name>/      │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Call                │
         │  omarchy-theme-set   │
         │  <name>              │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Update symlink:     │
         │  current/theme ->    │
         │  themes/<name>/      │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Send notification:  │
         │  "Theme set to       │
         │   <name>"            │
         └──────────────────────┘
```

### Theme Switching Flow

```
User runs: omarchy-theme-next
                    │
                    ▼
         ┌──────────────────────┐
         │  List themes in      │
         │  ~/.config/omarchy/  │
         │  themes/             │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Read current theme  │
         │  from symlink        │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Calculate next      │
         │  theme (with wrap)   │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Update symlink to   │
         │  next theme          │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Send notification   │
         └──────────────────────┘
```

### Application Configuration Loading Flow

```
User starts Helix/Ghostty
                    │
                    ▼
         ┌──────────────────────┐
         │  Load base config    │
         │  from Nix-managed    │
         │  paths               │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Check for theme     │
         │  config via symlink  │
         │  current/theme/      │
         │  <app>.conf          │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  If exists, merge/   │
         │  include theme       │
         │  settings            │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Apply final         │
         │  configuration       │
         └──────────────────────┘
```

### System Rebuild Flow (Theme Persistence)

```
User runs: nixos-rebuild / home-manager switch
                    │
                    ▼
         ┌──────────────────────┐
         │  Nix evaluates       │
         │  configuration       │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Install theme       │
         │  sources to          │
         │  themes/ directory   │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Install omarchy     │
         │  binaries            │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Run activation      │
         │  script              │
         └──────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Check if            │
         │  current/theme       │
         │  symlink exists      │
         └──────────────────────┘
                    │
            ┌───────┴───────┐
            │               │
          Yes              No
            │               │
            ▼               ▼
    ┌───────────────┐  ┌──────────────┐
    │  SKIP         │  │  Create      │
    │  (preserve    │  │  symlink to  │
    │   user        │  │  default     │
    │   choice)     │  │  theme       │
    └───────────────┘  └──────────────┘
            │               │
            └───────┬───────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  User's theme        │
         │  selection           │
         │  preserved!          │
         └──────────────────────┘
```

## Constraints and Invariants

### Filesystem Constraints

1. **XDG Compliance**: All paths use XDG base directory specification
   - Config: `${XDG_CONFIG_HOME}/omarchy` (default: `~/.config/omarchy`)
   - Data: `${XDG_DATA_HOME}/omarchy` (default: `~/.local/share/omarchy`)

2. **Symlink Atomicity**: Theme switching updates must be atomic
   - Use `ln -sf` to ensure atomic symlink replacement
   - No intermediate broken symlink state

3. **Directory Permissions**: All omarchy directories must be user-writable
   - Themes directory: 755 (user writable, world readable)
   - Binaries directory: 755 (user writable, world readable + executable)
   - Config files: 644 (user writable, world readable)

### Data Invariants

1. **Active Theme Validity**: Active theme symlink MUST either:
   - Point to valid theme directory in themes/, OR
   - Not exist (will be created on next activation)

2. **Theme Completeness**: NOT ENFORCED
   - Themes may contain any subset of application configs
   - Applications gracefully degrade to defaults if config missing

3. **Binary Immutability**: Omarchy binaries MUST NOT be modified locally
   - Source of truth is Omarchy flake input
   - Any changes applied via Nix rebuild, not manual editing

4. **State Separation**:
   - Theme sources = declarative (managed by Nix)
   - Active theme selection = imperative (managed by user via symlink)
   - This separation is intentional and must be preserved

## Example State Representations

### Initial State (Fresh Installation)

```
~/.config/omarchy/
├── themes/
│   └── default/
│       ├── helix.toml
│       └── ghostty.conf
└── current/
    └── theme -> ../themes/default

~/.local/share/omarchy/
├── bin/
│   ├── omarchy-theme-next
│   ├── omarchy-theme-set
│   └── omarchy-theme-install
└── logo.txt
```

### State After Installing Custom Theme

```
~/.config/omarchy/
├── themes/
│   ├── default/
│   │   ├── helix.toml
│   │   └── ghostty.conf
│   └── catppuccin/
│       ├── helix.toml
│       ├── ghostty.conf
│       ├── hyprland.conf
│       └── backgrounds/
│           └── wallpaper.png
└── current/
    └── theme -> ../themes/catppuccin
```

### State After Theme Cycling

```
~/.config/omarchy/
├── themes/
│   ├── catppuccin/     # Previous active
│   ├── default/        # Skipped
│   └── gruvbox/        # Now active
└── current/
    └── theme -> ../themes/gruvbox
```

## Schema Evolution

### Adding New Applications

To add support for a new application (e.g., adding lazygit support):

1. Update Application Theme Configuration entity with new application type
2. Add new config file pattern (e.g., `lazygit.yml`)
3. Extend terminal.nix module to include new application config
4. No changes needed to Theme, Active Theme, or Binary entities

### Adding New Theme Management Commands

To add new omarchy binaries (e.g., omarchy-theme-remove):

1. Omarchy upstream adds binary to their repository
2. Keystone updates omarchy flake input version
3. Binary automatically discovered via `builtins.readDir` in binaries.nix
4. No schema changes needed - system is self-extending

### Migration from Current State

N/A - This is a new feature with no existing state to migrate.

## Conclusion

The data model is intentionally minimal and filesystem-centric. Entities are represented as directories and files rather than database records, making the system:

1. **Transparent**: Users can inspect and modify themes directly
2. **Portable**: Themes can be shared via git repositories
3. **Resilient**: No database corruption risk, worst case is broken symlink
4. **Debuggable**: `ls` and `readlink` commands reveal full system state

This aligns with NixOS's declarative, filesystem-based approach to configuration management.
