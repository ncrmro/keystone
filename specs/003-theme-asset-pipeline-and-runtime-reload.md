# Spec: Theme asset pipeline and runtime reload

## Stories Covered
- US-001: Link supported repo-backed assets from local checkouts
- US-002: Apply linked changes without another rebuild for supported assets

## Affected Modules
- `modules/desktop/home/theming/default.nix`
- `modules/desktop/home/theming/themes/royal-green/`
- `modules/desktop/home/components/ghostty.nix`
- `modules/desktop/home/components/waybar.nix`
- `modules/desktop/home/components/btop.nix`
- `modules/desktop/home/components/launcher.nix`
- `modules/desktop/home/hyprland/default.nix`
- `modules/desktop/home/hyprland/hyprlock.nix`

## Data Models

### Theme asset payload
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| themeName | string | yes | Example: `royal-green` |
| sourceRepo | string | yes | Managed repo key when repo-backed |
| relativePath | string | yes | Theme directory inside the repo |
| assetFile | string | yes | e.g. `waybar.css`, `ghostty.conf`, `hyprland.conf` |
| liveEditable | bool | yes | Whether checkout edits should apply after activation |
| generated | bool | yes | Distinguishes copied files from derived files |

### Runtime theme link contract
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| currentThemeLink | string | yes | `~/.config/keystone/current/theme` |
| targetThemeDir | string | yes | Active theme directory |
| consumers | list | yes | Runtime components that read through the current-theme link |

## Interface definitions

### Supported theme files
- Direct theme payloads such as `hyprland.conf`, `hyprlock.conf`, `waybar.css`, `mako.ini`, `walker.css`, `btop.theme`, `ghostty.conf`, and `zellij.kdl` SHOULD be eligible for checkout-backed linking when they live in an explicitly supported repo-backed theme directory.
- Generated files such as mapped theme-name shims MAY remain activation-generated if the target application cannot consume the raw repo file directly.

## Behavioral Requirements

1. The system MUST define which theme asset files are live-editable in dev mode and which remain generated.
2. Explicitly supported repo-backed theme files MUST resolve from the local checkout in dev mode after activation.
3. Runtime desktop consumers that already read through `~/.config/keystone/current/theme/` MUST continue to use that indirection rather than reading repo paths directly.
4. The active theme symlink structure under `~/.config/keystone/current/` MUST remain the stable runtime contract for desktop components.
5. Generated theme derivatives MAY remain activation-generated, but the implementation MUST document that they are not live-editable.
6. Theme switching MUST continue to work with checkout-backed themes and MUST preserve the current reload behavior for Waybar, Ghostty, Mako, Hyprland, and related consumers.
7. Unsupported theme sources, including theme trees that are not explicitly marked repo-backed, MUST keep their current immutable behavior.
8. The implementation SHOULD prefer linking whole supported files from the checkout instead of regenerating equivalent content into the target tree.
9. The system MUST NOT require users to edit files under `~/.config/keystone/current/theme/` directly.

## Edge Cases

- If the active theme directory does not contain an optional file such as `backgrounds/` or `lazygit.yml`, activation and theme switching MUST degrade gracefully.
- If a runtime consumer cannot handle a symlinked payload, the exception MUST be documented and the asset MUST remain generated until the tool limitation is resolved.
- If the active theme is sourced from an external repo that is not present locally, the system MUST fall back to the immutable source for that theme.
- If a user switches themes at runtime, the current-theme symlink MUST remain valid even when the previously active theme was checkout-backed.

## Cross-spec dependencies
- `specs/001-shared-dev-mode-path-resolution.md`
- `specs/004-lock-and-deploy-safety.md`
