# Agent MicroVMs

> **Looking for the user guide?** See the **[Agent Sandbox User Guide](agent-sandbox.md)** for CLI usage and workflows.

This document outlines the architecture of using MicroVMs to run AI coding agents (Claude Code, Gemini CLI, Codex) in isolated, fully autonomous environments without restrictions.

## Overview

AI coding agents are powerful tools for software development, but running them on a host system presents security concerns:

- **Unrestricted shell access**: Agents execute arbitrary commands
- **File system access**: Agents can read/write anywhere the user has permissions
- **Network access**: Agents can make outbound connections
- **Credential exposure**: SSH keys, API tokens, and other secrets may be accessible

MicroVMs provide a lightweight, ephemeral isolation boundary that allows agents to operate with full autonomy inside a sandboxed environment while protecting the host system.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Host System                                                         │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ nix develop shell                                             │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │ MicroVM (QEMU direct kernel boot)                       │  │  │
│  │  │                                                         │  │  │
│  │  │  ┌─────────────────┐   ┌─────────────────────────────┐  │  │  │
│  │  │  │ AI Agent        │   │ Development Tools           │  │  │  │
│  │  │  │ - claude-code   │   │ - git, gh                   │  │  │  │
│  │  │  │ - gemini-cli    │   │ - language runtimes         │  │  │  │
│  │  │  │ - codex         │   │ - build tools               │  │  │  │
│  │  │  └─────────────────┘   └─────────────────────────────┘  │  │  │
│  │  │                                                         │  │  │
│  │  │  ┌─────────────────────────────────────────────────┐    │  │  │
│  │  │  │ Shared Workspace (9p/virtiofs mount)            │    │  │  │
│  │  │  │ /workspace → host project directory             │    │  │  │
│  │  │  └─────────────────────────────────────────────────┘    │  │  │
│  │  │                                                         │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Components

1. **Dev Shell**: Nix development shell containing the microvm runner and host-side tools
2. **MicroVM**: Lightweight QEMU VM with direct kernel boot (no UEFI overhead)
3. **Agent Environment**: NixOS guest with AI agents and development tools pre-installed
4. **Shared Workspace**: Host directory mounted into the VM for bidirectional file access

## Benefits

### Security Isolation

- **Process isolation**: Agent processes cannot escape the VM boundary
- **Filesystem isolation**: Only explicitly shared directories are accessible
- **Network isolation**: Can be configured with no network, filtered network, or full access
- **Credential isolation**: Host secrets (SSH keys, API tokens) are not accessible unless explicitly shared

### Unrestricted Agent Operation

Inside the MicroVM, agents can operate without the typical safety restrictions:

- Execute any shell command without confirmation
- Modify any file in the workspace
- Install packages and dependencies
- Run long-running processes
- Access the network (if enabled)

This enables truly autonomous operation for tasks like:

- Large-scale refactoring
- Dependency upgrades with full test suites
- Security audits and penetration testing
- CI/CD pipeline development

### Reproducibility

- Declarative NixOS configuration ensures identical environments
- Ephemeral VMs start fresh each time
- No accumulated state or drift

## Configuration

### Example MicroVM Configuration

```nix
# tests/microvm/agent.nix
{
  pkgs,
  config,
  lib,
  ...
}: {
  microvm = {
    hypervisor = "qemu";

    # Memory allocation for agent workloads
    mem = 8192;  # 8GB RAM
    vcpu = 4;    # 4 vCPUs

    # Share the project directory with the guest
    shares = [{
      tag = "workspace";
      source = "/path/to/project";
      mountPoint = "/workspace";
      proto = "virtiofs";  # or "9p" for broader compatibility
    }];

    # Network access for API calls and package downloads
    interfaces = [{
      type = "user";
      id = "vm-agent";
    }];
  };

  # AI Agent packages
  environment.systemPackages = with pkgs; [
    # AI Agents
    claude-code      # Anthropic's Claude Code CLI
    # gemini-cli     # Google's Gemini CLI (when packaged)
    # codex-cli      # OpenAI Codex CLI (when packaged)

    # Development tools
    git
    gh               # GitHub CLI
    jq
    ripgrep
    fd

    # Language runtimes (customize as needed)
    nodejs
    python3
    rustc
    cargo
    go

    # Build tools
    gnumake
    cmake
    gcc
  ];

  # Configure git for the agent
  programs.git = {
    enable = true;
    config = {
      user.name = "AI Agent";
      user.email = "agent@microvm.local";
      safe.directory = "/workspace";
    };
  };

  # Auto-login and start agent on boot
  services.getty.autologinUser = "agent";

  users.users.agent = {
    isNormalUser = true;
    home = "/home/agent";
    extraGroups = ["wheel"];
    initialPassword = "agent";
  };

  # Passwordless sudo for agent operations
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.05";
}
```

### Dev Shell Integration

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    microvm.url = "github:astro/microvm.nix";
  };

  outputs = { self, nixpkgs, microvm }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.agent-vm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        microvm.nixosModules.microvm
        ./microvm/agent.nix
      ];
    };

    devShells.${system}.agent = pkgs.mkShell {
      buildInputs = [
        # The microvm runner
        self.nixosConfigurations.agent-vm.config.microvm.declaredRunner
      ];

      shellHook = ''
        echo "Agent MicroVM development shell"
        echo "Run: microvm-run"
      '';
    };
  };
}
```

## Usage

### Starting an Agent MicroVM

```bash
# Enter the development shell
nix develop .#agent

# Start the MicroVM
microvm-run

# The agent environment is now running
# Connect via serial console or SSH
```

### Running Claude Code Inside the MicroVM

```bash
# Inside the MicroVM
cd /workspace

# Start Claude Code with full autonomy
claude --dangerously-skip-permissions

# Or run a specific task
claude "Refactor all API endpoints to use async/await"
```

### Automated Task Execution

Create a wrapper script for fully autonomous operation:

```bash
#!/usr/bin/env bash
# bin/agent-task
set -euo pipefail

TASK="$1"

# Build and run the microvm with the task
nix develop .#agent --command bash -c "
  microvm-run &
  MICROVM_PID=\$!

  # Wait for VM to boot
  sleep 10

  # Execute task via SSH or console
  ssh -o StrictHostKeyChecking=no agent@localhost -p 2222 \\
    'cd /workspace && claude --dangerously-skip-permissions \"$TASK\"'

  # Shutdown VM
  kill \$MICROVM_PID
"
```

Usage:

```bash
./bin/agent-task "Add comprehensive test coverage to the auth module"
```

## Network Configuration Options

### No Network (Maximum Isolation)

```nix
microvm = {
  # No interfaces = no network
  interfaces = [];
};
```

### NAT Network (Default)

```nix
microvm = {
  interfaces = [{
    type = "user";
    id = "vm-net";
  }];
};
```

### Bridged Network

```nix
microvm = {
  interfaces = [{
    type = "bridge";
    id = "vm-br";
    bridge = "br0";
  }];
};
```

## Credential Management

### Passing API Keys

Mount a secrets directory or use environment variables:

```nix
microvm = {
  shares = [
    {
      tag = "workspace";
      source = "/path/to/project";
      mountPoint = "/workspace";
      proto = "virtiofs";
    }
    {
      tag = "secrets";
      source = "/run/secrets/agent";  # tmpfs with API keys
      mountPoint = "/run/secrets";
      proto = "virtiofs";
    }
  ];
};
```

Or pass via environment:

```bash
ANTHROPIC_API_KEY="sk-..." microvm-run
```

### SSH Key Injection

For git operations requiring authentication:

```nix
{
  # Generate ephemeral SSH key on boot
  systemd.services.setup-ssh = {
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /home/agent/.ssh
      ssh-keygen -t ed25519 -f /home/agent/.ssh/id_ed25519 -N ""
      chown -R agent:users /home/agent/.ssh

      # Display public key for GitHub/GitLab registration
      echo "Add this deploy key to your repository:"
      cat /home/agent/.ssh/id_ed25519.pub
    '';
  };
}
```

## Best Practices

### 1. Ephemeral by Default

Don't persist VM state. Each run should start fresh:

```bash
# Good: Clean start
microvm-run

# Bad: Persisting state
microvm-run --persist-disk
```

### 2. Minimal Privilege Escalation

Only share what's needed:

```nix
# Good: Share only the project
shares = [{
  source = "/home/user/projects/myapp";
  mountPoint = "/workspace";
}];

# Bad: Share entire home directory
shares = [{
  source = "/home/user";
  mountPoint = "/home/user";
}];
```

### 3. Network Isolation When Possible

If the task doesn't require network access, disable it:

```nix
microvm.interfaces = [];
```

### 4. Resource Limits

Set appropriate memory and CPU limits:

```nix
microvm = {
  mem = 4096;  # 4GB
  vcpu = 2;

  # Optional: CPU pinning for isolation
  qemu.extraArgs = [
    "-cpu" "host,migratable=off"
  ];
};
```

### 5. Audit Logging

Enable comprehensive logging for post-task review:

```nix
{
  # Log all commands
  programs.bash.interactiveShellInit = ''
    export HISTFILE=/workspace/.agent-history
    export HISTTIMEFORMAT="%F %T "
    shopt -s histappend
  '';

  # Log agent output
  systemd.services.agent-logger = {
    wantedBy = ["multi-user.target"];
    script = ''
      script -f /workspace/.agent-session.log
    '';
  };
}
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Agent Task
on:
  workflow_dispatch:
    inputs:
      task:
        description: 'Task for the agent'
        required: true

jobs:
  agent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v31
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Run Agent Task
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          nix develop .#agent --command bash -c "
            timeout 3600 ./bin/agent-task '${{ inputs.task }}'
          "

      - name: Upload Results
        uses: actions/upload-artifact@v4
        with:
          name: agent-output
          path: |
            .agent-history
            .agent-session.log
```

## Troubleshooting

### VM Won't Start

```bash
# Check if KVM is available
ls -la /dev/kvm

# Verify microvm runner built correctly
nix build .#nixosConfigurations.agent-vm.config.microvm.declaredRunner
```

### Workspace Not Mounted

```bash
# Inside VM, check mounts
mount | grep workspace

# Verify virtiofsd is running on host
ps aux | grep virtiofsd
```

### Agent Can't Access Network

```bash
# Inside VM, check network
ip addr
ping -c 1 8.8.8.8

# Check DNS resolution
cat /etc/resolv.conf
```

### Performance Issues

```nix
# Increase resources
microvm = {
  mem = 16384;  # 16GB
  vcpu = 8;
};

# Use virtiofs instead of 9p for better I/O
shares = [{
  proto = "virtiofs";
  # ...
}];
```

## Related Documentation

- [MicroVM Testing](../CLAUDE.md#microvm-testing) - General microvm usage in Keystone
- [Testing Procedure](testing-procedure.md) - Overall testing strategy
- [microvm.nix documentation](https://github.com/astro/microvm.nix) - Upstream microvm.nix docs
