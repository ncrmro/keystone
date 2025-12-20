# Research: Headscale Networking for Keystone Clusters

**Feature**: 006-clusters
**Date**: 2024-12-20
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for implementing secure inter-node networking in Keystone Clusters using Headscale, the open-source Tailscale control plane. Headscale enables WireGuard-based mesh networking without relying on Tailscale's commercial infrastructure.

## Research Areas

### 1. Headscale vs Tailscale Control Plane

**Decision**: Use Headscale as self-hosted control plane

**Rationale**:
- Complete control over network infrastructure
- No external dependencies for cluster operation
- No per-seat licensing costs
- Data sovereignty - all traffic routing decisions stay local
- Primer Server can host Headscale directly

**Comparison**:

| Feature | Tailscale | Headscale |
|---------|-----------|-----------|
| Control Plane | SaaS (tailscale.com) | Self-hosted |
| Pricing | Free tier, then per-seat | Free (open source) |
| Data Privacy | Keys transit Tailscale | Fully self-contained |
| DERP Relays | Global network | Self-hosted or public |
| OIDC Support | Yes (SSO) | Yes (configurable) |
| ACL Format | HuJSON | HuJSON (compatible) |
| Stability | Production | Production-ready |

**Alternatives Considered**:
- **Nebula**: Lighter weight but less ecosystem support
- **ZeroTier**: Similar to Tailscale but less Kubernetes-native
- **WireGuard Direct**: Manual key distribution, no mesh management
- **Tailscale Funnel**: Commercial dependency, costs at scale

### 2. Access Pattern Architecture

**Decision**: Two distinct access patterns - Machine Access and Cluster Access

This is critical for Keystone's security model. Users need both:
1. **Machine Access**: SSH to individual nodes for maintenance
2. **Cluster Access**: kubectl to Kubernetes API for workload management

**Architecture**:
```
                    ┌─────────────────────────────────────────┐
                    │              Headscale                  │
                    │         (on Primer Server)              │
                    └─────────────────────────────────────────┘
                                      │
            ┌─────────────────────────┼─────────────────────────┐
            │                         │                         │
            ▼                         ▼                         ▼
    ┌───────────────┐       ┌───────────────┐         ┌───────────────┐
    │  User Laptop  │       │  Primer Node  │         │  Worker Node  │
    │  (tailscale)  │       │  (tailscale)  │         │  (tailscale)  │
    │               │       │               │         │               │
    │  - kubectl    │       │  - k8s API    │         │  - kubelet    │
    │  - ssh admin  │       │  - SSH        │         │  - SSH        │
    └───────────────┘       └───────────────┘         └───────────────┘
```

#### Machine Access Pattern

**Use Case**: System administration, debugging, maintenance

**Flow**:
```
User Laptop ──[Headscale mesh]──► Node (SSH on port 22)
```

**Configuration**:
```yaml
# Headscale ACL for machine access
{
  "groups": {
    "group:admins": ["user1@example.com", "user2@example.com"],
    "group:machines": ["tag:keystone-node"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["group:machines:22"]  # SSH only
    }
  ]
}
```

**Benefits**:
- Direct SSH access to any cluster node
- No jump hosts or bastion required
- Works through NAT/firewalls
- Audit trail via Headscale logs

#### Cluster Access Pattern

**Use Case**: Kubernetes API access for deployments, monitoring

**Flow**:
```
User Laptop ──[Headscale mesh]──► Primer/API Server (port 6443)
       └── kubectl configured with Headscale IP ──┘
```

**Configuration**:
```yaml
# kubeconfig using Headscale IP
apiVersion: v1
kind: Config
clusters:
  - cluster:
      server: https://primer.keystone.local:6443
      certificate-authority-data: <ca-cert>
    name: keystone-cluster
contexts:
  - context:
      cluster: keystone-cluster
      user: admin
    name: keystone
users:
  - name: admin
    user:
      client-certificate-data: <client-cert>
      client-key-data: <client-key>
```

**ACL for Cluster Access**:
```yaml
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:primer:6443"]  # Kubernetes API
    },
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:primer:443"]   # Grafana, ArgoCD, etc.
    }
  ]
}
```

### 3. ACL Configuration Patterns

**Decision**: Use role-based ACLs with granular service access

**ACL Structure**:
```json
{
  "groups": {
    "group:cluster-admins": ["admin@keystone.local"],
    "group:developers": ["dev1@example.com", "dev2@example.com"],
    "group:monitoring": ["prometheus@keystone.local"]
  },

  "tagOwners": {
    "tag:primer": ["group:cluster-admins"],
    "tag:worker": ["group:cluster-admins"],
    "tag:storage": ["group:cluster-admins"]
  },

  "acls": [
    // Cluster admins - full access
    {
      "action": "accept",
      "src": ["group:cluster-admins"],
      "dst": ["*:*"]
    },

    // Developers - API and SSH only
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": [
        "tag:primer:6443",     // Kubernetes API
        "tag:primer:443",      // Ingress services
        "tag:worker:22",       // SSH for debugging
        "tag:primer:22"
      ]
    },

    // Inter-node communication
    {
      "action": "accept",
      "src": ["tag:primer", "tag:worker"],
      "dst": ["tag:primer:*", "tag:worker:*"]
    },

    // Monitoring access
    {
      "action": "accept",
      "src": ["group:monitoring"],
      "dst": [
        "tag:worker:9100",     // Node exporter
        "tag:worker:10250",    // Kubelet metrics
        "tag:primer:9090"      // Prometheus
      ]
    }
  ],

  "ssh": [
    {
      "action": "accept",
      "src": ["group:cluster-admins"],
      "dst": ["tag:primer", "tag:worker"],
      "users": ["root", "admin"]
    },
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": ["tag:worker"],
      "users": ["debug"]  // Limited user for debugging
    }
  ]
}
```

### 4. DERP Relay Setup

**Decision**: Deploy private DERP relay on Primer, fall back to public relays

**Rationale**:
- Private DERP ensures traffic stays within trusted infrastructure
- Public DERP fallback handles edge cases (mismatched NAT types)
- Lower latency when DERP is colocated with cluster

**DERP Architecture**:
```
                    ┌─────────────────────────────────────┐
                    │       Private DERP (Primer)         │
                    │       derp.keystone.local:443       │
                    └─────────────────────────────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
         ▼                          ▼                          ▼
    ┌─────────┐               ┌─────────┐               ┌─────────┐
    │ Node A  │◄─────────────►│ Node B  │◄─────────────►│ Node C  │
    │ (NAT)   │  Direct P2P   │ (NAT)   │  Via DERP     │ (cloud) │
    └─────────┘               └─────────┘               └─────────┘
```

**DERP Configuration** (on Primer):
```yaml
# /etc/derp/derp.yaml
privateKeyPath: /var/lib/derp/private.key
derp:
  hostname: derp.keystone.local
  certMode: manual  # Use existing TLS cert
  certDir: /etc/derp/certs
  stun: true
  stunPort: 3478
  httpPort: -1  # Disable HTTP
  httpsPort: 443
```

**Headscale DERP Map**:
```yaml
# headscale config
derp:
  server:
    enabled: true
    region_id: 900
    region_code: "keystone"
    region_name: "Keystone Private"
    stun_listen_addr: "0.0.0.0:3478"

  urls: []  # Don't use Tailscale public DERP

  paths:
    - /etc/headscale/derp.yaml

  auto_update_enabled: false
  update_frequency: 24h
```

**Custom DERP Map** (/etc/headscale/derp.yaml):
```json
{
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "keystone",
      "RegionName": "Keystone Private",
      "Nodes": [{
        "Name": "primer-derp",
        "RegionID": 900,
        "HostName": "derp.keystone.local",
        "STUNPort": 3478,
        "DERPPort": 443
      }]
    },
    "1": {
      "RegionID": 1,
      "RegionCode": "nyc",
      "RegionName": "New York (Fallback)",
      "Nodes": [{
        "Name": "1a",
        "RegionID": 1,
        "HostName": "derp1.tailscale.com"
      }]
    }
  }
}
```

### 5. Node Registration Workflow

**Decision**: Use pre-auth keys with machine-specific tags

**Flow**:
```
1. Primer generates pre-auth key for new node
2. Node boots with cloud-init containing pre-auth key
3. Tailscale client registers with Headscale
4. Node receives Headscale IP and mesh configuration
5. Node becomes accessible via mesh network
```

**Pre-Auth Key Generation**:
```bash
# Generate reusable key for worker nodes
headscale preauthkeys create \
  --user keystone \
  --reusable \
  --expiration 24h \
  --tags tag:worker

# Generate single-use key for specific node
headscale preauthkeys create \
  --user keystone \
  --expiration 1h \
  --tags tag:primer
```

**Cloud-Init Integration**:
```yaml
#cloud-config
write_files:
  - path: /etc/tailscale/auth-key
    content: ${HEADSCALE_AUTH_KEY}
    permissions: '0600'

runcmd:
  - tailscale up --login-server=https://headscale.keystone.local \
      --authkey=$(cat /etc/tailscale/auth-key) \
      --hostname=$(hostname) \
      --accept-routes \
      --accept-dns=false
```

**NixOS Module**:
```nix
{ config, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraUpFlags = [
      "--login-server=https://headscale.keystone.local"
      "--accept-routes"
      "--accept-dns=false"
    ];
  };

  # Pre-auth key provided via activation script
  system.activationScripts.tailscale-auth = ''
    if [ -f /etc/tailscale/auth-key ]; then
      ${pkgs.tailscale}/bin/tailscale up \
        --authkey=$(cat /etc/tailscale/auth-key) \
        --reset
      rm /etc/tailscale/auth-key
    fi
  '';
}
```

### 6. Kubernetes CNI Integration

**Decision**: Use Tailscale as overlay network for cross-node pod communication

**Options**:

| Approach | Complexity | Performance | Use Case |
|----------|------------|-------------|----------|
| **Flannel + Headscale underlay** | Low | Good | Default recommendation |
| Tailscale Kubernetes Operator | Medium | Good | Full mesh pods |
| Cilium + Headscale | High | Best | Advanced networking |

**Flannel Configuration** (using Headscale IPs):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
data:
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "wireguard",
        "PSK": "${FLANNEL_PSK}"
      }
    }
```

**Node Configuration**:
```bash
# Each node advertises its Headscale IP as internal IP
kubelet --node-ip=$(tailscale ip -4)
```

**Pod-to-Pod Flow**:
```
Pod A (Node 1) ──► Flannel (vxlan) ──► Headscale (WireGuard) ──► Node 2 ──► Pod B
        └── 10.244.1.x                  100.64.x.x                  10.244.2.x ──┘
```

### 7. DNS Configuration

**Decision**: Use Headscale MagicDNS with custom domain

**Configuration**:
```yaml
# Headscale config
dns_config:
  override_local_dns: false
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  domains: []
  magic_dns: true
  base_domain: keystone.local
```

**Resulting DNS Names**:
```
primer.keystone.local        → 100.64.0.1
worker-1.keystone.local      → 100.64.0.2
worker-2.keystone.local      → 100.64.0.3
```

**Kubernetes CoreDNS Integration**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
        }
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
    keystone.local:53 {
        forward . 100.64.0.1  # Headscale DNS
        cache 30
    }
```

### 8. High Availability Considerations

**Single Primer**:
- Headscale runs on Primer server
- If Primer fails, existing connections persist (mesh is established)
- New nodes cannot join until Primer recovers
- Suitable for small/medium clusters

**Multi-Primer (Future)**:
```
┌─────────────────────────────────────────────────────────────┐
│                    Headscale HA Cluster                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Primer 1   │  │  Primer 2   │  │  Primer 3   │         │
│  │  (active)   │  │  (standby)  │  │  (standby)  │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│         └────────────────┼────────────────┘                 │
│                          │                                  │
│                    ┌─────▼─────┐                           │
│                    │  PostgreSQL│                           │
│                    │  (shared)  │                           │
│                    └───────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

**HA Requirements**:
- Shared PostgreSQL database for Headscale state
- Load balancer for Headscale API
- Each Primer can run DERP relay
- Nodes configured with multiple control plane endpoints

## Integration Points

### With AWS/Cloud Nodes
- Cloud nodes register with Headscale using pre-auth keys
- Security groups allow WireGuard UDP (41641) and DERP HTTPS (443)
- STUN port (3478/UDP) for NAT traversal

### With Observability
- Headscale exposes Prometheus metrics at `/metrics`
- Grafana dashboard for connection status, latency, throughput
- Alert on node disconnection

### With ZFS/Storage
- Storage traffic flows over Headscale mesh (encrypted)
- Ceph OSD traffic uses Headscale IPs for cluster network

### With Cloudflare Tunnel
- Headscale OIDC login can be exposed via Cloudflare Tunnel
- Admin UI accessible without direct mesh access

## Key Findings Summary

1. **Headscale enables self-sovereign networking** - no external dependencies
2. **Two access patterns are essential** - machine (SSH) and cluster (kubectl)
3. **ACLs provide granular access control** - role-based, service-specific
4. **Private DERP improves performance** - traffic stays within infrastructure
5. **Pre-auth keys simplify node onboarding** - integrate with cloud-init
6. **Flannel + Headscale underlay is simplest** - standard CNI over mesh

## Open Questions Resolved

- **Q**: How do new nodes discover the Headscale server?
  - **A**: DNS name baked into cloud-init, or IP passed via pre-auth key metadata

- **Q**: What happens if Headscale goes down?
  - **A**: Existing mesh connections persist; new registrations fail until recovery

- **Q**: Can we use Tailscale clients with Headscale?
  - **A**: Yes, standard Tailscale client works with `--login-server` flag

- **Q**: How do we rotate pre-auth keys?
  - **A**: Generate new keys before expiry; existing nodes unaffected

## Next Steps

1. Deploy Headscale on Primer server NixOS configuration
2. Create ACL template for Keystone clusters
3. Configure DERP relay on Primer
4. Integrate node registration into cloud-init templates
5. Test machine access (SSH) and cluster access (kubectl) patterns
6. Create Grafana dashboard for Headscale metrics
