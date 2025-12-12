# Keystone Cluster Module

Deploy a self-sovereign Kubernetes control plane on bare metal or VPS with cloud operator integration for autoscaling worker nodes.

## Overview

Run your own Kubernetes control plane on hardware you control, then use Kubernetes operators to provision cloud resources (worker nodes, storage, databases) on-demand.

**Why?**
- Avoid managed Kubernetes control plane fees (~$70/month for EKS/GKE)
- Full control over your cluster configuration
- Run control plane on cheap hardware (home server, $5 VPS)
- Scale workers in the cloud only when needed

## Quick Start

```nix
{
  keystone.cluster = {
    enable = true;
    distribution = "k3s";
    role = "control-plane+worker";
  };
}
```

## Documentation

| Document | Description |
|----------|-------------|
| [SPEC.md](./SPEC.md) | Full technical specification |
| [Getting Started](./docs/getting-started.md) | Deployment options (bare metal vs VPS) |
| [AWS Integration](./docs/aws.md) | OIDC setup, IAM roles, Karpenter |
| [Autoscaling](./docs/autoscaling.md) | Node autoscaling with cloud providers |

## Architecture

```
┌─────────────────────────────────┐
│  Your Hardware / VPS            │
│  ├── K3s Control Plane          │
│  ├── Cloud Operators (ACK)      │
│  └── Cluster Autoscaler         │
└─────────────────────────────────┘
              │
              ▼ OIDC Authentication
┌─────────────────────────────────┐
│  Cloud Provider (AWS/GCP/etc)   │
│  └── Autoscaled Worker Nodes    │
└─────────────────────────────────┘
```

## Requirements

- NixOS host (bare metal or VPS)
- Cloud provider account (for cloud workers)
- Public endpoint for OIDC discovery (S3 bucket or web server)
