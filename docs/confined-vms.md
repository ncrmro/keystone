# Confined NixOS VMs for Sandboxed Development

This document describes how to create and use confined NixOS virtual machines for sandboxed development work, particularly designed for AI assistants like Claude to work in isolated environments without internet access.

## Overview

Confined VMs provide a secure, reproducible development environment with the following characteristics:

- **Network Isolation**: No internet access (confined networking)
- **Host Integration**: Direct access to worktrees from the host via shared directories
- **Complete Development Environment**: All necessary tools pre-installed via Nix
- **Fast Iteration**: Uses `nixos-rebuild build-vm` for rapid testing cycles
- **Reproducibility**: Declarative configuration ensures consistent environments

## Use Cases

1. **AI Assistant Development**: Provide Claude or other AI assistants with a sandboxed environment to work on code
2. **Security Testing**: Test potentially untrusted code without network access
3. **Offline Development**: Work on projects in fully offline environments
4. **Reproducible Builds**: Ensure builds are not affected by external network resources

## Architecture

### Directory Sharing

The VM uses QEMU's 9P/virtfs to mount host directories into the guest:

```
Host                          Guest
────────────────────         ────────────────────
/path/to/worktree     →      /mnt/workspace
/nix/store (ro)       →      /nix/store (9P, auto)
```

### Network Configuration

The VM has three network configuration options:

1. **Fully Confined** (recommended for Claude): No network devices
2. **Host-Only**: Network device but no internet gateway
3. **Restricted**: Limited network with firewall rules

## Quick Start

### 1. Create a Confined VM Configuration

Create a new VM configuration file at `vms/confined-dev/configuration.nix`:

```nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  system.stateVersion = "25.05";

  # System identity
  networking.hostName = "keystone-confined-dev";

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Mount host workspace
  fileSystems."/mnt/workspace" = {
    device = "workspace";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "msize=104857600"  # 100MB msize for better performance
      "rw"
    ];
  };

  # NETWORK ISOLATION: Disable all networking
  networking.interfaces = lib.mkForce {};
  networking.useDHCP = lib.mkForce false;
  networking.dhcpcd.enable = lib.mkForce false;
  networking.wireless.enable = lib.mkForce false;

  # Firewall: deny all (defense in depth)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };

  # VM-specific configuration
  virtualisation.vmVariant = {
    # Additional shared directories
    virtualisation.sharedDirectories = {
      workspace = {
        source = "/path/to/your/worktree";
        target = "/mnt/workspace";
      };
    };

    # No network device at all (most secure)
    virtualisation.qemu.networkingOptions = [];

    # Generous resources for development
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.diskSize = 20000;  # 20GB
  };

  # Enable serial console
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Users
  users.mutableUsers = true;

  # Development user
  users.users.dev = {
    isNormalUser = true;
    description = "Development User";
    initialPassword = "dev";
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
  };

  users.users.root.initialPassword = "root";

  # Allow sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Nix configuration
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "dev"];
    # Disable network access for nix
    allowed-uris = lib.mkForce [];
  };

  # Complete development environment
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    neovim
    git
    curl
    wget
    htop
    tmux
    zellij

    # Build tools
    gnumake
    gcc
    clang
    cmake

    # Language toolchains
    rustc
    cargo
    go
    nodejs_22
    python3

    # Nix tools
    nix-tree
    nix-diff
    nixfmt-rfc-style

    # Development utilities
    ripgrep
    fd
    bat
    eza
    zoxide
    fzf
    jq
    yq
  ];

  # ZSH configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Git configuration
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      safe.directory = "/mnt/workspace";
    };
  };

  # Home-manager integration (optional)
  home-manager.users.dev = {
    home.stateVersion = "25.05";

    programs.git = {
      userName = "Confined Dev";
      userEmail = "dev@confined-vm";
    };

    programs.zsh = {
      enable = true;
      shellAliases = {
        ws = "cd /mnt/workspace";
        ll = "eza -la";
      };
      initExtra = ''
        # Workspace shortcut
        export WORKSPACE=/mnt/workspace
        cd $WORKSPACE
      '';
    };
  };
}
```

### 2. Add to Flake

Add the confined VM configuration to your `flake.nix`:

```nix
nixosConfigurations = {
  # ... existing configurations ...

  confined-dev = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      home-manager.nixosModules.home-manager
      ./vms/confined-dev/configuration.nix
    ];
  };
};
```

### 3. Build the VM

Build the VM using nixos-rebuild:

```bash
nixos-rebuild build-vm --flake .#confined-dev
```

### 4. Run the VM

The build creates a script at `./result/bin/run-keystone-confined-dev-vm`. Before running, you need to configure the workspace path:

```bash
# Option 1: Edit the generated script to set workspace path
sed -i "s|/path/to/your/worktree|$(pwd)|g" ./result/bin/run-keystone-confined-dev-vm

# Option 2: Create a wrapper script
cat > run-confined-vm.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Path to the worktree on host
WORKSPACE_PATH="${1:-$(pwd)}"

# Run the VM with the workspace mounted
QEMU_KERNEL_PARAMS="workspace.source=$WORKSPACE_PATH" \
  ./result/bin/run-keystone-confined-dev-vm
EOF

chmod +x run-confined-vm.sh
./run-confined-vm.sh /path/to/worktree
```

### 5. Access the VM

Once the VM boots, log in with:

- Username: `dev`
- Password: `dev`

Your worktree will be available at `/mnt/workspace`.

## Advanced Configuration

### Option 1: Completely Isolated (Recommended)

No network device at all:

```nix
virtualisation.vmVariant = {
  virtualisation.qemu.networkingOptions = [];
};

networking.interfaces = lib.mkForce {};
networking.useDHCP = lib.mkForce false;
```

### Option 2: Host-Only Networking

Network device but no internet gateway:

```nix
virtualisation.vmVariant = {
  virtualisation.qemu.networkingOptions = [
    "-net nic,model=virtio"
    "-net user,restrict=on,hostfwd=tcp::2222-:22"
  ];
};

# Guest configuration
networking.useDHCP = true;
services.openssh.enable = true;
```

With this setup:
- The VM can communicate with the host via SSH on port 2222
- No internet access (QEMU user networking with `restrict=on`)
- Useful for Claude to receive commands via SSH

### Option 3: Firewall-Based Restriction

Network device with strict firewall:

```nix
networking = {
  useDHCP = true;
  firewall = {
    enable = true;
    # Deny all outbound by default
    extraCommands = ''
      iptables -P OUTPUT DROP
      iptables -A OUTPUT -o lo -j ACCEPT
      iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    '';
  };
};
```

## Development Workflow

### For Claude/AI Assistants

1. **Host prepares workspace**: Clone repository to host filesystem
2. **Start confined VM**: Boot VM with workspace mounted
3. **Claude works in VM**: All development happens in `/mnt/workspace`
4. **Changes persist**: Modifications visible immediately on host
5. **No internet access**: Claude cannot fetch external resources

### Example Session

```bash
# On host: Build and prepare VM
cd /path/to/keystone
nixos-rebuild build-vm --flake .#confined-dev

# On host: Start VM with current directory as workspace
./run-confined-vm.sh $(pwd)

# In VM: Claude works on the project
cd /mnt/workspace
git status
nix build .#iso
# ... development work ...

# Changes are immediately visible on host
```

### Nix Development Shell

For projects with flakes, create a comprehensive dev shell:

```nix
# Add to your project's flake.nix
devShells.x86_64-linux.confined = pkgs.mkShell {
  name = "confined-dev-shell";

  buildInputs = with pkgs; [
    # All necessary development tools
    git
    nixfmt-rfc-style
    nixos-rebuild
    # ... project-specific tools ...
  ];

  shellHook = ''
    echo "Confined development environment"
    echo "Workspace: $WORKSPACE"
    echo "No internet access - all dependencies must be pre-cached"
  '';
};
```

Usage in VM:

```bash
cd /mnt/workspace
nix develop .#confined
```

## Pre-Caching Dependencies

Since the VM has no internet access, all dependencies must be pre-cached on the host:

### Method 1: Build on Host First

```bash
# On host: Build everything to populate Nix store
nix build .#iso
nix develop .#confined --command echo "Dependencies cached"

# Then start VM - it will use the host's /nix/store
```

### Method 2: Explicit Pre-Fetch

```bash
# On host: Pre-fetch all inputs
nix flake archive
nix flake prefetch

# For specific packages
nix build .#package --no-link
```

### Method 3: Include Dependencies in VM Closure

```nix
# In VM configuration
environment.systemPackages = with pkgs; [
  # Include all packages needed by your project
  (callPackage /mnt/workspace/package.nix {})
];
```

## Performance Optimization

### 9P Performance Tuning

The `msize` parameter significantly affects shared directory performance:

```nix
fileSystems."/mnt/workspace" = {
  device = "workspace";
  fsType = "9p";
  options = [
    "trans=virtio"
    "version=9p2000.L"
    "msize=104857600"  # 100MB (recommended for large files)
    "cache=loose"      # Better performance, less safety
    "rw"
  ];
};
```

Cache modes:
- `cache=none`: Safest, slowest (no cache)
- `cache=loose`: Better performance, metadata cached (recommended)
- `cache=fscache`: Best performance, requires fscache support

### Memory and CPU Allocation

```nix
virtualisation.vmVariant = {
  virtualisation.memorySize = 8192;  # 8GB for large builds
  virtualisation.cores = 8;          # Match host CPU cores
  virtualisation.diskSize = 40000;   # 40GB for Nix store
};
```

### Nix Build Optimization

```nix
nix.settings = {
  cores = 8;           # Parallel jobs per build
  max-jobs = 4;        # Number of concurrent builds
  sandbox = true;      # Ensure reproducibility
};
```

## Security Considerations

### Network Isolation Verification

Inside the VM, verify network isolation:

```bash
# Should show no network interfaces (except lo)
ip addr show

# Should fail - no internet access
ping 8.8.8.8
curl https://google.com

# Nix builds should fail if they need network
nix build .#something-that-needs-network
```

### Workspace Permissions

The workspace mount respects host permissions:

```nix
virtualisation.sharedDirectories = {
  workspace = {
    source = "/path/to/worktree";
    target = "/mnt/workspace";
    # No permission remapping - uses host permissions
  };
};
```

To ensure the `dev` user can write:

```bash
# On host: Set appropriate permissions
chown -R $(id -u):$(id -g) /path/to/worktree
chmod -R u+rwX /path/to/worktree
```

### Read-Only Workspaces

For extra safety, mount workspace as read-only:

```nix
fileSystems."/mnt/workspace" = {
  device = "workspace";
  fsType = "9p";
  options = [
    "trans=virtio"
    "version=9p2000.L"
    "ro"  # Read-only
  ];
};
```

## Automation

### Build and Run Script

Create `bin/confined-vm` for easy management:

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${1:-$(pwd)}"
FLAKE_CONFIG="${2:-confined-dev}"

echo "Building confined VM: $FLAKE_CONFIG"
nixos-rebuild build-vm --flake ".#$FLAKE_CONFIG"

echo "Starting VM with workspace: $WORKSPACE"
exec ./result/bin/run-keystone-${FLAKE_CONFIG}-vm
```

Usage:

```bash
chmod +x bin/confined-vm
./bin/confined-vm /path/to/project confined-dev
```

### Integration with Claude Agent

Example workflow for automated Claude sessions:

```bash
#!/usr/bin/env bash
# Start confined VM and connect Claude via serial console

VM_NAME="keystone-confined-dev"
WORKSPACE="$(pwd)"

# Build VM
nixos-rebuild build-vm --flake ".#confined-dev"

# Start VM with serial console on pipe
mkfifo /tmp/claude-vm-in /tmp/claude-vm-out

./result/bin/run-keystone-confined-dev-vm \
  -serial pipe:/tmp/claude-vm-in,pipe:/tmp/claude-vm-out &

VM_PID=$!

# Claude can now interact via the pipes
# /tmp/claude-vm-in  (write commands to VM)
# /tmp/claude-vm-out (read output from VM)
```

## Troubleshooting

### Workspace Not Mounted

Check QEMU command line includes the shared directory:

```bash
ps aux | grep qemu | grep workspace
# Should see: -virtfs local,path=/path/to/workspace,...
```

Verify mount in VM:

```bash
mount | grep workspace
# Should see: workspace on /mnt/workspace type 9p (rw,...)
```

### Permission Denied on Workspace

Check host permissions:

```bash
# On host
ls -la /path/to/workspace
# Ensure readable/writable by your user
```

Check VM user UID:

```bash
# In VM
id dev
# Should match host user UID for seamless access
```

### Slow Filesystem Performance

Increase msize:

```nix
options = [
  "msize=104857600"  # 100MB
  "cache=loose"
];
```

Or use alternative sharing method (NFS, etc.) for large workspaces.

### Network Access Detected

Verify network is disabled:

```bash
# In VM - should show only lo interface
ip link show

# Check firewall
iptables -L -n

# Verify nix cannot access network
nix build nixpkgs#hello --no-net-fallback
```

## Best Practices

1. **Pre-cache dependencies**: Build on host before starting VM
2. **Use version control**: Keep worktree in git for easy reset
3. **Regular snapshots**: Snapshot VM disk after setting up development environment
4. **Monitor resources**: Watch RAM/CPU usage during large builds
5. **Verify isolation**: Always test that network is truly disabled
6. **Document dependencies**: Maintain a list of required packages
7. **Use nix shells**: Leverage project-specific development shells

## Integration with Existing Keystone Infrastructure

### Using Keystone Modules

Confined VMs can use Keystone modules selectively:

```nix
{
  imports = [
    ../../modules/users  # Keystone user management
    # Exclude: disko, secure-boot, tpm (not needed in VM)
  ];

  # Override for VM testing
  keystone.users.primaryUser = "dev";
}
```

### Sharing Nix Store

The VM automatically shares the host's `/nix/store` via 9P, so:

- No need to rebuild packages already built on host
- Instant access to all host's Nix packages
- Reduced VM disk usage

### Testing Configurations

Use confined VMs to test Keystone configurations before deployment:

```bash
# Build configuration in confined VM
cd /mnt/workspace
nix build .#test-server --no-link

# Verify build artifacts
ls -la result/
```

## Examples

### Example 1: Rust Development

```nix
# vms/confined-rust/configuration.nix
environment.systemPackages = with pkgs; [
  rustc
  cargo
  rust-analyzer
  clippy
  rustfmt
];

# In VM
cd /mnt/workspace
cargo build --release
cargo test
```

### Example 2: NixOS Configuration Development

```nix
# vms/confined-nixos/configuration.nix
environment.systemPackages = with pkgs; [
  nixos-rebuild
  nixfmt-rfc-style
  nix-tree
];

# In VM
cd /mnt/workspace
nixos-rebuild build-vm --flake .#myconfig
```

### Example 3: Documentation Writing

```nix
# vms/confined-docs/configuration.nix
environment.systemPackages = with pkgs; [
  mdbook
  pandoc
  texlive.combined.scheme-medium
];

# In VM
cd /mnt/workspace/docs
mdbook build
```

## References

- [QEMU 9P/virtfs Documentation](https://wiki.qemu.org/Documentation/9psetup)
- [NixOS VM Testing](https://nixos.org/manual/nixos/stable/index.html#sec-nixos-tests)
- [Nix Sandbox](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-sandbox)

## Future Enhancements

Potential improvements to confined VM infrastructure:

1. **Automated dependency analysis**: Scan project and pre-fetch all dependencies
2. **Resource monitoring**: Built-in tools to track VM resource usage
3. **Multi-workspace support**: Mount multiple directories for complex projects
4. **Container integration**: Use systemd-nspawn as lighter alternative to full VM
5. **Claude-specific optimizations**: Tailored configurations for AI assistant workflows
