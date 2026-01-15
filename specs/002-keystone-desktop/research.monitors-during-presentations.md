# Research: Monitor Management During Presentations

## Problem Statement
When a Keystone desktop user needs to present, there is currently no clear or automated procedure for configuring monitors (e.g., mirroring). The manual process involves knowing specific `hyprctl` commands or hardware identifiers, which is not user-friendly during high-pressure situations like starting a presentation.

## Current State
The Keystone menu (`Alt+Escape` -> `Setup` -> `Monitors`) currently has a placeholder that is marked as "not implemented". Users are left to manually configure their displays via the CLI or by editing Nix configurations, which requires a system rebuild or at least a restart of the compositor session in some cases if not using `hyprctl` keywords correctly.

## Reference: Omarchy Handling
Omarchy (the inspiration for many Keystone desktop patterns) provides a set of utility scripts for display management. It emphasizes ergonomic defaults and quick access to common configurations. Keystone aims to integrate these patterns into a more unified, discovery-driven menu system.

## Fresh Install & Default Behavior

### Out-of-the-Box Experience
On a fresh Keystone installation without any monitor-specific configuration:
1.  **Auto-Detection**: Hyprland defaults to auto-detection (`monitor=,preferred,auto,1`). It will attempt to enable all connected displays with their preferred resolution and positioning.
2.  **Fallback**: If detection fails or behavior is unexpected (e.g., wrong primary monitor), users might find themselves on a secondary screen or with disjointed layouts.

### Declarative Configuration (Post-Install)
Users should be able to declaratively configure their monitor behavior using a unified `keystone.desktop.monitors` option.

**Proposed Configuration Model:**
Instead of scattering options under `keystone.desktop.hyprland`, we centralize monitor configuration under `keystone.desktop.monitors`.

```nix
keystone.desktop.monitors = {
  # Enable auto-mirroring for new/unknown displays (Great for presentations)
  autoMirror = true; 
  
  # Static configurations for known hardware (Home/Work setup)
  settings = [
    # Primary Laptop Display
    "desc:BOE 0x0BCA, 2256x1504@60.00Hz, 0x0, 1"
    
    # Fallback/specific external display
    ", preferred, auto-right, 1"
  ];
};
```

## Proposed Solution: Interactive Monitor Menu

The "Monitors" submenu should be dynamic and informative, rather than just a list of static commands:

1. **List Current Monitors**: The menu should query `hyprctl monitors -j` and display a list of currently connected displays with their names and descriptions.
2. **Mirroring Toggle**:
   - Provide a global "Mirror All" toggle.
   - Allow selecting a specific external monitor to mirror the primary (laptop) display.
3. **Smart Defaults**:
   - **New displays should default to mirrored**: When `autoMirror` is enabled (default), new displays automatically mirror the primary display. This ensures immediate visibility during presentations.
4. **Resolution Presets**: Allow quick switching to common presentation resolutions (e.g., 1080p) to ensure compatibility with older projectors.

## Implementation Details (Hyprland)

Mirroring in Hyprland is achieved using the `mirror` keyword in the monitor rule:
```bash
# Example: Mirror eDP-1 onto an external HDMI display
hyprctl keyword monitor "HDMI-A-1,preferred,auto,1,mirror,eDP-1"
```

### Auto-Mirroring Logic
If `keystone.desktop.monitors.autoMirror` is true, the system generates a default rule for unknown monitors:

```bash
# NixOS module generation logic:
monitor = , preferred, auto, 1, mirror, [PRIMARY_MONITOR]
```

This ensures that any monitor not explicitly matched by the `settings` list will default to mirroring the primary display.

## Next Steps
- Refactor `keystone.desktop.monitors` option to support the new structure (attribute set instead of simple list).
- Implement `keystone-monitors` script for the Walker menu.
- Update `keystone-menu.sh` to call this script.
- Document the exact `hyprctl` calls needed for various mirroring scenarios.
