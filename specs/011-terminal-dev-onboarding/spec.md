# Feature Specification: Terminal Development Environment Onboarding

**Feature Branch**: `011-terminal-dev-onboarding`
**Created**: 2025-11-09
**Status**: Draft
**Input**: Create a specification for terminal dev environment onboarding/tips that show up in the user's shell. It shows how to use z, zi and zs (zoxide) for quick directory navigation. When the shell loads, if a command has been seen enough times the help text will automatically disappear.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First-Time Shell Experience (Priority: P1)

A new Keystone user opens their terminal for the first time and sees helpful onboarding tips that teach them about the most essential navigation commands (z, zi) and keyboard shortcuts, allowing them to become productive immediately without reading extensive documentation.

**Why this priority**: First-time user experience is critical for adoption. Without guidance, users may not discover powerful productivity features like zoxide navigation, leading to frustration and underutilization of the terminal dev environment.

**Independent Test**: Can be fully tested by creating a fresh user profile, opening a shell, and verifying that onboarding tips are displayed with clear, actionable information about essential commands.

**Acceptance Scenarios**:

1. **Given** a user opens a shell for the first time, **When** the zsh session initializes, **Then** a welcome message with essential tips is displayed before the prompt
2. **Given** the onboarding tips are displayed, **When** the user reads the tips, **Then** they learn about `z <dir>` for quick directory jumping and `zi` for interactive directory selection
3. **Given** onboarding tips are shown, **When** the user sees them, **Then** the tips include information about the most frequently used aliases (hx, lg, l)
4. **Given** tips are displayed, **When** the user views them, **Then** a subtle note indicates that tips will automatically disappear after being seen multiple times
5. **Given** the user views the tips, **When** the shell session ends, **Then** the view count is persisted for the next session

---

### User Story 2 - Progressive Tip Dismissal (Priority: P2)

A user who has seen the onboarding tips multiple times (5+ shell sessions) no longer sees them automatically, reducing visual clutter while still being able to recall tips on demand if needed.

**Why this priority**: Repeated tips become noise for experienced users. Progressive dismissal ensures new users get help while experienced users have a clean terminal experience.

**Independent Test**: Can be tested by opening and closing shells multiple times, verifying tips disappear after a threshold, and confirming tips can be manually re-displayed.

**Acceptance Scenarios**:

1. **Given** a user has opened their shell 5 times, **When** they open the shell for the 6th time, **Then** onboarding tips are no longer automatically displayed
2. **Given** tips have been auto-dismissed, **When** the user runs `keystone-tips` or similar command, **Then** all tips are displayed on demand
3. **Given** tips have been dismissed, **When** the user runs `keystone-tips reset`, **Then** the view count is reset and tips will appear on next shell load
4. **Given** a user wants to disable tips permanently, **When** they run `keystone-tips disable`, **Then** tips never appear automatically (even at 0 view count)
5. **Given** tips are disabled, **When** the user runs `keystone-tips enable`, **Then** tips can appear automatically again based on view count

---

### User Story 3 - Contextual Navigation Tips (Priority: P3)

A user learns about zoxide navigation features progressively: first learning basic `z <dir>` jumping, then discovering `zi` for interactive selection, and optionally learning about `zs` for query-based search, with each tip building on previous knowledge.

**Why this priority**: While helpful, layered learning is less critical than basic onboarding. Users can discover advanced features through exploration or on-demand help.

**Independent Test**: Can be tested by tracking which tips have been shown and verifying that zoxide tips build progressively (basic → interactive → advanced).

**Acceptance Scenarios**:

1. **Given** a user sees tips for the first time, **When** zoxide tips are displayed, **Then** the basic `z <directory-name>` command is explained with a simple example
2. **Given** a user has seen basic zoxide tips 2+ times, **When** tips are displayed, **Then** the `zi` interactive selector is introduced as a next step
3. **Given** a user has used the shell 5+ times, **When** tips are displayed, **Then** advanced zoxide features like `z -` (go back) are explained
4. **Given** a user views zoxide tips, **When** the tips are shown, **Then** practical examples are included (e.g., "Try: z keystone → jumps to /home/user/keystone")
5. **Given** multiple navigation tools exist, **When** tips explain zoxide, **Then** they clarify when to use zoxide vs cd vs directory bookmarks

---

### User Story 4 - Tool Discovery Tips (Priority: P3)

A user discovers other terminal dev environment tools (helix shortcuts, lazygit, zellij) through progressive tips that appear after navigation tips have been learned, avoiding information overload.

**Why this priority**: Tool discovery enhances productivity but is not essential for basic terminal use. Users can function effectively with just navigation knowledge.

**Independent Test**: Can be tested by progressing through tip stages and verifying that tool-specific tips appear only after foundational tips have been dismissed.

**Acceptance Scenarios**:

1. **Given** navigation tips have been seen 5+ times, **When** the user opens a shell, **Then** tips shift focus to editor shortcuts (helix keybindings)
2. **Given** a user has dismissed navigation tips, **When** tool tips are shown, **Then** they learn about `lg` (lazygit) for git operations
3. **Given** tool tips are displayed, **When** the user views them, **Then** zellij multiplexer basics are explained (if not already running in zellij)
4. **Given** multiple tool categories exist, **When** tips rotate, **Then** only one category of tips is shown per session to avoid overwhelming the user

---

### Edge Cases

- What happens when a user's shell state file is deleted or corrupted (tip counter lost)?
- How does the system handle multiple concurrent shell sessions (race condition on counter updates)?
- What happens when tips are configured but zoxide or other tools are disabled?
- How does the system behave in non-interactive shells (scripts, SSH commands, etc.)?
- What happens when terminal width is too narrow to display tips properly?
- How should tips behave when running inside a container or VM where home directory might be ephemeral?
- What if a user manually edits the tip state file to invalid values?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display onboarding tips when a new interactive zsh shell session starts
- **FR-002**: System MUST persist tip view counts across shell sessions in a user-specific state file (e.g., `~/.local/state/keystone/shell-tips.json`)
- **FR-003**: System MUST automatically stop displaying tips after they have been shown N times (default: 5), configurable via environment variable
- **FR-004**: System MUST provide a command to manually display tips on demand (e.g., `keystone-tips` or `tips`)
- **FR-005**: System MUST provide a command to reset tip view counts (e.g., `keystone-tips reset`)
- **FR-006**: System MUST provide a command to permanently disable automatic tips (e.g., `keystone-tips disable`)
- **FR-007**: System MUST provide a command to re-enable automatic tips (e.g., `keystone-tips enable`)
- **FR-008**: Tips MUST include explanations of zoxide navigation commands:
  - `z <partial-name>` - Jump to frequently visited directory
  - `zi` - Interactive directory selection with fuzzy finding
  - `z -` - Return to previous directory
- **FR-009**: Tips MUST include commonly used shell aliases from terminal-dev-environment:
  - `hx` - Helix editor
  - `lg` - Lazygit
  - `l` or `ls` - eza file listing
- **FR-010**: Tips MUST NOT be displayed in non-interactive shell sessions (scripts, SSH command execution)
- **FR-011**: System MUST handle missing or corrupted state files gracefully, defaulting to showing tips as if new user
- **FR-012**: Tips MUST be formatted to fit common terminal widths (minimum 80 columns) with graceful degradation on narrow terminals
- **FR-013**: System MUST provide a way to query current tip status (view count, enabled/disabled state)
- **FR-014**: Tips MUST be organized into categories (navigation, editor, git, multiplexer) with progressive disclosure
- **FR-015**: System MUST include practical examples in tips (e.g., "Try: z keystone")

### Non-Functional Requirements

- **NFR-001**: Tip display MUST add less than 100ms to shell initialization time
- **NFR-002**: Tips MUST be visually distinct from the prompt and command output (e.g., using colors, borders, or prefixes)
- **NFR-003**: State file MUST be atomic (write to temp file, then rename) to prevent corruption from concurrent updates
- **NFR-004**: Implementation MUST be pure Nix/zsh without external dependencies (no Python, Ruby, etc.)
- **NFR-005**: Tips MUST be configurable through home-manager module options
- **NFR-006**: System MUST respect user's existing shell customizations and not interfere with prompt, aliases, or functions
- **NFR-007**: Documentation MUST include examples of customizing tip content and threshold
- **NFR-008**: Tips MUST be accessible (plain text, no Unicode art that breaks screen readers)
- **NFR-009**: State file location MUST follow XDG Base Directory specification (`$XDG_STATE_HOME` or `~/.local/state`)

### Key Entities

- **TipState**: Persistent data tracking which tips have been shown and how many times
  - `viewCount`: Number of times tips have been displayed
  - `enabled`: Whether automatic tips are enabled
  - `lastShown`: Timestamp of last tip display
  - `categoriesSeen`: Which tip categories have been dismissed

- **TipCategory**: A logical grouping of related tips
  - `name`: Category identifier (navigation, editor, git, multiplexer)
  - `priority`: Display order (1 = shown first)
  - `tips`: Array of individual tip content items

- **TipContent**: Individual help message
  - `title`: Short description
  - `command`: Command being explained
  - `description`: What it does
  - `example`: Practical usage example

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: New users see onboarding tips on their first 5 shell sessions without any manual action
- **SC-002**: Tips automatically disappear after 5 views, reducing visual clutter for experienced users
- **SC-003**: Users can manually recall tips using a simple command (`keystone-tips`) at any time
- **SC-004**: 100% of essential navigation commands (z, zi) are covered in onboarding tips
- **SC-005**: Tips display within 100ms on shell initialization (measured on typical hardware)
- **SC-006**: Tip view count persists correctly across 100 sequential shell sessions without loss or corruption
- **SC-007**: System handles concurrent shell sessions without race conditions (tested with 10 parallel shell launches)
- **SC-008**: Tips gracefully degrade on narrow terminals (tested at 60, 80, 120 column widths)
- **SC-009**: Non-interactive shells (scripts, SSH commands) never display tips (tested with `ssh user@host 'echo test'`)
- **SC-010**: Documentation includes at least 3 examples: enabling tips, customizing threshold, adding custom tip content
- **SC-011**: Users can disable tips permanently with a single command and re-enable just as easily
- **SC-012**: Tip content is accurate (all commands shown in tips actually work in the terminal-dev-environment)

## Implementation Considerations

### Technical Approach Options

1. **Pure Zsh Implementation**:
   - Hook into zsh's `precmd` or shell initialization
   - Use zsh associative arrays for tip storage
   - Serialize to JSON using `jq` for persistence

2. **Nix-Generated Script**:
   - Generate tip display script from Nix configuration
   - Allow tip content to be customized via home-manager options
   - Source script in `.zshrc`

3. **State Management**:
   - Use `~/.local/state/keystone/shell-tips.json` for persistence
   - Atomic writes (tmp file + mv) to prevent corruption
   - Flock or similar for concurrent session handling

### Integration Points

- Hook into `home-manager/modules/terminal-dev-environment/zsh.nix`
- Add new module option: `keystone.terminal-dev-environment.onboarding.enable`
- Add configuration options for tip threshold, content, and styling
- Ensure compatibility with existing starship prompt and oh-my-zsh setup

### User Configuration Example

```nix
keystone.terminal-dev-environment = {
  enable = true;
  onboarding = {
    enable = true;
    tipThreshold = 5;  # Show tips for first 5 sessions
    categories = {
      navigation = {
        enable = true;
        priority = 1;
      };
      editor = {
        enable = true;
        priority = 2;
      };
    };
    customTips = [
      {
        category = "navigation";
        command = "z <name>";
        description = "Jump to a frequently visited directory";
        example = "z keystone → cd ~/keystone";
      }
    ];
  };
};
```

### Testing Strategy

1. **Unit Testing**:
   - Test state file read/write/update
   - Test tip filtering logic (view count, categories)
   - Test command parsing (keystone-tips reset, enable, disable)

2. **Integration Testing**:
   - Test in fresh VM with terminal-dev-environment enabled
   - Verify tips appear for new user
   - Open/close shell 10 times, verify tips disappear after threshold
   - Test concurrent sessions (open 5 shells simultaneously)
   - Test state file corruption recovery

3. **Manual Testing**:
   - Test on actual Keystone desktop/terminal configurations
   - Verify visual appearance in different terminal emulators (ghostty, alacritty, xterm)
   - Test terminal width handling (resize during tip display)
   - Verify non-interactive shell behavior (cron jobs, SSH commands)

## Future Enhancements (Out of Scope)

- Interactive tutorial mode that walks users through commands step-by-step
- Tips based on user behavior (e.g., show git tips when in a git repo)
- Telemetry to understand which tips are most/least useful
- Integration with shell history to suggest tips for commands user struggles with
- Multi-language support for tips
- Rich formatting (colors, icons) for enhanced visual presentation
- Tip categories based on skill level (beginner, intermediate, advanced)
- Community-contributed tips via upstream repository
