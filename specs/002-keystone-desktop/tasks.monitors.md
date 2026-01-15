# Tasks: Monitor Management (dt-monitor)

**Feature**: 002-keystone-desktop
**Spec**: `specs/002-keystone-desktop/spec.md`

## Implementation Tasks

### Configuration
- [x] **dt-task-monitor-001**: Implement `keystone.desktop.monitors` option structure.
    - Create `monitors.nix` in `modules/desktop/home/hyprland/`.
    - Define `autoMirror` (bool, default true) and `settings` (list of strings) options.
    - Implement the logic to generate `monitor=` lines for Hyprland config.
    - Add default auto-mirror rule if `autoMirror` is enabled: `monitor=,preferred,auto,1,mirror,[primary]` (need to determine primary dynamically or via config). Actually, for static config, we can't determine primary dynamically easily without a script. The spec says "generate default rule". Hyprland `monitor` rules are static.
    - Wait, `monitor=,preferred,auto,1,mirror,eDP-1` works if eDP-1 is known. If not, maybe we just use `auto`.
    - Let's stick to the spec: "If `keystone.desktop.monitors.autoMirror` is true, the system generates a default rule for unknown monitors".

### Interactive Menu
- [ ] **dt-task-monitor-002**: Create `keystone-monitors` script.
    - Query `hyprctl monitors -j`.
    - Generate JSON/Text for Walker.
    - Handle actions: Mirror All, Mirror Specific, Extend (default/auto), Resolution presets.
    - Use `hyprctl keyword monitor` for runtime changes.

### Integration
- [ ] **dt-task-monitor-003**: Integrate with `keystone-menu.sh`.
    - Replace "Not implemented" placeholder in Setup -> Monitors.
