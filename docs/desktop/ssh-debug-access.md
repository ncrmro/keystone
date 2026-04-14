# SSH debug access

How to add SSH access to a fresh Keystone laptop for remote debugging.

## Adding your SSH public key

The Keystone OS module enables both SSH and Eternal Terminal (ET) by default
with password authentication disabled. Only public key authentication is
accepted.

On the fresh laptop, add your public key to the host configuration:

```nix
# hosts/<hostname>/configuration.nix
keystone.os.users.admin.authorizedKeys = [
  "ssh-ed25519 AAAA... operator@workstation"
];
```

Rebuild and apply:

```bash
ks build && ks switch
```

After the rebuild, SSH (port 22) and ET (port 2022) are available at the
laptop's IP.

## Connecting

```bash
# SSH
ssh <username>@<laptop-ip>

# Eternal Terminal (survives network changes)
et <username>@<laptop-ip>
```

If the laptop is on the same Tailscale/Headscale network:

```bash
ssh <username>@<hostname>
et <username>@<hostname>
```

## Collecting diagnostic context

Once connected, gather context for rc debugging:

```bash
# System generation and version
nixos-version

# Failed systemd units
systemctl --failed

# Hyprland session logs (wallpaper, bindings, menus)
journalctl --user -u hyprpaper.service --no-pager -n 50
journalctl --user -u walker.service --no-pager -n 50

# Elephant menu provider output
journalctl --user -u elephant.service --no-pager -n 50

# System health
ks doctor

# Home-manager generation
home-manager generations | head -5
```

## Troubleshooting

**SSH connection refused:** SSH is enabled by default via `keystone.os.ssh.enable`.
Verify the Keystone OS module is active on the host.

**Key not accepted:** Ensure the public key is in `authorizedKeys` for the
correct user, rebuild was applied, and `sshd` was restarted.

**Can't find the laptop IP:** Check the router's DHCP lease table, or run
`ip addr show` on the laptop directly.
