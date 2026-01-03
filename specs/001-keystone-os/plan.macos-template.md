# Plan: Template-based macOS (Apple Silicon) Configuration

## Background
Currently, the macOS (Apple Silicon) host `keystone-mac` is being updated by syncing the entire Keystone development repository to `/home/admin/nixos-config`. This approach is suboptimal as it includes development artifacts, large history, and can lead to unexpected kernel recompilations due to flake input overrides (e.g., `follows`).

## Goal
Transition the `keystone-mac` host to use a configuration initialized from the `macos` template provided by the Keystone flake. This separates the machine-specific configuration from the Keystone framework development.

## Implementation Steps

### Phase 1: Template Creation (Completed)

1.  **Define the `macos` Template**: ✅
    *   Created `templates/macos/configuration.nix` - NixOS configuration with Keystone desktop
    *   Created `templates/macos/hardware-configuration.nix` - Apple Silicon hardware config
    *   Created `templates/macos/flake.nix` - Standalone flake referencing Keystone as input
    *   Created `templates/macos/README.md` - Documentation for users
    *   Registered the template in `flake.nix` under `templates.macos`

### Phase 2: Migration on keystone-mac Host

2.  **Backup existing configuration on Mac**:
    ```bash
    # On keystone-mac
    mv /home/admin/nixos-config /home/admin/nixos-config.backup
    ```

3.  **Initialize new configuration from template**:
    ```bash
    # Create new config directory
    mkdir /home/admin/nixos-config
    cd /home/admin/nixos-config

    # Initialize from Keystone template (use GitHub URL for production)
    nix flake init -t github:ncrmro/keystone#macos

    # OR for local testing (if you have Keystone checked out locally):
    # nix flake init -t /path/to/local/keystone#macos
    ```

4.  **Update hardware-configuration.nix with actual UUIDs**:
    ```bash
    # Find root filesystem UUID
    lsblk -o NAME,UUID,LABEL,FSTYPE

    # Find boot partition PARTUUID
    blkid /dev/nvme0n1p* | grep -i boot

    # Edit hardware-configuration.nix with correct values
    ```

5.  **Customize configuration.nix**:
    *   Verify hostname matches desired value
    *   Update user settings (name, email, etc.)
    *   Set correct timezone
    *   Add any machine-specific packages or services

6.  **Initial deployment**:
    ```bash
    # From /home/admin/nixos-config
    sudo nixos-rebuild switch --flake .#keystone-mac
    ```

### Phase 3: Ongoing Workflow

7.  **Updating Keystone framework**:
    When Keystone receives updates (new Hyprland config, terminal tools, etc.):
    ```bash
    cd /home/admin/nixos-config
    nix flake update keystone
    nixos-rebuild switch --flake .#keystone-mac
    ```

8.  **Machine-specific changes**:
    Edit files in `/home/admin/nixos-config` directly. These stay separate from Keystone development.

## Benefits

*   **Isolation**: Machine-specific settings (UUIDs, user names) stay in the host config.
*   **Purity**: Reduces the chance of accidental overrides from the development repo.
*   **Efficiency**: Smaller sync footprint; uses pinned versions from the Keystone flake which improves binary cache hits for the Asahi kernel.
*   **Simplicity**: No need to sync entire development repository to production machine.

## Important: Binary Cache Compatibility

The template's `flake.nix` intentionally does **NOT** use `follows` for the Keystone or nixos-apple-silicon inputs:

```nix
# CORRECT - preserves binary cache compatibility
keystone = {
  url = "github:ncrmro/keystone";
  # No follows!
};

nixos-apple-silicon = {
  url = "github:tpwrules/nixos-apple-silicon";
  # No follows!
};
```

This is critical because:
1. The Asahi kernel must be compiled from source (~1-2 hours on M1)
2. Both Keystone and nixos-apple-silicon pin specific nixpkgs versions
3. Binary caches provide pre-built kernels for these pinned versions
4. Using `follows` would override the pins, breaking cache compatibility

## Files Created/Modified

*   `templates/macos/flake.nix` - NEW: Standalone flake for Apple Silicon hosts
*   `templates/macos/configuration.nix` - EXISTING: NixOS configuration
*   `templates/macos/hardware-configuration.nix` - EXISTING: Hardware config
*   `templates/macos/README.md` - NEW: User documentation
*   `flake.nix` - EXISTING: Template already registered at `templates.macos`
