# Container Development with Kind and Rootless Docker

This guide shows how to set up and use Kind (Kubernetes in Docker) with rootless Docker for local Kubernetes development.

## Overview

Keystone provides integrated support for container development using:
- **Rootless Docker**: Run Docker without root privileges for improved security
- **Kind**: Create local Kubernetes clusters for testing operators and applications
- **kubectl**: Manage Kubernetes resources
- **Helm**: Package manager for Kubernetes

## Configuration

Enable containers for a user in your Keystone configuration:

```nix
{
  keystone.os = {
    enable = true;
    users.developer = {
      fullName = "Developer User";
      email = "dev@example.com";
      containers.enable = true;  # Enable container development
      terminal.enable = true;     # Also enable terminal for full dev environment
      extraGroups = ["wheel"];
      initialPassword = "changeme";
    };
  };
}
```

## What Gets Installed

When `containers.enable = true`, the following are configured:

**System Level:**
- Rootless Docker daemon
- Kernel modules for container networking
- Increased inotify limits for watching files
- Network forwarding and bridge settings

**User Level:**
- `docker` - Docker client
- `kind` - Kubernetes in Docker
- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager
- `docker-compose` - Multi-container applications

**Shell Aliases:**
- `kind-create` - Create a Kind cluster named "keystone"
- `kind-delete` - Delete the Kind cluster
- `kind-load` - Load Docker images into Kind cluster
- `k` - Alias for kubectl
- `kgp` - Get pods
- `kgs` - Get services
- `kgn` - Get nodes
- `kctx` - Switch kubectl contexts

**Helper Scripts:**
- `~/.local/bin/kind-setup` - Setup Kind cluster with proper configuration
- `~/.local/bin/kind-test-operator` - Test Keystone operator in Kind

## Quick Start

After deploying your configuration and logging in:

### 1. Verify Docker is Running

```bash
# Check Docker status
docker info

# If not running, start it
systemctl --user start docker-rootless-$USER
systemctl --user enable docker-rootless-$USER
```

### 2. Create a Kind Cluster

```bash
# Using the helper script (recommended)
kind-setup

# Or manually
kind create cluster --name keystone
```

This creates a single-node Kubernetes cluster with:
- Port 30000 exposed for NodePort services
- kubectl context automatically configured

### 3. Verify Cluster

```bash
# Check cluster info
kubectl cluster-info

# List nodes
kubectl get nodes

# Check all system pods
kubectl get pods -A
```

## Testing the Keystone Operator

The Keystone HA operator can be tested locally in Kind:

### 1. Build the Operator

```bash
cd packages/keystone-ha/operator
cargo build --release
```

### 2. Create Docker Image

Create a `Dockerfile` in the operator directory:

```dockerfile
FROM debian:bookworm-slim
COPY target/release/keystone-ha-operator /usr/local/bin/
CMD ["/usr/local/bin/keystone-ha-operator"]
```

Build the image:

```bash
docker build -t keystone-ha-operator:dev .
```

### 3. Load into Kind

```bash
# Load the image into your Kind cluster
kind load docker-image keystone-ha-operator:dev --name keystone
```

### 4. Deploy CRDs

```bash
# Apply the Custom Resource Definitions
kubectl apply -f crds/

# Verify CRDs are installed
kubectl get crds
```

### 5. Deploy Operator

Create a deployment manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keystone-ha-operator
  namespace: keystone-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keystone-ha-operator
  template:
    metadata:
      labels:
        app: keystone-ha-operator
    spec:
      containers:
      - name: operator
        image: keystone-ha-operator:dev
        imagePullPolicy: Never
```

Apply it:

```bash
kubectl create namespace keystone-system
kubectl apply -f operator-deployment.yaml
```

### 6. Test with Sample Resources

Create a test Grant:

```yaml
apiVersion: keystone.io/v1alpha1
kind: Grant
metadata:
  name: test-grant
spec:
  grantorRealm: alice-home
  granteeRealm: bob-home
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
```

Apply and watch:

```bash
kubectl apply -f test-grant.yaml
kubectl get grants
kubectl logs -n keystone-system deployment/keystone-ha-operator -f
```

## Development Workflow

### Rapid Iteration

1. Make code changes
2. Rebuild: `cargo build --release`
3. Rebuild image: `docker build -t keystone-ha-operator:dev .`
4. Load into Kind: `kind load docker-image keystone-ha-operator:dev --name keystone`
5. Restart operator: `kubectl rollout restart -n keystone-system deployment/keystone-ha-operator`

### Debugging

```bash
# Get operator logs
kubectl logs -n keystone-system deployment/keystone-ha-operator -f

# Describe resources
kubectl describe grant test-grant

# Get events
kubectl get events -n keystone-system

# Shell into operator pod
kubectl exec -it -n keystone-system deployment/keystone-ha-operator -- /bin/bash
```

### Port Forwarding

Forward Kubernetes services to localhost:

```bash
# Forward a service
kubectl port-forward svc/my-service 8080:80

# Forward to a pod
kubectl port-forward pod/my-pod 8080:80
```

## Cleanup

### Delete Cluster

```bash
kind delete cluster --name keystone
```

### Stop Docker

```bash
systemctl --user stop docker-rootless-$USER
```

### Prune Resources

```bash
# Remove unused Docker resources
docker system prune -a
```

## Troubleshooting

### Docker Socket Not Found

**Problem**: `Cannot connect to the Docker daemon`

**Solution**: Start the Docker rootless service:
```bash
systemctl --user start docker-rootless-$USER
systemctl --user status docker-rootless-$USER
```

### Kind Cluster Won't Start

**Problem**: Kind fails to create cluster

**Solution**: Check Docker is working:
```bash
docker ps
docker info
```

### Image Not Found in Kind

**Problem**: Pod shows `ImagePullBackOff`

**Solution**: Ensure image is loaded and pull policy is correct:
```bash
kind load docker-image myimage:tag --name keystone
# In pod spec, use imagePullPolicy: Never
```

### Port Already in Use

**Problem**: `address already in use`

**Solution**: Change the port mapping in Kind config or stop the conflicting service

### Out of Disk Space

**Problem**: Docker runs out of space

**Solution**: Clean up:
```bash
docker system prune -a --volumes
kind delete cluster --name keystone
```

## Advanced Configuration

### Custom Kind Cluster Config

Create a `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
- role: worker
- role: worker
```

Create cluster:
```bash
kind create cluster --name keystone --config kind-config.yaml
```

### Multiple Clusters

```bash
# Create clusters for different purposes
kind create cluster --name dev
kind create cluster --name staging
kind create cluster --name test

# Switch between them
kubectl config use-context kind-dev
kubectl config use-context kind-staging

# List clusters
kind get clusters
```

### Persistent Storage

Mount host directories into Kind:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /home/developer/data
    containerPath: /data
```

## References

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Docker Rootless Mode](https://docs.docker.com/engine/security/rootless/)
- [kube-rs Documentation](https://kube.rs/)
- [Keystone Operator Spec](../packages/keystone-ha/operator/SPEC.md)
