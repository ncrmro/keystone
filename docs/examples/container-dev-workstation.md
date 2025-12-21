# Container Development Workstation Example

This example shows how to configure a development workstation with container development tools (Docker rootless + Kind) for testing Kubernetes operators and applications.

## Use Case

A developer wants to:
- Test Kubernetes operators locally using Kind
- Use rootless Docker for security
- Have a full terminal development environment
- Access their workstation remotely via SSH

## Configuration

```nix
{
  description = "Container development workstation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    keystone.url = "github:ncrmro/keystone";
    home-manager.url = "github:nix-community/home-manager";
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.dev-workstation = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        keystone.nixosModules.operating-system
        {
          # Required: Set unique host ID for ZFS
          networking.hostId = "a1b2c3d4";  # Generate: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
          networking.hostName = "dev-workstation";

          # Keystone OS configuration
          keystone.os = {
            enable = true;

            # Storage with ZFS
            storage = {
              type = "zfs";
              devices = [ "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S6B2NS0T123456" ];
              swap.size = "16G";
            };

            # Developer user with container tools
            users.developer = {
              fullName = "Developer User";
              email = "dev@example.com";
              
              # Enable container development
              containers.enable = true;
              
              # Enable terminal dev environment
              terminal.enable = true;
              
              # Additional groups for system access
              extraGroups = [ "wheel" "networkmanager" ];
              
              # SSH access
              authorizedKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKey dev@laptop"
              ];
              
              # Set initial password (change on first login)
              initialPassword = "changeme";
              
              # Optional: ZFS quota for home directory
              zfs.quota = "500G";
            };

            # Enable Secure Boot
            secureBoot.enable = true;

            # Enable TPM for automatic disk unlock
            tpm.enable = true;

            # Enable SSH in initrd for remote unlock (fallback)
            remoteUnlock = {
              enable = true;
              authorizedKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKey dev@laptop"
              ];
            };
          };

          # System configuration
          system.stateVersion = "24.11";

          # Additional system packages
          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            # Additional tools for development
            jq
            yq-go
            vim
          ];

          # Enable SSH server
          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              PermitRootLogin = "no";
            };
          };

          # Configure networking
          networking.networkmanager.enable = true;
          networking.firewall = {
            enable = true;
            allowedTCPPorts = [ 22 ];  # SSH
          };
        }
      ];
    };
  };
}
```

## Deployment

### 1. Generate Host ID

```bash
head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
```

### 2. Find Disk ID

```bash
ls -l /dev/disk/by-id/
```

### 3. Update Configuration

Replace the `networking.hostId` and `storage.devices` with your values.

### 4. Deploy with nixos-anywhere

```bash
# Boot target machine from Keystone ISO
# Get IP address from installer console

# Deploy from your local machine
nixos-anywhere --flake .#dev-workstation root@<installer-ip>
```

## Post-Installation

### 1. SSH into the System

```bash
ssh developer@<workstation-ip>
```

### 2. Verify Docker is Working

```bash
# Start Docker service
systemctl --user start docker-rootless-developer
systemctl --user enable docker-rootless-developer

# Test Docker
docker info
docker run hello-world
```

### 3. Create a Kind Cluster

```bash
# Use the helper script
kind-setup

# Or create manually
kind create cluster --name test
```

### 4. Verify Kubernetes

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

## Development Workflow

### Testing the Keystone Operator

```bash
# Navigate to operator directory
cd ~/projects/keystone/packages/keystone-ha/operator

# Build operator
cargo build --release

# Build Docker image
docker build -t keystone-ha-operator:dev .

# Load into Kind
kind load docker-image keystone-ha-operator:dev --name test

# Deploy CRDs (create these first)
kubectl apply -f crds/

# Deploy operator
kubectl apply -f deploy/

# Watch logs
kubectl logs -n keystone-system deployment/keystone-ha-operator -f
```

### Remote Development

From your laptop:

```bash
# SSH into workstation
ssh developer@dev-workstation

# Attach to existing Zellij session (if any)
zellij attach

# Or start new session
zellij

# Work on operator
cd ~/projects/keystone/packages/keystone-ha/operator
hx src/main.rs
```

## What Gets Installed

With `containers.enable = true`, the following are configured:

**System Level:**
- Rootless Docker daemon
- Kernel modules for container networking
- Increased inotify limits
- Network forwarding enabled

**User Level:**
- Docker client (`docker`)
- Kind (`kind`)
- kubectl (`kubectl`)
- Helm (`helm`)
- docker-compose (`docker-compose`)

**Shell Aliases:**
- `kind-create` - Create Kind cluster
- `kind-delete` - Delete Kind cluster
- `k` - kubectl alias
- `kgp` - kubectl get pods
- `kgs` - kubectl get services
- `kgn` - kubectl get nodes

**Helper Scripts:**
- `~/.local/bin/kind-setup` - Setup Kind cluster
- `~/.local/bin/kind-test-operator` - Test operator in Kind

## Network Configuration

The Kind cluster will:
- Run inside rootless Docker containers
- Use bridge networking (isolated from host)
- Expose port 30000 for NodePort services
- Have kubectl context automatically configured

## Storage Considerations

### ZFS Quotas

Set appropriate quota for your home directory:
```nix
zfs.quota = "500G";  # Adjust based on your needs
```

### Container Storage

Docker images and containers are stored in:
- `~/.local/share/docker/` - Docker data directory
- No sudo/root access required

### Kind Storage

Kind cluster data is stored in Docker containers. To see usage:
```bash
docker system df
```

Clean up with:
```bash
docker system prune -a
```

## Troubleshooting

### Docker Not Starting

Check service status:
```bash
systemctl --user status docker-rootless-developer
journalctl --user -u docker-rootless-developer -f
```

Restart if needed:
```bash
systemctl --user restart docker-rootless-developer
```

### Kind Cluster Creation Fails

Verify Docker is working:
```bash
docker ps
docker info
```

Check available resources:
```bash
df -h  # Disk space
free -h  # Memory
```

### Kubectl Context Issues

List available contexts:
```bash
kubectl config get-contexts
```

Switch to Kind context:
```bash
kubectl config use-context kind-test
```

## See Also

- [Container Development Guide](../containers-kind.md) - Detailed guide for using Kind and Docker
- [Keystone Operator Spec](../../packages/keystone-ha/operator/SPEC.md) - Operator architecture
- [Terminal Development Environment](../modules/terminal-dev-environment.md) - Terminal tools and configuration
