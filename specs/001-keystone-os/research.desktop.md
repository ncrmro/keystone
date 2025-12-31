# Desktop Session Startup

This document describes how Keystone's desktop module initializes a Hyprland session from boot to a fully functional locked desktop.

## Startup Flow

```
Boot → greetd → UWSM → Hyprland → hyprlock (locked desktop)
```

### 1. greetd (Display Manager)

greetd is a minimal display manager that handles user authentication and session launching. Keystone configures greetd with auto-login directly into UWSM:

```nix
services.greetd.settings.default_session = {
  command = "uwsm start -F Hyprland";
  user = cfg.user;
};
```

This bypasses any greeter UI and immediately starts the Wayland session for the configured user.

### 2. UWSM (Universal Wayland Session Manager)

UWSM is a session manager that wraps Wayland compositors to provide proper systemd integration. We use UWSM because:

- **Systemd user session integration** - Runs the compositor as a systemd user service, enabling proper dependency management and clean shutdown
- **Environment management** - Properly exports environment variables to all child processes and D-Bus
- **XDG autostart support** - Handles XDG autostart entries through systemd
- **App launching** - Provides `uwsm app -- <command>` for launching applications as proper systemd scopes/services
- **Clean session lifecycle** - Ensures all session services are properly stopped when the compositor exits

The `-F` flag enables "hardcode mode" which embeds full paths in generated unit files for reliability.

NixOS provides UWSM integration via `programs.hyprland.withUWSM = true`, which:
- Installs UWSM
- Creates the necessary systemd unit templates
- Sets up the Hyprland desktop entry for UWSM

### 3. Hyprland (Compositor)

Once UWSM starts Hyprland, the compositor initializes and runs `exec-once` commands defined in the home-manager configuration:

```nix
exec-once = [
  # D-Bus activation environment for notifications
  "systemctl --user import-environment"
  "dbus-update-activation-environment --systemd --all"
  # Lock screen immediately
  "hyprlock"
  # Background services
  "uwsm app -- hyprsunset"
  "systemctl --user start hyprpolkitagent"
  "wl-clip-persist --clipboard regular & uwsm app -- clipse -listen"
];
```

### 4. hyprlock (Lock Screen)

The first `exec-once` command after D-Bus setup is `hyprlock`, which immediately presents a lock screen. This ensures:

- **Security** - The desktop is never visible without authentication
- **Full initialization** - All desktop components (waybar, notifications, clipboard) are running behind the lock screen
- **Seamless experience** - User unlocks to a fully ready desktop

## PAM Session Configuration

greetd's PAM configuration registers the session as a Wayland session type:

```nix
security.pam.services.greetd.rules.session.systemd.settings = {
  type = "wayland";
};
```

This enables `loginctl lock-session` to work properly for session locking.

---

## Footnotes

### About the "start-hyprland" Warning

Hyprland versions 0.46+ emit a warning when not started via the `start-hyprland` wrapper script:

> "Hyprland was started without start-hyprland..."

This warning exists because `start-hyprland` handles certain environment setup that the raw `Hyprland` binary doesn't perform directly.

However, when using UWSM with `programs.hyprland.withUWSM = true`, UWSM handles session management, environment propagation, and systemd integration - making the `start-hyprland` wrapper unnecessary.

We disable this warning in our configuration:

```nix
misc.disable_watchdog_warning = true;
```

This is appropriate because UWSM provides equivalent (and arguably superior) session management compared to the `start-hyprland` script.

See: https://github.com/hyprwm/Hyprland/discussions/12661
