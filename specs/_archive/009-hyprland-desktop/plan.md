# Implementation Plan: Hyprland Desktop Environment

**Branch**: `009-hyprland-desktop` | **Date**: 2025-11-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/home/ncrmro/code/ncrmro/keystone/specs/009-hyprland-desktop/spec.md`

## Summary

This feature introduces a set of NixOS and home-manager modules to configure a complete Hyprland-based desktop environment. The implementation will provide a graphical login using `greetd`, a `uwsm`-managed Hyprland session, and essential desktop components like `waybar`, `mako`, `hyprlock`, and core applications such as `chromium` and `ghostty`. The approach focuses on creating a minimal, secure, and composable desktop experience that integrates with existing project structures.

## Technical Context

**Language/Version**: Nix  
**Primary Dependencies**: NixOS, home-manager, Hyprland, greetd, uwsm, waybar, mako, hyprlock, hypridle  
**Storage**: N/A  
**Testing**: Manual VM testing using `bin/virtual-machine` as per constitution.  
**Target Platform**: NixOS (x86_64)
**Project Type**: NixOS Modules  
**Performance Goals**: Responsive desktop session with fast boot-to-login time.  
**Constraints**: Must integrate with the existing `terminal-dev-environment` module. The initial implementation should offer minimal configuration options.  
**Scale/Scope**: Two primary modules (one for NixOS, one for home-manager) to deliver a complete desktop environment.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Declarative Infrastructure**: `PASS` - The feature will be implemented entirely as declarative NixOS and home-manager modules.
- **II. Security by Default**: `PASS` - The feature includes `hyprlock` and `hypridle` for automatic session locking, adhering to security-by-default principles.
- **III. Modular Composability**: `PASS` - The feature is designed as two distinct, composable modules (system-level and user-level), promoting modularity.
- **IV. Hardware Agnostic**: `PASS` - The modules will be hardware-agnostic, with hardware-dependent utilities like `brightnessctl` failing gracefully.
- **V. Cryptographic Sovereignty**: `PASS` - This feature does not manage cryptographic keys, inheriting the sovereignty of the underlying system.
- **Module Development Standards**: `PASS` - The new modules will use standard `enable` options and follow project conventions.
- **Development Tooling**: `PASS` - Testing will be conducted using the mandated `bin/virtual-machine` script.

**Result**: All constitutional gates pass. No violations identified.

## Project Structure

### Documentation (this feature)

```text
specs/009-hyprland-desktop/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
modules/client/
└── desktop/
    ├── hyprland.nix     # New: Main Hyprland system configuration
    └── greetd.nix       # New: Greetd login manager setup

home-manager/modules/
└── desktop/
    └── hyprland/
        ├── default.nix  # New: Main home-manager module for Hyprland
        ├── hyprpaper.nix# New: Wallpaper configuration
        ├── waybar.nix   # New: Status bar configuration
        ├── mako.nix     # New: Notification daemon configuration
        ├── hyprlock.nix # New: Screen lock configuration
        └── hypridle.nix # New: Idle management configuration
```

**Structure Decision**: The implementation will extend the existing `modules/client/` and `home-manager/modules/` directories. A new `desktop` category will be created in both to house the Hyprland-related modules, ensuring a clean separation of concerns between system-level and user-level configuration.

## Complexity Tracking

> No constitutional violations were found. This section is not required.
