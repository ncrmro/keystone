# Research: Cloudflare Tunnel for Keystone Ingress

**Feature**: 006-clusters
**Date**: 2024-12-20
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for implementing ingress to Keystone Clusters using Cloudflare Tunnel. The goal is to expose cluster services to the internet without opening inbound firewall ports or requiring public IP addresses.

## Research Areas

### 1. Cloudflare Tunnel Architecture

**Decision**: Use cloudflared daemon as Kubernetes Deployment with Ingress controller integration

**Rationale**:
- No inbound ports required - all connections outbound to Cloudflare
- DDoS protection included at no extra cost
- TLS termination handled by Cloudflare
- Works behind NAT, CGNAT, or restrictive firewalls
- Zero-trust access policies available

**Architecture**:
```
                          ┌──────────────────────┐
                          │   Cloudflare Edge    │
Internet ─────────────────►   (DDoS protection)  │
                          │   (TLS termination)  │
                          └──────────┬───────────┘
                                     │
                          ┌──────────▼───────────┐
                          │  Cloudflare Tunnel   │
                          │  (encrypted tunnel)  │
                          └──────────┬───────────┘
                                     │
    ┌────────────────────────────────┼────────────────────────────────┐
    │                     Kubernetes Cluster                          │
    │  ┌─────────────────────────────▼─────────────────────────────┐ │
    │  │              cloudflared Deployment                        │ │
    │  │              (2+ replicas for HA)                         │ │
    │  └─────────────────────────────┬─────────────────────────────┘ │
    │                                │                                │
    │         ┌──────────────────────┼──────────────────────┐        │
    │         ▼                      ▼                      ▼        │
    │  ┌─────────────┐      ┌─────────────┐       ┌─────────────┐   │
    │  │  Grafana    │      │   ArgoCD    │       │  App Service│   │
    │  │  :3000      │      │   :443      │       │  :8080      │   │
    │  └─────────────┘      └─────────────┘       └─────────────┘   │
    └─────────────────────────────────────────────────────────────────┘
```

**Alternatives Considered**:
- **Nginx Ingress + LoadBalancer**: Requires public IP and open ports
- **Traefik**: Same issue as Nginx, needs inbound access
- **Tailscale Funnel**: Limited features, commercial dependency
- **Dedicated Ingress Nodes**: More complexity, still needs public IP (see section 7)

### 2. cloudflared Deployment Patterns

**Decision**: Deploy cloudflared as Kubernetes Deployment with ConfigMap-based ingress rules

**Deployment Options**:

| Pattern | Use Case | Complexity | Flexibility |
|---------|----------|------------|-------------|
| Standalone binary | Single service | Low | Low |
| **Deployment + ConfigMap** | Multi-service | Medium | High |
| Ingress Controller | Native K8s integration | High | Highest |

**Kubernetes Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          args:
            - tunnel
            - --config
            - /etc/cloudflared/config.yaml
            - run
          volumeMounts:
            - name: config
              mountPath: /etc/cloudflared
              readOnly: true
            - name: credentials
              mountPath: /etc/cloudflared/credentials
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /ready
              port: 2000
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: config
          configMap:
            name: cloudflared-config
        - name: credentials
          secret:
            secretName: cloudflared-credentials
```

**ConfigMap for Tunnel Configuration**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflare-system
data:
  config.yaml: |
    tunnel: keystone-cluster
    credentials-file: /etc/cloudflared/credentials/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true

    ingress:
      # Grafana
      - hostname: grafana.keystone.example.com
        service: http://grafana.monitoring.svc:3000
        originRequest:
          noTLSVerify: true

      # ArgoCD
      - hostname: argocd.keystone.example.com
        service: https://argocd-server.argocd.svc:443
        originRequest:
          noTLSVerify: true

      # Kubernetes Dashboard
      - hostname: dashboard.keystone.example.com
        service: https://kubernetes-dashboard.kubernetes-dashboard.svc:443

      # Catch-all (required)
      - service: http_status:404
```

### 3. Tunnel Creation and Credentials

**Decision**: Create tunnel via CLI, store credentials in Kubernetes Secret

**Tunnel Setup**:
```bash
# Login to Cloudflare (one-time, stores credentials locally)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create keystone-cluster

# This creates:
# ~/.cloudflared/<tunnel-id>.json  (credentials file)

# Create Kubernetes secret from credentials
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=/path/to/<tunnel-id>.json \
  -n cloudflare-system

# Configure DNS (creates CNAME to tunnel)
cloudflared tunnel route dns keystone-cluster grafana.keystone.example.com
cloudflared tunnel route dns keystone-cluster argocd.keystone.example.com
```

**Credentials Secret Structure**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-credentials
  namespace: cloudflare-system
type: Opaque
data:
  credentials.json: <base64-encoded-credentials>
```

### 4. Zero-Trust Access Policies

**Decision**: Use Cloudflare Access for authentication on sensitive services

**Rationale**:
- Additional authentication layer before traffic reaches cluster
- SSO integration (Google, GitHub, OIDC)
- Audit logging for all access
- Per-service access policies

**Access Policy Configuration** (via Cloudflare Dashboard or API):
```json
{
  "name": "Keystone Admin Access",
  "decision": "allow",
  "include": [
    {
      "email": {
        "email": "admin@example.com"
      }
    },
    {
      "email_domain": {
        "domain": "keystone.example.com"
      }
    }
  ],
  "require": [
    {
      "login_method": ["github"]
    }
  ]
}
```

**Service-Specific Policies**:

| Service | Access Policy | Authentication |
|---------|---------------|----------------|
| Grafana | Team members | GitHub SSO |
| ArgoCD | DevOps only | GitHub SSO + 2FA |
| Dashboard | Admins only | OIDC (Primer) |
| Public API | Public | None (app handles auth) |

**Tunnel Configuration with Access**:
```yaml
ingress:
  - hostname: grafana.keystone.example.com
    service: http://grafana.monitoring.svc:3000
    originRequest:
      noTLSVerify: true
      access:
        required: true
        teamName: keystone
        audTag: ["grafana-audit"]
```

### 5. Ingress Controller Integration

**Decision**: Use cloudflare-ingress-controller for native Kubernetes integration (optional)

**Rationale**:
- Standard Kubernetes Ingress resources
- Automatic DNS record management
- Declarative configuration
- GitOps-friendly

**Ingress Controller Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflare-ingress-controller
  namespace: cloudflare-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cloudflare-ingress
  template:
    spec:
      containers:
        - name: controller
          image: cloudflare/cloudflare-ingress-controller:latest
          args:
            - --tunnel-id=$(TUNNEL_ID)
            - --credentials-file=/etc/cloudflared/credentials.json
            - --ingress-class=cloudflare
          env:
            - name: TUNNEL_ID
              valueFrom:
                secretKeyRef:
                  name: cloudflared-credentials
                  key: tunnel-id
```

**Ingress Resource Example**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    kubernetes.io/ingress.class: cloudflare
    cloudflare.com/access-policy: team-access
spec:
  rules:
    - host: grafana.keystone.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

### 6. High Availability and Failover

**Decision**: Run multiple cloudflared replicas with pod anti-affinity

**HA Configuration**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
spec:
  replicas: 2
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: cloudflared
                topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: cloudflared
```

**Connection Pooling**:
```yaml
# config.yaml
tunnel: keystone-cluster
originRequest:
  connectTimeout: 30s
  tlsTimeout: 10s
  tcpKeepAlive: 30s
  noHappyEyeballs: false
  keepAliveConnections: 100
  keepAliveTimeout: 90s
```

### 7. Alternative: Dedicated Ingress Nodes

**When to Consider**:
- Need for custom TLS certificates (not Cloudflare-managed)
- Compliance requirements for traffic not transiting third-party
- Performance-sensitive applications (direct path)
- Cloudflare outage resilience

**Architecture**:
```
                    ┌─────────────────────────────────┐
                    │        Cloud Provider LB         │
Internet ───────────►     (AWS ALB/NLB, GCP LB)       │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────▼─────────────────┐
                    │       Ingress Node Pool         │
                    │  ┌─────────┐    ┌─────────┐    │
                    │  │ nginx-1 │    │ nginx-2 │    │
                    │  └────┬────┘    └────┬────┘    │
                    └───────┼──────────────┼─────────┘
                            │              │
                            └──────┬───────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │       Kubernetes Services        │
                    └─────────────────────────────────┘
```

**Ingress Node Configuration**:
```yaml
apiVersion: keystone.systems/v1alpha1
kind: NodePool
metadata:
  name: ingress
spec:
  provider: aws
  instanceType: t3.medium
  minNodes: 2
  maxNodes: 4
  taints:
    - key: node-role.kubernetes.io/ingress
      effect: NoSchedule
  labels:
    node-role.kubernetes.io/ingress: ""
```

**Nginx Ingress with NodeSelector**:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nginx-ingress
spec:
  selector:
    matchLabels:
      app: nginx-ingress
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/ingress: ""
      tolerations:
        - key: node-role.kubernetes.io/ingress
          effect: NoSchedule
```

**Hybrid Approach** (Recommended):
- Use Cloudflare Tunnel for most services (simplicity, DDoS protection)
- Use dedicated ingress nodes for specific high-performance or compliance needs
- Both can coexist in the same cluster

### 8. Monitoring and Observability

**Metrics Endpoint**:
```yaml
# cloudflared exposes Prometheus metrics
config.yaml: |
  metrics: 0.0.0.0:2000
```

**ServiceMonitor**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cloudflared
spec:
  selector:
    matchLabels:
      app: cloudflared
  endpoints:
    - port: metrics
      interval: 30s
```

**Key Metrics**:
- `cloudflared_tunnel_total_requests` - Request count by hostname
- `cloudflared_tunnel_request_errors` - Error count
- `cloudflared_tunnel_response_by_code` - HTTP status codes
- `cloudflared_tunnel_connection_latency_ms` - Tunnel latency

**Grafana Dashboard Panels**:
```json
{
  "panels": [
    {
      "title": "Tunnel Requests/sec",
      "targets": [{
        "expr": "rate(cloudflared_tunnel_total_requests[5m])"
      }]
    },
    {
      "title": "Error Rate",
      "targets": [{
        "expr": "rate(cloudflared_tunnel_request_errors[5m]) / rate(cloudflared_tunnel_total_requests[5m])"
      }]
    },
    {
      "title": "P99 Latency",
      "targets": [{
        "expr": "histogram_quantile(0.99, cloudflared_tunnel_connection_latency_ms_bucket)"
      }]
    }
  ]
}
```

### 9. Security Considerations

**Tunnel Security**:
- All traffic encrypted end-to-end (Cloudflare edge to origin)
- Tunnel credentials should be treated as secrets
- Rotate tunnel credentials periodically
- Use Cloudflare Access for sensitive services

**Network Policy**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cloudflared-egress
  namespace: cloudflare-system
spec:
  podSelector:
    matchLabels:
      app: cloudflared
  policyTypes:
    - Egress
  egress:
    # Allow outbound to Cloudflare
    - to: []
      ports:
        - port: 443
          protocol: TCP
        - port: 7844
          protocol: TCP
    # Allow access to cluster services
    - to:
        - namespaceSelector: {}
```

**Origin Server Protection**:
```yaml
# Only accept traffic from cloudflared
ingress:
  - hostname: api.keystone.example.com
    service: http://api-service.default.svc:8080
    originRequest:
      httpHostHeader: api.keystone.example.com
      originServerName: api-service.default.svc
```

## Integration Points

### With Headscale
- Cloudflare Tunnel and Headscale serve different purposes
- Cloudflare: Public internet ingress
- Headscale: Private mesh for admin/operator access
- Both can expose same services (different audiences)

### With Observability
- cloudflared metrics scraped by Prometheus
- Grafana dashboards for tunnel health
- Alerts on tunnel disconnection or high error rates

### With OIDC
- Cloudflare Access can use Primer's OIDC provider
- SSO for all exposed services
- Centralized authentication and audit logging

### With AWS/Cloud
- Tunnels work from any network (cloud VPC, on-prem, home)
- No VPC peering or transit gateway needed for ingress
- Cloud nodes can run cloudflared replicas

## Key Findings Summary

1. **Cloudflare Tunnel is ideal for zero-trust ingress** - no open ports needed
2. **Deployment + ConfigMap pattern** - simple, declarative, GitOps-friendly
3. **Cloudflare Access adds authentication layer** - SSO before traffic hits cluster
4. **Multiple replicas for HA** - pod anti-affinity ensures resilience
5. **Dedicated ingress nodes are optional** - use for specific compliance/performance needs
6. **Metrics integration** - full observability with Prometheus/Grafana

## Open Questions Resolved

- **Q**: Can Cloudflare Tunnel work with custom domains?
  - **A**: Yes, add domain to Cloudflare account and create DNS records

- **Q**: What's the latency overhead of Cloudflare Tunnel?
  - **A**: Typically 10-50ms depending on Cloudflare edge proximity; negligible for most use cases

- **Q**: How do we handle tunnel credential rotation?
  - **A**: Create new tunnel, update Secret, rolling restart of cloudflared pods

- **Q**: Can we use Cloudflare Tunnel for non-HTTP traffic?
  - **A**: Yes, supports TCP/UDP with `cloudflared access tcp` or Spectrum (paid feature)

## Next Steps

1. Create cloudflared Kubernetes manifests (Deployment, ConfigMap, Secret)
2. Document tunnel creation and DNS setup process
3. Configure Cloudflare Access policies for sensitive services
4. Create ServiceMonitor and Grafana dashboard for tunnel metrics
5. Test failover with multiple replicas
6. Document hybrid approach with dedicated ingress nodes
