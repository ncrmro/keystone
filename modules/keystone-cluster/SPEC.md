# Keystone Cluster Module Specification

## Overview

The `keystone-cluster` module provides a NixOS configuration for deploying a Kubernetes control plane host capable of managing cloud-native infrastructure through Kubernetes operators. This enables self-sovereign Kubernetes clusters with autoscaling worker nodes across multiple cloud providers.

## Goals

1. **Self-Sovereign Kubernetes** - Run a Kubernetes control plane on infrastructure you own (local hardware, VPS, or cloud VM)
2. **Cloud Operator Integration** - Leverage Kubernetes operators to provision and manage cloud resources
3. **Autoscaling Node Groups** - Dynamically scale worker nodes based on workload demands
4. **Multi-Cloud Support** - Support AWS, GCP, Azure, and other cloud providers through their respective operators
5. **Cost Optimization** - Use spot/preemptible instances for worker nodes when appropriate

## Architecture

### Deployment Models

#### Model 1: Local Control Plane + Cloud Workers
```
┌─────────────────────────────────────────────────────────────┐
│  Local Network / Home Lab                                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Keystone Cluster Host (NixOS)                          │ │
│  │  ├── K3s/K8s Control Plane                              │ │
│  │  ├── AWS Controllers for Kubernetes (ACK)               │ │
│  │  ├── Crossplane Providers                               │ │
│  │  └── Cluster Autoscaler                                 │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ VPN / WireGuard
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  AWS / Cloud Provider                                        │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  Worker Node 1  │  │  Worker Node 2  │  ... (autoscaled) │
│  │  (EC2 Spot)     │  │  (EC2 Spot)     │                   │
│  └─────────────────┘  └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

#### Model 2: VPS/EC2 Control Plane + Cloud Workers
```
┌─────────────────────────────────────────────────────────────┐
│  VPS Provider (Hetzner, DigitalOcean) or AWS EC2            │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Keystone Cluster Host (NixOS)                          │ │
│  │  ├── K3s/K8s Control Plane                              │ │
│  │  ├── Cloud Operators                                    │ │
│  │  └── Cluster Autoscaler                                 │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Private Network / VPC
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Same or Different Cloud Provider                            │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  Worker Node 1  │  │  Worker Node 2  │  ... (autoscaled) │
│  └─────────────────┘  └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

#### Model 3: Fully Local Cluster
```
┌─────────────────────────────────────────────────────────────┐
│  Local Network / Home Lab                                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Keystone Cluster Host (NixOS)                          │ │
│  │  ├── K3s Control Plane + Worker                         │ │
│  │  ├── Optional: VM-based workers (libvirt)               │ │
│  │  └── Local storage (Longhorn, OpenEBS)                  │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### Kubernetes Distribution
- **Primary**: K3s (lightweight, single-binary, production-ready)
- **Alternative**: K8s via kubeadm (for full Kubernetes compatibility)

### Cloud Operators

#### AWS Controllers for Kubernetes (ACK)
- EC2 instances for worker nodes
- EKS node groups (managed workers)
- S3 for storage
- RDS for managed databases
- IAM roles and policies

#### Crossplane
- Multi-cloud resource provisioning
- Composition of cloud resources as Kubernetes CRDs
- Provider support: AWS, GCP, Azure, Kubernetes

#### Karpenter (AWS-specific)
- Just-in-time node provisioning
- Spot instance management
- Bin-packing optimization
- Consolidation and drift detection

### Autoscaling Components

#### Cluster Autoscaler
- Watches for pending pods
- Triggers cloud provider APIs to add/remove nodes
- Supports multiple cloud providers

#### Vertical Pod Autoscaler (VPA)
- Right-sizes pod resource requests
- Reduces over-provisioning

#### Horizontal Pod Autoscaler (HPA)
- Scales deployments based on metrics
- Built into Kubernetes

### Networking

#### CNI Options
- **Cilium** (default) - eBPF-based, network policies, observability
- **Flannel** - Simple overlay network (K3s default)
- **Calico** - Network policies, BGP support

#### Ingress
- **Traefik** (K3s default)
- **NGINX Ingress Controller**
- **Cilium Ingress**

#### Service Mesh (Optional)
- **Cilium Service Mesh**
- **Linkerd** - Lightweight, easy to operate
- **Istio** - Full-featured, complex

### Storage

#### Cloud Storage
- AWS EBS CSI Driver
- AWS EFS CSI Driver
- Cloud provider block/file storage

#### Local Storage
- **Longhorn** - Distributed block storage
- **OpenEBS** - Container-attached storage
- **Local Path Provisioner** (K3s default)

## Configuration Interface

```nix
{
  keystone.cluster = {
    enable = true;

    # Kubernetes distribution
    distribution = "k3s"; # or "kubeadm"

    # Role: control-plane, worker, or both
    role = "control-plane"; # or "worker" or "control-plane+worker"

    # Cluster networking
    networking = {
      cni = "cilium"; # or "flannel", "calico"
      podCidr = "10.42.0.0/16";
      serviceCidr = "10.43.0.0/16";
      clusterDomain = "cluster.local";
    };

    # Cloud provider integration
    cloudProviders = {
      aws = {
        enable = true;
        region = "us-west-2";
        # Credentials via IRSA, instance profile, or secrets
        credentialsSource = "instance-profile";
      };
    };

    # Operators to deploy
    operators = {
      ack = {
        enable = true;
        controllers = ["ec2" "s3" "rds" "iam"];
      };
      crossplane = {
        enable = false;
        providers = ["aws" "kubernetes"];
      };
      karpenter = {
        enable = true;
        defaultNodePool = {
          instanceTypes = ["t3.medium" "t3.large" "t3a.medium"];
          capacityTypes = ["spot" "on-demand"];
          zones = ["us-west-2a" "us-west-2b"];
        };
      };
    };

    # Autoscaling configuration
    autoscaling = {
      clusterAutoscaler = {
        enable = true;
        minNodes = 1;
        maxNodes = 10;
      };
    };

    # Storage configuration
    storage = {
      defaultClass = "ebs-gp3"; # or "local-path", "longhorn"
      ebsCSI.enable = true;
      longhorn.enable = false;
    };

    # Observability
    observability = {
      prometheus.enable = true;
      grafana.enable = true;
      loki.enable = true;
    };
  };
}
```

## Security Considerations

### Control Plane Security
- TLS for all Kubernetes API communication
- RBAC enabled by default
- Pod Security Standards enforcement
- Network policies restricting control plane access

### Cloud Credentials
- **Preferred**: IAM Roles for Service Accounts (IRSA) on AWS
- **Alternative**: Instance profiles for EC2-hosted control planes
- **Fallback**: Kubernetes secrets (encrypted at rest)

### Node Security
- Minimal OS images for workers (Bottlerocket, Talos)
- Node restriction admission controller
- Kubelet certificate rotation

### Network Security
- Encrypted pod-to-pod traffic (WireGuard via Cilium)
- Network policies by default
- Private cluster endpoints where possible

## Implementation Phases

### Phase 1: Core K3s Module
- [ ] K3s server installation and configuration
- [ ] Basic networking (Flannel/Cilium)
- [ ] Local storage provisioner
- [ ] Kubectl and admin tooling

### Phase 2: AWS Integration
- [ ] AWS credential management
- [ ] ACK EC2 controller
- [ ] EBS CSI driver
- [ ] Basic node group provisioning

### Phase 3: Autoscaling
- [ ] Karpenter deployment
- [ ] Node pool configuration
- [ ] Spot instance support
- [ ] Cluster autoscaler (non-AWS clouds)

### Phase 4: Multi-Cloud
- [ ] Crossplane integration
- [ ] GCP provider
- [ ] Azure provider
- [ ] Hetzner provider

### Phase 5: Advanced Features
- [ ] Service mesh options
- [ ] GitOps integration (Flux/ArgoCD)
- [ ] Backup and disaster recovery
- [ ] Multi-cluster federation

## Dependencies

### NixOS Packages Required
- `k3s` or `kubernetes` (kubeadm)
- `kubectl`
- `helm`
- `cilium-cli` (optional)
- `kustomize`
- `aws-cli` (for AWS integration)

### External Dependencies
- Cloud provider account(s) with appropriate permissions
- DNS for cluster access (optional but recommended)
- Container registry access

## Related Keystone Modules

- **`keystone.vpn`** - Secure connectivity between control plane and workers
- **`keystone.server`** - Base server configuration
- **`keystone.ssh`** - SSH access to control plane
- **`keystone.disko`** - Disk configuration for control plane host

## References

- [K3s Documentation](https://docs.k3s.io/)
- [AWS Controllers for Kubernetes](https://aws-controllers-k8s.github.io/community/)
- [Crossplane](https://crossplane.io/)
- [Karpenter](https://karpenter.sh/)
- [Cilium](https://cilium.io/)
- [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
