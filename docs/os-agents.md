---
layout: default
title: OS Agents
---

# OS Agents (`keystone.os.agents`)

OS agents are non-interactive NixOS user accounts designed for autonomous LLM-driven operation. Each agent gets an isolated home directory, SSH keys, mail, browser, and optional workspace cloning.

## Quick Start

```nix
keystone.os.agents.drago = {
  fullName = "Drago";
  email = "drago@example.com";
  ssh.publicKey = "ssh-ed25519 AAAAC3... agent-drago";
  space.repo = "ssh://forgejo@git.example.com:2222/drago/agent-space.git";
};
```

## Agent Space (Workspace Cloning)

The `space.repo` option clones a git repository into `/home/agent-{name}/agent-space/` on first boot.

### Forgejo SSH URL Format

When using Forgejo's built-in SSH server, the SSH username must match the system user running Forgejo — typically `forgejo`, **not** `git`.

```
# CORRECT — Forgejo built-in SSH server
ssh://forgejo@git.example.com:2222/owner/repo.git

# WRONG — will fail with "Permission denied (publickey)"
ssh://git@git.example.com:2222/owner/repo.git
git@git.example.com:owner/repo.git
```

The `git@` convention is GitHub/GitLab-specific. Forgejo's built-in SSH server (`START_SSH_SERVER = true`) runs as the `forgejo` user and only accepts connections with that username.

If using Forgejo with OpenSSH (passthrough mode) instead of the built-in server, `git@` may work depending on configuration — but the built-in server always requires `forgejo@`.

### SSH Authentication

The clone service uses the agent's agenix SSH key directly (`/run/agenix/agent-{name}-ssh-key`). The key must be registered in the Forgejo user's SSH keys settings.

### Required Agenix Secrets

Each agent with SSH configured needs:
- `agent-{name}-ssh-key` — Private SSH key (ed25519)
- `agent-{name}-ssh-passphrase` — Passphrase for the key

### Retry Behavior

The clone service retries on failure (up to 10 attempts over 10 minutes with 30-second intervals). Check status with:

```bash
systemctl status clone-agent-space-{name}.service
journalctl -xeu clone-agent-space-{name}.service
```

## What Each Agent Gets

| Feature | Service/Config | Details |
|---------|---------------|---------|
| User account | `agent-{name}` | UID 4001+, group `agents`, no sudo |
| Home directory | `/home/agent-{name}` | chmod 750, readable by `agent-admins` group |
| SSH agent | `ssh-agent-agent-{name}.service` | Auto-loads agenix key with passphrase |
| Git signing | `git-config-agent-{name}.service` | SSH-based commit signing |
| Desktop | `labwc-agent-{name}.service` | Headless Wayland (labwc + wayvnc) |
| Browser | `chromium-agent-{name}.service` | Chromium with remote debugging |
| Mail | himalaya CLI | Stalwart IMAP/SMTP via agenix password |
| Bitwarden | `bw` CLI | Configured for Vaultwarden instance |
| Workspace | `clone-agent-space-{name}.service` | Clones `space.repo` on first boot |

## Debugging

### Clone fails with "Permission denied (publickey)"

1. **Check the SSH username** in `space.repo` — must be `forgejo@` for Forgejo's built-in SSH server
2. **Verify the key is registered** in Forgejo under the correct user's SSH keys
3. **Test manually:**
   ```bash
   sudo runuser -u agent-{name} -- ssh -vvv \
     -i /run/agenix/agent-{name}-ssh-key \
     -o StrictHostKeyChecking=accept-new \
     -o IdentitiesOnly=yes \
     -p 2222 -T forgejo@git.example.com
   ```
4. **Check key fingerprint matches:**
   ```bash
   # Fingerprint of the agenix private key
   ssh-keygen -lf /run/agenix/agent-{name}-ssh-key

   # Compare with the public key in your config
   echo "ssh-ed25519 AAAAC3..." | ssh-keygen -lf -
   ```

### Service dependency order

The clone service depends on:
- `create-agent-homes.service` (or `zfs-agent-datasets.service` on ZFS)

The SSH agent service runs independently and is not a dependency of the clone service.
