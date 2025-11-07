# Quickstart: Hyprland Desktop Environment

## Prerequisites

- NixOS system with flakes enabled
- home-manager configured for the target user
- Access to `bin/virtual-machine` for testing

## Testing the Feature

### 1. Create a Test VM

```bash
# From the repository root
./bin/virtual-machine --name hyprland-test --memory 4096 --vcpus 2 --start
```

### 2. Enable the Modules

Create a test NixOS configuration that enables the new desktop modules:

```nix
# Example: vms/test-client/configuration.nix
{ config, pkgs, ... }:

{
  imports = [
    ../../modules/client/desktop/hyprland.nix
  ];

  # Enable the Hyprland desktop
  keystone.client.desktop.hyprland.enable = true;

  # User configuration
  users.users.testuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "audio" ];
    initialPassword = "test";
  };

  # Home-manager configuration
  home-manager.users.testuser = { pkgs, ... }: {
    imports = [
      ../../home-manager/modules/desktop/hyprland
    ];

    keystone.homeManager.desktop.hyprland.enable = true;
  };
}
```

### 3. Build and Deploy

```bash
# Build the configuration
nix build .#nixosConfigurations.hyprland-test.config.system.build.toplevel

# Deploy to VM (if using nixos-anywhere)
nixos-anywhere --flake .#hyprland-test root@192.168.100.99
```

### 4. Verify User Story 1: Graphical Session Login

**Test**: Boot the VM and verify greetd displays

1. Connect to VM console:
   ```bash
   remote-viewer $(virsh domdisplay hyprland-test)
   ```

2. Expected: greetd login prompt appears within 30 seconds of boot
3. Action: Enter credentials for `testuser`
4. Expected: Hyprland session launches via uwsm

**Success Criteria**:
- ✅ greetd login screen appears on boot
- ✅ Valid credentials launch Hyprland session
- ✅ Desktop environment is visible

### 5. Verify User Story 2: Basic Desktop Interaction

**Test**: Verify desktop components are running

1. After login, check for waybar:
   ```bash
   # In a terminal (Super+Enter to launch)
   pgrep waybar
   ```

2. Test notifications:
   ```bash
   notify-send "Test" "This is a test notification"
   ```
   Expected: mako displays the notification

3. Launch applications:
   ```bash
   # Launch chromium
   chromium &
   
   # Launch ghostty
   ghostty &
   ```

**Success Criteria**:
- ✅ waybar is visible on screen
- ✅ mako displays notifications
- ✅ chromium launches successfully
- ✅ ghostty launches successfully
- ✅ hyprpaper shows wallpaper

### 6. Verify User Story 3: Session Security and Power Management

**Test**: Verify automatic screen locking

1. Leave the session idle for the configured duration (default: 5 minutes)
2. Expected: hyprlock activates and locks the screen
3. Action: Enter password to unlock
4. Expected: Session unlocks and returns to active desktop

**Success Criteria**:
- ✅ Screen locks after idle timeout
- ✅ hyprlock displays lock screen
- ✅ Correct password unlocks session
- ✅ Session state is preserved after unlock

## Manual Verification Checklist

After deployment, verify these items:

- [ ] System boots to greetd login
- [ ] User can log in with credentials
- [ ] Hyprland session starts via uwsm
- [ ] waybar displays at top of screen
- [ ] hyprpaper sets wallpaper
- [ ] mako displays notifications
- [ ] chromium is available and launches
- [ ] ghostty is available and launches
- [ ] All essential Hyprland packages are installed (hyprshot, hyprpicker, etc.)
- [ ] Screen locks after idle period
- [ ] User can unlock screen with password
- [ ] Terminal inherits configuration from terminal-dev-environment module

## Troubleshooting

### greetd doesn't start
- Check: `systemctl status greetd`
- Verify: greetd service is enabled in NixOS configuration

### Hyprland session fails to launch
- Check: `journalctl -u greetd -b`
- Verify: uwsm is installed and available
- Verify: User has proper permissions (video, audio groups)

### Desktop components missing
- Check: `echo $PATH` in Hyprland session
- Verify: home-manager module is enabled for the user
- Rebuild: `home-manager switch` for the user

### Screen doesn't lock
- Check: `pgrep hypridle`
- Verify: hypridle configuration is valid
- Check: `journalctl --user -u hypridle`

## Clean Up

```bash
# Shut down VM
virsh shutdown hyprland-test

# Remove VM completely
./bin/virtual-machine --reset hyprland-test
```
