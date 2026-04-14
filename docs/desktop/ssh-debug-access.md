# SSH debug access

How to add SSH access to a fresh Keystone laptop for remote debugging.

## Adding your SSH public key

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

The Keystone OS module enables `sshd` by default. After the rebuild, SSH access
is available at the laptop's IP.

## Connecting

```bash
ssh <username>@<laptop-ip>
```

If the laptop is on the same Tailscale/Headscale network:

```bash
ssh <username>@<hostname>
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

**SSH connection refused:** Verify `services.openssh.enable` is true in the
host config (enabled by default in the Keystone OS module).

**Key not accepted:** Ensure the public key is in `authorizedKeys` for the
correct user, rebuild was applied, and `sshd` was restarted.

**Can't find the laptop IP:** Check the router's DHCP lease table, or run
`ip addr show` on the laptop directly.
