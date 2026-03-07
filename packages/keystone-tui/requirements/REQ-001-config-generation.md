# REQ-001: Config Generation

This document defines requirements for the configuration output that the
Keystone TUI must produce. The TUI generates a complete, buildable NixOS
flake directory from user-provided inputs.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Output Structure

**REQ-001.1** The TUI MUST produce a directory containing at minimum
`flake.nix`, `configuration.nix`, and `hardware.nix`.

**REQ-001.2** The generated `flake.nix` MUST declare `nixpkgs`, `keystone`,
`home-manager`, and `disko` as inputs, with `nixpkgs` following `keystone`.

**REQ-001.3** The generated `flake.nix` MUST import
`keystone.nixosModules.operating-system` in the NixOS configuration modules
list.

**REQ-001.4** The generated `flake.nix` MUST import
`home-manager.nixosModules.home-manager` when any user has `terminal.enable`
or `desktop.enable` set.

**REQ-001.5** The generated `flake.nix` MUST import
`keystone.nixosModules.desktop` when any user has `desktop.enable` set.

**REQ-001.6** The generated `hardware.nix` MUST be a placeholder module
`{ ... }: { }` that the user populates post-installation with
`nixos-generate-config`.

### Content Quality

**REQ-001.7** The generated files MUST NOT contain any `TODO:` markers.

**REQ-001.8** The generated files MUST be valid Nix syntax that parses
without error via `nix-instantiate --parse`.

**REQ-001.9** The generated files SHOULD be formatted with `nixfmt` and
produce no diff when re-formatted.

**REQ-001.10** The generated `configuration.nix` MUST set
`networking.hostName`, `networking.hostId`, `system.stateVersion`,
`keystone.os.enable`, `keystone.os.storage`, and at least one
`keystone.os.users` entry.

### Completeness

**REQ-001.11** The generated configuration MUST evaluate successfully via
`nixpkgs.lib.nixosSystem` without additional user modifications (aside from
`hardware.nix` customization for target hardware).

**REQ-001.12** The generated `flake.nix` MUST expose a single
`nixosConfigurations.<hostname>` output using the user-provided hostname.

**REQ-001.13** The generated configuration MUST set `time.timeZone` to a
user-provided value or default to `"UTC"`.
