# Quickstart: Hyprland Desktop Environment

## Prerequisites

- NixOS system with flakes enabled
- home-manager configured for the target user
- Python 3 (for test scripts)
- Libvirt/QEMU for VM testing

## Automated Testing (Recommended)

The easiest way to test the Hyprland desktop is using the automated test scripts:

### 1. Deploy Base System

```bash
# From the repository root
# This deploys the base infrastructure to a VM
./bin/test-deployment
```

This will:
- Create a VM with ISO
- Deploy base NixOS configuration with disk encryption
- Set up SSH access
- Takes ~10-15 minutes

### 2. Add Desktop Environment

```bash
# Apply desktop configuration on top of the base system
./bin/test-desktop
```

This will:
- Check if desktop is already installed (via marker file `/var/lib/keystone-desktop-installed`)
- Build the Hyprland desktop configuration
- Deploy to the running VM via nixos-rebuild
- Create installation marker file (contents: `1`)
- **First-time installation**: Automatically reboot VM to start greetd display manager
- **Subsequent runs**: Skip reboot if marker file exists
- Verify desktop services and packages
- Show manual testing steps
- Takes ~5-10 minutes (first time includes reboot + wait)

### 3. Test Graphical Session

```bash
# Connect to VM graphical console
remote-viewer $(virsh domdisplay keystone-test-vm)
```

Login credentials:
- Username: `testuser`
- Password: `testpass`

## Manual Testing (Advanced)

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
