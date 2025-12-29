# Quickstart: Agent Sandbox

Get an AI coding agent running in an isolated sandbox in under 5 minutes.

## Prerequisites

- NixOS with flakes enabled
- KVM support (`ls /dev/kvm` should succeed)
- A git repository to work on

## 1. Enable Agent Sandbox

Add to your NixOS configuration:

```nix
# configuration.nix or flake module
{
  imports = [ keystone.nixosModules.agent ];

  keystone.agent = {
    enable = true;
    # Optional: customize defaults
    defaults = {
      memory = 8192;  # 8GB RAM
      vcpus = 4;
    };
    # Enable dev server proxy
    proxy.enable = true;
  };
}
```

Rebuild:
```bash
sudo nixos-rebuild switch
```

## 2. Start a Sandbox

Navigate to your project and start:

```bash
cd ~/projects/myapp
keystone agent start
```

This will:
1. Create a MicroVM with your project cloned to `/workspace/`
2. Install AI agents (Claude Code, etc.)
3. Attach you to a Zellij session

## 3. Run the Agent

Inside the sandbox, start Claude Code:

```bash
cd /workspace
claude
```

The agent runs with full autonomy - no permission prompts!

## 4. Sync Changes Back

When the agent is done, sync changes to your host:

```bash
# From host terminal (Ctrl-A D to detach from sandbox)
keystone agent sync
```

Your changes now appear in your local git repository.

## Common Workflows

### Auto-Start with Claude

```bash
keystone agent start --agent claude
```

### Work on Multiple Branches

```bash
# Add a worktree for a feature branch
keystone agent worktree add feature-auth --create

# Attach to that worktree
keystone agent attach --worktree feature-auth
```

### Access Dev Server

```bash
# Inside sandbox, start your dev server
npm run dev  # Runs on port 3000

# From host browser, visit:
# http://myapp.sandbox.local:3000
```

### Fresh Start

```bash
# Discard previous sandbox state
keystone agent start --fresh
```

## Sync Modes

| Mode | When to Use |
|------|-------------|
| `manual` (default) | Full control, explicit sync |
| `auto-commit` | Sync on each git commit |
| `auto-idle` | Sync after 30s of inactivity |

Set sync mode:
```bash
keystone agent start --sync-mode auto-commit
```

## Troubleshooting

### "KVM not available"

```bash
# Check KVM support
ls -la /dev/kvm

# If missing, enable virtualization in BIOS
# and ensure kvm module is loaded:
sudo modprobe kvm_intel  # or kvm_amd
```

### Nested VMs Not Working

```bash
# Check nested virtualization
cat /sys/module/kvm_intel/parameters/nested  # Should be Y

# If N, add to configuration.nix:
boot.extraModprobeConfig = "options kvm_intel nested=1";
```

### Sandbox Won't Start

```bash
# Check status
keystone agent status

# View logs
journalctl -u keystone-agent-myapp

# Try fresh start
keystone agent start --fresh
```

### Can't Access Dev Server

```bash
# Ensure proxy is running
systemctl status caddy

# Check mDNS resolution
avahi-resolve -n myapp.sandbox.local
```

## Next Steps

- [CLI Reference](./contracts/cli-spec.md) - Full command documentation
- [Data Model](./data-model.md) - Entity definitions
- [Research](./research.md) - Technology decisions
