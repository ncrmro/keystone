# Implementation Plan: Keystone Clusters (006-clusters)

## Summary

Keystone Clusters extends the Keystone infrastructure platform to support multi-node Kubernetes clusters with:
- **Primer Server**: Bootstrap node providing cluster control plane
- **Cloud Integration**: AWS EC2 provisioning via OIDC
- **Mesh Networking**: Headscale for secure inter-node communication
- **Distributed Storage**: Ceph/Rook on ZFS with cloud backup
- **Observability**: Prometheus, Grafana, Loki stack
- **Ingress**: Cloudflare Tunnel for zero-trust public access

The implementation follows a phased approach, starting with a spike to validate the Primer Server bootstrap process.

## Technical Context

### Existing Infrastructure
- NixOS-based configuration with disko module for encrypted ZFS
- TPM2 + LUKS + ZFS native encryption for security
- Secure Boot with custom key enrollment
- ISO installer with nixos-anywhere deployment

### New Components
- Go-based Kubernetes operators (kubebuilder)
- Headscale control plane for WireGuard mesh
- Rook/Ceph for distributed storage
- kube-prometheus-stack for observability
- cloudflared for ingress

### Key Dependencies
- etcd (single-node initially, HA later)
- Kubernetes control plane (k3s or kubeadm)
- Helm for application deployment
- ArgoCD for GitOps

## Constitution Check

### Security
- ✅ All storage encrypted at rest (ZFS + LUKS + TPM2)
- ✅ Mesh networking encrypted (WireGuard via Headscale)
- ✅ No long-lived cloud credentials (OIDC federation)
- ✅ Zero-trust ingress (Cloudflare Tunnel + Access)
- ✅ Audit logging via observability stack

### Declarative Configuration
- ✅ NixOS modules for all system configuration
- ✅ Kubernetes resources as YAML/Helm
- ✅ GitOps via ArgoCD
- ✅ Infrastructure as code for cloud resources

### Modularity
- ✅ Independent components (Headscale, Ceph, Prometheus)
- ✅ Phased implementation with clear milestones
- ✅ Each phase delivers usable functionality

## Project Structure

```
keystone/
├── specs/
│   └── 006-clusters/
│       ├── spec.md                         # Functional requirements
│       ├── PLAN.md                         # This file
│       ├── tasks.md                        # Phased task breakdown
│       └── research.*.md                   # Research documents
│
├── modules/
│   ├── cluster/
│   │   ├── primer/                         # Primer server NixOS module
│   │   │   ├── default.nix
│   │   │   ├── etcd.nix
│   │   │   ├── kubernetes.nix
│   │   │   ├── headscale.nix
│   │   │   └── oidc-provider.nix
│   │   │
│   │   ├── worker/                         # Worker node NixOS module
│   │   │   ├── default.nix
│   │   │   ├── kubelet.nix
│   │   │   └── tailscale.nix
│   │   │
│   │   └── common/                         # Shared cluster configuration
│   │       ├── storage.nix                 # Ceph OSD configuration
│   │       └── monitoring.nix              # Node exporter, Alloy
│   │
│   └── iso-installer/
│       └── tui/                            # Go TUI installer
│           ├── main.go
│           ├── wizard/
│           ├── hardware/
│           └── nixos/
│
├── operators/
│   └── keystone-operator/                  # Kubernetes operator (Go)
│       ├── api/v1alpha1/
│       │   └── nodepool_types.go
│       ├── controllers/
│       │   └── nodepool_controller.go
│       └── main.go
│
├── helm/
│   └── keystone-cluster/                   # Helm chart for cluster addons
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── headscale/
│           ├── observability/
│           ├── storage/
│           └── ingress/
│
└── tests/
    └── cluster/
        ├── spike-primer.nix                # Spike test configuration
        └── integration/                    # End-to-end tests
```

## Component Integration Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              KEYSTONE CLUSTER                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         PRIMER SERVER                                 │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐     │   │
│  │  │   etcd     │  │ kube-api   │  │ Headscale  │  │   OIDC     │     │   │
│  │  │  (raft)    │  │ server     │  │ (mesh ctrl)│  │  Provider  │     │   │
│  │  └──────┬─────┘  └──────┬─────┘  └──────┬─────┘  └──────┬─────┘     │   │
│  │         │               │               │               │            │   │
│  │  ┌──────▼───────────────▼───────────────▼───────────────▼──────┐    │   │
│  │  │                    ZFS (encrypted)                          │    │   │
│  │  └─────────────────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                    ┌─────────▼─────────┐                                    │
│                    │  Headscale Mesh   │                                    │
│                    │   (WireGuard)     │                                    │
│                    └─────────┬─────────┘                                    │
│                              │                                               │
│         ┌────────────────────┼────────────────────┐                         │
│         │                    │                    │                         │
│  ┌──────▼──────┐      ┌──────▼──────┐      ┌──────▼──────┐                 │
│  │  WORKER 1   │      │  WORKER 2   │      │  WORKER N   │                 │
│  │  ┌────────┐ │      │  ┌────────┐ │      │  ┌────────┐ │                 │
│  │  │ kubelet│ │      │  │ kubelet│ │      │  │ kubelet│ │                 │
│  │  └────────┘ │      │  └────────┘ │      │  └────────┘ │                 │
│  │  ┌────────┐ │      │  ┌────────┐ │      │  ┌────────┐ │                 │
│  │  │Ceph OSD│ │      │  │Ceph OSD│ │      │  │Ceph OSD│ │                 │
│  │  └────────┘ │      │  └────────┘ │      │  └────────┘ │                 │
│  └─────────────┘      └─────────────┘      └─────────────┘                 │
│         │                    │                    │                         │
│  ┌──────▼────────────────────▼────────────────────▼──────┐                 │
│  │                   CEPH CLUSTER                         │                 │
│  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  │                 │
│  │   │  MON    │  │  MGR    │  │  RGW    │  │  MDS    │  │                 │
│  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘  │                 │
│  └───────────────────────────────────────────────────────┘                 │
│                              │                                               │
│  ┌───────────────────────────▼───────────────────────────┐                 │
│  │                   OBSERVABILITY                        │                 │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐           │                 │
│  │   │Prometheus│  │ Grafana  │  │   Loki   │           │                 │
│  │   └──────────┘  └──────────┘  └──────────┘           │                 │
│  └───────────────────────────────────────────────────────┘                 │
│                              │                                               │
│  ┌───────────────────────────▼───────────────────────────┐                 │
│  │                     INGRESS                            │                 │
│  │   ┌──────────────────────────────────────────────┐    │                 │
│  │   │         Cloudflare Tunnel (cloudflared)      │    │                 │
│  │   └──────────────────────────────────────────────┘    │                 │
│  └───────────────────────────────────────────────────────┘                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Phased Implementation Overview

### Phase 0: Spike - Primer Server Bootstrap
**Goal**: Validate the core bootstrap process with minimal components

**Scope**:
- Bootable USB with encrypted ZFS (using existing Keystone installer)
- Single-node etcd
- Basic Kubernetes control plane (k3s)
- Headscale deployment
- Cluster CA and initial credentials

**Deliverable**: Working Primer server that can be installed via USB, boots with encryption, and runs basic Kubernetes

### Phase 1: Networking Foundation
**Goal**: Establish secure mesh networking

**Scope**:
- Headscale configuration and ACLs
- DERP relay on Primer
- Node registration workflow
- SSH via Headscale (machine access)
- kubectl via Headscale (cluster access)

**Deliverable**: Nodes can join the mesh network and communicate securely

### Phase 2: Cloud Provider Integration
**Goal**: Enable AWS node provisioning without static credentials

**Scope**:
- OIDC provider on Primer
- AWS IAM trust relationship
- NodePool CRD and operator
- EC2 instance provisioning
- Cloud-init for node bootstrap

**Deliverable**: Operator can provision EC2 instances that auto-join the cluster

### Phase 3: Storage Layer
**Goal**: Distributed storage with cloud backup

**Scope**:
- Rook/Ceph deployment on ZFS
- Storage classes (block, filesystem, object)
- RGW for S3 compatibility
- ZFS snapshot automation
- Cloud sync to AWS S3

**Deliverable**: Persistent storage available to workloads with offsite backup

### Phase 4: Observability
**Goal**: Full monitoring and logging stack

**Scope**:
- kube-prometheus-stack deployment
- Loki + Alloy for log collection
- Custom Keystone dashboards
- Alertmanager configuration
- ServiceMonitors for all components

**Deliverable**: Complete observability for cluster and workloads

### Phase 5: Ingress
**Goal**: Zero-trust public access

**Scope**:
- cloudflared Deployment
- Cloudflare Access policies
- Ingress for Grafana, ArgoCD, etc.
- Optional dedicated ingress nodes

**Deliverable**: Public services accessible via Cloudflare Tunnel

### Phase 6: TUI Installer
**Goal**: User-friendly installation experience

**Scope**:
- Go TUI with Bubbletea
- Hardware detection
- Guided configuration
- NixOS integration
- qcow2 testing workflow

**Deliverable**: Interactive installer for Primer server bootstrap

## Testing Infrastructure

### Framework Selection

Testing Keystone Clusters requires internet access for pulling container images and communicating with external APIs (like AWS). We use **microvm.nix** as our primary testing framework to satisfy these requirements while maintaining near-instant boot times.

| Feature | Benefit |
|---------|---------|
| Internet Access | VMs use user-mode networking (SLIRP) to pull images at runtime |
| Performance | ~10s boot times for a full cluster (Primer + 3 Workers) |
| Port Forwarding | Easy access to k3s API (16443) and Headscale (18080) from host |
| Portability | Runs as a normal user process (no root required) |

### Running Tests

The test suite orchestrates a multi-node cluster including the Primer node and multiple Worker nodes.

```bash
# Start the full cluster (Primer + 3 Workers)
./bin/test-cluster-microvm --workers

# Access the Primer node
ssh -p 22223 root@localhost

# Check cluster status (from host)
export KUBECONFIG=~/.kube/keystone-test.yaml # if configured
kubectl get nodes
```

### Component Validation

| Component | Validation Method |
|-----------|-------------------|
| Networking | `tailscale ping` between all nodes in the mesh |
| Kubernetes | `kubectl get nodes` shows all workers as Ready |
| Secrets | `agenix` decrypts Headscale keys in initrd/boot |
| Storage | Ceph OSDs join the cluster from worker nodes |

## Risk Mitigation

### Technical Risks
| Risk | Mitigation |
|------|------------|
| Image Pull Failures | Use MicroVMs with NAT access; cache images in local registry if needed |
| Headscale stability | Use stable release, have DERP fallback |
| OIDC token expiry issues | Configure proper token refresh |
| Cloud provider API limits | Implement backoff and retry |

### Schedule Risks
| Risk | Mitigation |
|------|------------|
| Integration issues | Continuous validation via MicroVM cluster |
| External dependencies | Pin versions, automate updates |

## Success Criteria

### Spike Complete When (MicroVM-First)
- [ ] Primer boots via MicroVM with k3s running
- [ ] Headscale pod is healthy and pulls image successfully
- [ ] Workers register via pre-auth key over virtual network
- [ ] All 4 nodes can `tailscale ping` each other
- [ ] Cluster is reachable from host via port-forwarding

### MVP Complete When
- [ ] Phases 0-4 complete
- [ ] At least 3 nodes in cluster
- [ ] Storage available to workloads (Ceph/Rook)
- [ ] Metrics and logs being collected (Prometheus/Loki)

### Full Implementation When
- [ ] All phases complete
- [ ] TUI installer tested on 3+ hardware configs
- [ ] Documentation complete
- [ ] End-to-end tests passing in MicroVM and physical hardware

## Next Steps

1. ~~Review this plan with stakeholders~~
2. ~~Set up MicroVM test environment~~
3. Launch cluster via `./bin/test-cluster-microvm --workers`
4. Validate mesh connectivity between all 4 nodes
5. Verify k3s agent join process for workers

