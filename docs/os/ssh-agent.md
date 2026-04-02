---
title: SSH Agent
description: SSH key management via systemd user service for terminal and desktop sessions
---

# SSH Agent

Keystone runs `ssh-agent` as a systemd user service, providing SSH key
management for terminal and desktop sessions.

## How It Works

Three pieces work together:

1. **`services.ssh-agent`** (home-manager) - Starts a systemd user service running `ssh-agent -D -a $XDG_RUNTIME_DIR/ssh-agent`
2. **Session environment** - Exposes `SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent` so terminal shells, editors, and desktop applications inherit it
3. **`programs.ssh.addKeysToAgent = "yes"`** - On first SSH use, the key is automatically added to the agent after you enter the passphrase

## Passphrase-Protected Keys

With `AddKeysToAgent yes` in SSH config:

1. First `git push` or `ssh` of the session prompts for your key passphrase
2. The key is cached in the agent for the rest of the session
3. Subsequent operations use the cached key without prompting

No PAM integration or GNOME Keyring needed.

## Software Key Hosts vs Hardware-Key-Only Hosts

Keystone distinguishes between two host types:

- **Software-key hosts** — `keystone.terminal.sshAutoLoad.enable = true`. These hosts
  have a local SSH private key (e.g. `~/.ssh/id_ed25519`) that must be loaded into the
  agent. Keystone actively monitors this and warns when the key is missing.
- **Hardware-key-only hosts** — No `sshAutoLoad`. These hosts rely on hardware security
  keys (YubiKey, FIDO2) for SSH. The ssh-agent service still runs but an empty agent is
  normal and does **not** trigger warnings.

## SSH Key Health Warnings

On software-key hosts (`sshAutoLoad.enable = true`), Keystone surfaces warnings when
the SSH key is not loaded. This helps catch the problem before `git push`, SSH access,
or Git commit signing fails.

### Terminal Warning

When you open a new login shell on a software-key host, Keystone checks the agent
state:

- **Key not loaded** — Shows: `⚠  SSH key not loaded. Run: keystone-ssh-unlock ~/.ssh/id_ed25519`
- **Agent unreachable** — Shows: `✗  SSH agent unreachable. Run: systemctl --user start ssh-agent`
- **Key loaded** — No warning (quiet)

The warning appears once per shell session to avoid noisy repetition.

### Desktop Notification

On desktop sessions, Keystone sends a desktop notification 3 seconds after login if
the SSH key is not loaded. The notification says:

> **SSH key not loaded** — Run: keystone-ssh-unlock

### Desktop Menu Entry

The Setup menu (Mod+Escape → Setup) includes an **SSH Key** entry on software-key
hosts. It shows the current state and provides an unlock action. The SSH Key entry
appears in the Setup menu because SSH key management is a session configuration task,
alongside Audio, Monitors, and Hardware.

## Unlocking Software SSH Keys

### Terminal

```bash
keystone-ssh-unlock                          # unlock default key (~/.ssh/id_ed25519)
keystone-ssh-unlock /path/to/custom/key      # unlock a specific key
```

This runs `ssh-add` against the configured key. In a terminal, it prompts for the
passphrase interactively. On desktop sessions, it uses `SSH_ASKPASS` for a GUI prompt.

### Desktop (Wayland)

The desktop unlock flow uses `SSH_ASKPASS` with `lxqt-openssh-askpass` as the
backend. This is a Qt-based, Wayland-native askpass dialog that:

- Works in Wayland sessions without X11
- Does not require privilege escalation (PAM/polkit)
- Provides a simple password dialog for the SSH key passphrase

**Why lxqt-openssh-askpass?**

| Backend               | Wayland | Dependencies | Notes                          |
| --------------------- | ------- | ------------ | ------------------------------ |
| lxqt-openssh-askpass  | ✓       | Qt only      | Minimal, Wayland-native        |
| ssh-askpass-fullscreen | ✗       | X11          | Does not work on pure Wayland  |
| ksshaskpass           | ✓       | KDE/Plasma   | Heavy dependency for non-KDE   |
| x11-ssh-askpass       | ✗       | X11          | Legacy X11-only                |

Keystone sets `SSH_ASKPASS=lxqt-openssh-askpass` and `SSH_ASKPASS_REQUIRE=prefer` in
the Hyprland environment so all desktop processes inherit it.

### Wayland Validation

The desktop unlock path requires these environment variables in the session:

- `WAYLAND_DISPLAY` — set by Hyprland compositor
- `SSH_AUTH_SOCK` — set to `$XDG_RUNTIME_DIR/ssh-agent` in Hyprland environment
- `SSH_ASKPASS` — set to `lxqt-openssh-askpass` in Hyprland environment

To validate the unlock flow works on a live Keystone Hyprland session:

```bash
# 1. Verify environment
echo $WAYLAND_DISPLAY    # Should be non-empty (e.g. "wayland-1")
echo $SSH_AUTH_SOCK      # Should be /run/user/<uid>/ssh-agent
echo $SSH_ASKPASS        # Should be lxqt-openssh-askpass

# 2. Test askpass dialog directly
lxqt-openssh-askpass "Test prompt"   # Should show a GUI dialog

# 3. Test unlock from desktop terminal
keystone-ssh-unlock                  # Should show askpass dialog, then load key

# 4. Test from user service context (simulates menu/notification path)
systemd-run --user --collect --wait -- keystone-ssh-health
# Should report the correct state
```

If `lxqt-openssh-askpass` fails in a particular Wayland session configuration, check
that the compositor is running and `WAYLAND_DISPLAY` is exported. As a fallback, unlock
from a terminal with `keystone-ssh-unlock` which works interactively without askpass.

## SSH Key Health Check

The `keystone-ssh-health` command classifies the agent state:

```bash
keystone-ssh-health            # prints: unlocked, locked, or agent-unreachable
keystone-ssh-health --quiet    # exit code only (0=unlocked, 1=locked, 2=unreachable)
```

This is the shared check used by both terminal warnings and desktop notifications.

## Git SSH Commit Signing

If you use `gpg.format = "ssh"` for Git commit signing, it works automatically since `ssh-agent` provides the signing key via `SSH_AUTH_SOCK`. No additional configuration required.

## Coexistence with Hardware Keys

The desktop module may also include a hardware-key module that uses GPG agent for SSH. Both can coexist:

- **ssh-agent**: Handles standard SSH keys (`~/.ssh/id_ed25519`, etc.)
- **GPG agent**: Handles hardware security keys (YubiKey, etc.) when configured

If you use a hardware key exclusively, the ssh-agent service still runs but remains idle.

## Verification

After logging in to your session:

```bash
# Check the socket exists
echo $SSH_AUTH_SOCK
# Expected: /run/user/1000/ssh-agent

# Check the agent is running
ssh-add -l
# Expected: "The agent has no identities." (not "Could not open connection")

# Check the systemd service
systemctl --user status ssh-agent
# Expected: active (running)

# Check SSH key health (software-key hosts)
keystone-ssh-health
# Expected: unlocked (if key is loaded), locked (if not loaded)
```

## Troubleshooting

### "Could not open a connection to your authentication agent"

The agent service may not be running:

```bash
systemctl --user start ssh-agent
systemctl --user status ssh-agent
```

### SSH_AUTH_SOCK is empty or wrong

Check that your session inherited the environment variable:

```bash
# Should show the ssh-agent socket path
hyprctl getoption env

# If missing in a desktop session, the env line may not be in hyprland.conf
grep SSH_AUTH_SOCK ~/.config/hypr/hyprland.conf
```

### Key not being cached after entering passphrase

Verify `AddKeysToAgent` is set:

```bash
ssh -G github.com | grep addkeystoagent
# Expected: addkeystoagent yes
```

### SSH key not loaded warning despite auto-load being enabled

If the `ssh-auto-load` systemd service failed:

```bash
systemctl --user status ssh-auto-load
journalctl --user -u ssh-auto-load --no-pager -n 20
```

Common causes:
- The agenix passphrase secret was not decrypted (check `/run/agenix/`)
- The SSH key file does not exist at the configured path
- The ssh-agent socket was not ready in time

### Desktop askpass dialog does not appear

Verify the environment:

```bash
echo $SSH_ASKPASS              # Should be lxqt-openssh-askpass
which lxqt-openssh-askpass     # Should resolve to a valid path
echo $WAYLAND_DISPLAY          # Should be non-empty
```
