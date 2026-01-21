# Keystone Clusters Specification

## Overview

Keystone Clusters provides a Nix flake for deploying Kubernetes infrastructure on VPS or bare metal servers. The system extends Keystone Base OS (which handles Secure Boot, TPM unlock, and ZFS) to create a self-sovereign cluster architecture centered around a "Primer Server" that bootstraps and manages the entire cluster lifecycle.

## Architecture

### Primer Server

The Primer Server is a single physical or virtual machine that serves as the root of trust for the entire cluster. It is the only component that requires persistent local storage and can operate completely air-gapped.

**Core Responsibilities:**
- Establishes the initial Root of Trust for the cluster
- Stores encrypted root secrets (CA certificates, etcd encryption keys, OIDC signing keys)
- Bootstraps the initial etcd quorum
- Manages cloud provider integrations via OIDC
- Can be taken offline after cluster initialization with secrets encrypted and snapshotted

**Offline Capability:**
- All root secrets are encrypted at rest using TPM-sealed keys
- ZFS snapshots capture the complete system state before going offline
- Cluster continues to operate independently once bootstrapped
- Primer can be brought back online for recovery, rotation, or expansion operations

### Cloud Provider Integration

The Primer Server connects to cloud providers using OIDC federation, eliminating the need for long-lived API credentials.

**Supported Providers:**
- AWS (EC2, EBS, S3, IAM)
- Future: GCP, Azure, Hetzner, Vultr

**OIDC Integration:**
- Primer acts as an OIDC identity provider
- Cloud provider trusts Primer-issued tokens
- Short-lived credentials for all cloud operations
- No static API keys stored in the cluster

### Kubernetes Operator

A custom Kubernetes operator runs on the Primer Server to orchestrate cluster resources.

**Capabilities:**
- Schedule control plane nodes (self-hosted or managed)
- Provision worker nodes on-demand (cloud or bare metal)
- Manage blob storage backends
- Handle node lifecycle (provisioning, updates, decommissioning)

**Node Types:**
- **Control Plane Nodes**: Run etcd, API server, scheduler, controller-manager
- **Worker Nodes**: Execute workloads, can be mixed (bare metal + cloud)
- **Storage Nodes**: Dedicated nodes for Ceph OSDs

## Storage Architecture

### ZFS Foundation

All nodes use ZFS as the base filesystem, providing:

- **Snapshots**: Automatic periodic snapshots for point-in-time recovery
- **Send/Receive**: Efficient backup and replication to remote storage
- **Checksums**: Data integrity verification on every read
- **Compression**: Transparent LZ4 compression for all datasets

**Snapshot Policy:**
- Hourly snapshots retained for 24 hours
- Daily snapshots retained for 7 days
- Weekly snapshots retained for 4 weeks
- Monthly snapshots retained for 12 months

### Distributed Storage (Ceph/Rook)

Ceph runs on top of ZFS to provide distributed storage across the cluster.

**Components:**
- **Rook Operator**: Manages Ceph deployment on Kubernetes
- **Ceph OSDs**: Object Storage Daemons on ZFS datasets
- **Ceph Monitors**: Maintain cluster map (minimum 3 for quorum)
- **Ceph MDS**: Metadata servers for CephFS (optional)

**Storage Classes:**
- `ceph-block`: RBD volumes for databases and stateful workloads
- `ceph-filesystem`: CephFS for shared storage (ReadWriteMany)
- `ceph-object`: S3-compatible object storage via RGW

### Blob Storage Integration

Cloud blob storage (S3, GCS) is integrated for:

- Offsite backup of ZFS snapshots
- Ceph RGW backend for object storage
- Container registry storage
- Log and metrics long-term retention

## Observability Stack

### Monitoring (Grafana + Kube-Prometheus)

**Components:**
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Alertmanager**: Alert routing and silencing
- **Node Exporter**: Host-level metrics
- **kube-state-metrics**: Kubernetes object metrics

**Pre-configured Dashboards:**
- Cluster overview
- Node resource utilization
- Pod and container metrics
- Storage (ZFS + Ceph) health
- Network traffic and latency

### Logging (Loki)

**Components:**
- **Loki**: Log aggregation and querying
- **Promtail**: Log collection agent on all nodes
- **Grafana**: Log visualization and exploration

**Log Retention:**
- Hot storage: 7 days (local SSD)
- Cold storage: 90 days (blob storage)

### Alerting

**Default Alert Rules:**
- Node down or unreachable
- High CPU/memory/disk utilization
- ZFS pool degraded or errors
- Ceph health warnings
- Kubernetes component failures
- Certificate expiration warnings

## Networking

### Headscale (Secure Inter-node Networking)

All cluster nodes communicate over a WireGuard mesh managed by Headscale.

**Features:**
- Encrypted node-to-node communication
- Works across NAT and firewalls
- Supports node migration between networks
- ACL-based access control

**Network Topology:**
- Primer Server runs the Headscale control plane
- All nodes register and receive WireGuard keys
- Direct peer-to-peer connections when possible
- DERP relays for NAT traversal when needed

### Ingress Options

#### Option A: Cloudflare Tunnels

- Zero-trust ingress without exposing public IPs
- Automatic TLS termination
- DDoS protection included
- Ideal for clusters behind NAT or without public IPs

**Configuration:**
- Tunnel daemon runs on dedicated ingress pods
- Routes defined via Kubernetes Ingress annotations
- Supports TCP, HTTP, and WebSocket traffic

#### Option B: Dedicated Ingress Nodes

- Bare metal or cloud nodes with public IPs
- Run ingress controllers (nginx, Traefik, or Envoy)
- Direct control over TLS and routing
- Required for non-HTTP protocols or low-latency requirements

**Load Balancing:**
- MetalLB for bare metal environments
- Cloud provider load balancers for cloud nodes
- DNS-based failover across ingress nodes

## Installation & Setup

### TUI Installer

A terminal-based installer guides users through initial setup.

**Installation Phases:**

1. **Hardware Detection**
   - Identify available disks and network interfaces
   - Detect TPM and Secure Boot capability
   - Validate minimum hardware requirements

2. **Disk Configuration**
   - ZFS pool creation (mirror, RAIDZ1, RAIDZ2)
   - Dataset layout for system, containers, and data
   - Encryption key generation and TPM sealing

3. **Network Configuration**
   - Static IP or DHCP assignment
   - Headscale enrollment
   - Firewall rule configuration

4. **Cluster Bootstrap**
   - Generate cluster CA and secrets
   - Initialize etcd (single-node or existing quorum)
   - Deploy core system components

5. **Cloud Provider Setup** (Optional)
   - Configure OIDC trust with cloud provider
   - Test connectivity and permissions
   - Set up initial node pools

6. **Observability Setup**
   - Deploy Prometheus, Grafana, Loki
   - Configure alert destinations (email, Slack, PagerDuty)
   - Import default dashboards

### Post-Installation

After TUI setup completes:

- Access Grafana dashboard via Cloudflare tunnel or ingress
- Primer Server can be taken offline (secrets encrypted)
- Cluster operates autonomously
- GitOps workflow recommended for ongoing management

## Security Model

### Root of Trust

- TPM 2.0 seals disk encryption keys
- Secure Boot validates boot chain
- Primer Server is the only holder of root CA private keys

### Secret Management

Cluster secrets are managed using **agenix**, which encrypts secrets with age and stores them in git alongside the NixOS configuration. This enables GitOps workflows while keeping secrets secure.

#### Key Hierarchy

The system uses a multi-recipient encryption model where each secret can be decrypted by multiple authorized parties:

```
┌─────────────────────────────────────────────────────────────┐
│                    secrets.nix                               │
│  Defines which age public keys can decrypt which secrets    │
│                                                              │
│  Recipients for each secret:                                 │
│  ├── Primer server's age key (for autonomous decryption)    │
│  ├── Admin 1's age public key                               │
│  ├── Admin 2's age public key                               │
│  └── Admin N's age public key                               │
└─────────────────────────────────────────────────────────────┘
```

**Per-admin keys** allow individual revocation without affecting other administrators. When an admin leaves, only their key is removed and secrets are re-encrypted.

#### Secrets Inventory

| Secret | Purpose | Recipients |
|--------|---------|------------|
| `headscale-private.age` | Headscale main private key | primer + all admins |
| `headscale-noise.age` | Noise protocol key for node communication | primer + all admins |
| `headscale-derp.age` | DERP relay server key | primer + all admins |
| `k8s-ca-key.age` | Kubernetes CA private key | primer + all admins |
| `etcd-encryption.age` | etcd data-at-rest encryption key | primer + all admins |
| `oidc-signing.age` | OIDC token signing key | primer + all admins |

#### Admin Workflows

**Adding a new admin:**
```bash
# 1. New admin generates age keypair
age-keygen -o ~/.config/age/keystone-admin.txt
# Output: Public key: age1...

# 2. New admin shares public key with existing admin (out-of-band)

# 3. Existing admin adds public key to secrets.nix
# let
#   adminKeys = {
#     alice = "age1...";
#     bob = "age1...";  # New admin
#   };

# 4. Re-encrypt all secrets with new recipient
agenix -r

# 5. Commit and push
git add . && git commit -m "Add admin: bob" && git push
```

**Revoking an admin:**
```bash
# 1. Remove admin's public key from secrets.nix

# 2. Re-encrypt all secrets (revoked admin can no longer decrypt)
agenix -r

# 3. IMPORTANT: Rotate all secrets (revoked admin had previous access)
# Generate new keys for: headscale, k8s CA, etcd encryption, OIDC

# 4. Commit and push
git add . && git commit -m "Revoke admin: eve" && git push

# 5. Redeploy affected services
```

**Primer server key setup:**
```bash
# During installation, primer generates its age identity
age-keygen -o /etc/age/primer.txt

# The public key is added to secrets.nix for all cluster secrets
# At boot, agenix decrypts secrets to /run/agenix/
# Services read secrets from /run/agenix/<secret-name>
```

#### Directory Structure

```
cluster-config/
├── flake.nix
├── configuration.nix
├── secrets.nix              # Age public keys and secret→recipient mappings
└── secrets/
    ├── headscale-private.age
    ├── headscale-noise.age
    ├── headscale-derp.age
    ├── k8s-ca-key.age
    ├── etcd-encryption.age
    └── oidc-signing.age
```

#### Runtime Behavior

- At boot, the agenix NixOS module decrypts secrets to `/run/agenix/`
- Secrets are mounted with restricted permissions (root-only by default)
- Services reference secrets via `config.age.secrets.<name>.path`
- Secrets never touch disk unencrypted (tmpfs-backed `/run`)

#### Additional Security Properties

- All secrets encrypted at rest in git (age encryption)
- Kubernetes secrets use envelope encryption with the etcd encryption key
- etcd data encrypted with AES-GCM
- Regular automatic key rotation recommended for compliance

### Network Security

- All inter-node traffic encrypted (WireGuard via Headscale)
- No unencrypted traffic leaves the cluster
- Network policies enforce pod-to-pod restrictions
- Ingress traffic terminates TLS at edge

### Access Control

- OIDC-based authentication for kubectl and dashboards
- RBAC for all Kubernetes resources
- Audit logging for all API operations
- SSH access via Headscale (no public SSH ports)

## Functional Requirements

### FR-001: Primer Server Bootstrap
The system shall allow a user to bootstrap a Primer Server from a Keystone Base OS installation using the TUI installer.

### FR-002: Offline Secret Storage
The Primer Server shall store all root secrets encrypted with TPM-sealed keys, allowing the server to go offline while the cluster continues to operate.

### FR-003: ZFS Snapshot Automation
The system shall automatically create and manage ZFS snapshots according to a configurable retention policy.

### FR-004: Cloud Provider OIDC
The system shall authenticate to cloud providers using OIDC, eliminating the need for long-lived API credentials.

### FR-005: Kubernetes Node Scheduling
The Kubernetes operator shall provision and manage control plane and worker nodes across bare metal and cloud infrastructure.

### FR-006: Distributed Storage
The system shall provide distributed block, file, and object storage via Ceph/Rook running on ZFS.

### FR-007: Blob Storage Integration
The system shall integrate with cloud blob storage (S3) for backups, object storage, and long-term retention.

### FR-008: Observability Stack
The system shall deploy Grafana, Prometheus, and Loki for monitoring, alerting, and log aggregation.

### FR-009: Secure Networking
All inter-node communication shall be encrypted via WireGuard mesh (Headscale).

### FR-010: Ingress Options
The system shall support both Cloudflare Tunnels and dedicated ingress nodes for external access.

### FR-011: TUI Installation
The system shall provide a terminal-based installer for guided setup of all components.

### FR-012: Air-Gap Capability
The cluster shall continue to operate when the Primer Server is offline, with the ability to restore from encrypted snapshots.

### FR-013: Agenix Secret Management
The system shall use agenix for encrypting and storing cluster secrets in git, with support for multiple admin keys (per-admin revocable) and autonomous primer server decryption. All cluster secrets (Headscale keys, Kubernetes CA, etcd encryption, OIDC signing) shall be encrypted with age and decrypted at boot to `/run/agenix/`.
