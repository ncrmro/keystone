# Container Development VM Testing

This VM configuration is used for testing container development with Docker rootless and Kind (Kubernetes in Docker).

## Building the VM

From the repository root:

```bash
nixos-rebuild build-vm --flake ./tests#build-vm-containers
```

Or use the helper script (if available):

```bash
./bin/build-vm containers
```

## Running the VM

After building, run:

```bash
./result/bin/run-build-vm-containers-vm
```

The VM will:
- Start with 4GB RAM and 4 CPU cores
- Create a persistent disk at `./build-vm-containers.qcow2` (20GB)
- Forward SSH to `localhost:2222`
- Start Docker rootless service automatically

## Accessing the VM

### SSH Access

```bash
ssh -p 2222 testuser@localhost
```

**Credentials:**
- Username: `testuser`
- Password: `testpass`

### Serial Console

The VM includes a serial console. In the QEMU window, you can switch to it.

## Testing Docker

Once logged in:

```bash
# Check Docker status
docker info

# Run a test container
docker run hello-world

# List running containers
docker ps
```

## Testing Kind

### Create a Kubernetes Cluster

```bash
# Using the helper script
kind-setup

# Or manually
kind create cluster --name test
```

### Verify Kubernetes

```bash
# Check cluster info
kubectl cluster-info

# List nodes
kubectl get nodes

# List all pods
kubectl get pods -A
```

## Testing the Keystone Operator

### 1. Build the Operator

```bash
# In the VM, clone the repository or mount it
cd /path/to/keystone/packages/keystone-ha/operator

# Build
cargo build --release
```

### 2. Create Docker Image

```bash
# Create a simple Dockerfile if needed
cat > Dockerfile <<EOF
FROM debian:bookworm-slim
COPY target/release/keystone-ha-operator /usr/local/bin/
CMD ["/usr/local/bin/keystone-ha-operator"]
EOF

# Build image
docker build -t keystone-ha-operator:dev .
```

### 3. Load Image into Kind

```bash
kind load docker-image keystone-ha-operator:dev --name test
```

### 4. Deploy to Kind

```bash
# Create namespace
kubectl create namespace keystone-system

# Apply CRDs (create these first)
kubectl apply -f crds/

# Deploy operator
kubectl apply -f deploy/

# Watch logs
kubectl logs -n keystone-system deployment/keystone-ha-operator -f
```

## Helper Commands

The VM includes helpful shell aliases:

- `kind-create` - Create Kind cluster named "keystone"
- `kind-delete` - Delete Kind cluster
- `k` - Alias for kubectl
- `kgp` - kubectl get pods
- `kgs` - kubectl get services
- `kgn` - kubectl get nodes

## Troubleshooting

### Docker Not Running

```bash
# Check service status
systemctl --user status docker

# Start if needed
systemctl --user start docker
systemctl --user enable docker
```

### Out of Disk Space

The VM has a 20GB disk. To check usage:

```bash
df -h
docker system df
```

To clean up:

```bash
# Remove unused Docker resources
docker system prune -a

# Delete Kind cluster
kind delete cluster --name test
```

### Kind Cluster Issues

```bash
# Verify Docker is working
docker ps
docker info

# Check Kind logs
kind get clusters
kubectl cluster-info --context kind-test
```

## Cleaning Up

### Delete VM Disk

```bash
# From the host
rm ./build-vm-containers.qcow2
```

### Rebuild from Scratch

```bash
rm -f ./result ./build-vm-containers.qcow2
nixos-rebuild build-vm --flake ./tests#build-vm-containers
```

## What Gets Installed

**System Level:**
- Docker rootless daemon
- Kernel modules for container networking
- Network forwarding configured
- Increased inotify limits

**User Packages:**
- `docker` and `docker-compose`
- `kind` - Kubernetes in Docker
- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager
- `jq` and `yq-go` - JSON/YAML processors

**Home Manager Modules:**
- Terminal dev environment (zsh, helix, zellij)
- Container development tools and aliases
- kubectl completion

## References

- [Container Development Guide](../../docs/containers-kind.md)
- [Keystone Operator Spec](../../packages/keystone-ha/operator/SPEC.md)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Docker Rootless Mode](https://docs.docker.com/engine/security/rootless/)
