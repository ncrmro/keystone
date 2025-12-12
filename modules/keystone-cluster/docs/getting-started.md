# Getting Started

## Deployment Options

### Option A: Bare Metal / Home Server

Best for home labs, always-on workloads, and data sovereignty.

```nix
{
  keystone.cluster = {
    enable = true;
    role = "control-plane+worker";  # Run workloads locally too
  };

  keystone.vpn.enable = true;  # WireGuard for cloud connectivity
  networking.firewall.allowedTCPPorts = [6443];  # K8s API
}
```

**Pros**: No monthly costs, full control, can run local workloads
**Cons**: Requires home network setup, may need dynamic DNS

### Option B: VPS Node

Best for reliable uptime and static IP without home network complexity.

| Provider | Cheapest Option | Notes |
|----------|-----------------|-------|
| Hetzner | €3.79/mo (CX22) | Best value, EU datacenters |
| DigitalOcean | $6/mo | Simple setup |
| Vultr | $5/mo | Many locations |
| AWS EC2 | ~$8/mo (t3.micro) | Stay in AWS ecosystem |

```nix
{
  keystone.cluster = {
    enable = true;
    role = "control-plane";  # Workers will be in the cloud
  };
}
```

## Deployment

### New Machine

```bash
nixos-anywhere --flake .#my-cluster root@<ip-address>
```

### Existing NixOS Machine

```bash
nixos-rebuild switch --flake .#my-cluster
```

## Accessing Your Cluster

```bash
ssh root@<ip-address>
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

## Next Steps

- [AWS Integration](./aws.md) - Set up OIDC and cloud operators
- [Autoscaling](./autoscaling.md) - Configure worker node autoscaling
