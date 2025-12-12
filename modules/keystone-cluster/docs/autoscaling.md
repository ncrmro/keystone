# Autoscaling

## Overview

Autoscaling allows your cluster to dynamically adjust capacity based on workload demands. There are three levels:

| Level | What Scales | Tool |
|-------|-------------|------|
| **Pod** | Number of pod replicas | HPA (built-in) |
| **Resource** | Pod CPU/memory requests | VPA |
| **Node** | Worker nodes in cluster | Karpenter / Cluster Autoscaler |

## Node Autoscaling

### Karpenter (AWS)

Karpenter is a just-in-time node provisioner that:
- Watches for pending pods
- Provisions right-sized nodes immediately
- Supports spot instances (60-90% cost savings)
- Consolidates underutilized nodes

```nix
{
  keystone.cluster.operators.karpenter = {
    enable = true;
    defaultNodePool = {
      instanceTypes = ["t3.medium" "t3.large" "m5.large"];
      capacityTypes = ["spot" "on-demand"];
      zones = ["us-west-2a" "us-west-2b"];
    };
  };
}
```

**NodePool Example** (Kubernetes manifest):

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large", "m5.large"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 100
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
```

### Cluster Autoscaler (Multi-Cloud)

For non-AWS clouds or managed node groups:

```nix
{
  keystone.cluster.autoscaling.clusterAutoscaler = {
    enable = true;
    minNodes = 1;
    maxNodes = 10;
  };
}
```

## Pod Autoscaling

### Horizontal Pod Autoscaler (HPA)

Scales pod replicas based on metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### Vertical Pod Autoscaler (VPA)

Adjusts pod resource requests automatically:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: Auto
```

## Cost Optimization

### Spot Instances

Configure Karpenter to prefer spot instances:

```yaml
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["spot"]  # Spot only
    # values: ["spot", "on-demand"]  # Spot preferred, on-demand fallback
```

**Spot Savings by Instance Type**:
| Type | On-Demand | Spot (typical) | Savings |
|------|-----------|----------------|---------|
| t3.medium | $0.0416/hr | $0.0125/hr | ~70% |
| m5.large | $0.096/hr | $0.035/hr | ~64% |

### Consolidation

Karpenter can consolidate underutilized nodes:

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 1m
```

### Scale to Zero

For dev/test clusters, scale workers to zero when idle:

```nix
{
  keystone.cluster.autoscaling = {
    scaleToZero = true;
    idleTimeout = "30m";
  };
}
```

## Monitoring

Key metrics to watch:
- `karpenter_nodes_total` - Current node count
- `karpenter_pods_state` - Pending vs scheduled pods
- `cluster_autoscaler_unschedulable_pods_count`

```nix
{
  keystone.cluster.observability = {
    prometheus.enable = true;
    grafana.enable = true;
  };
}
```
