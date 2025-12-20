# Research: Observability Stack (Grafana, Kube-Prometheus, Loki + Alloy)

**Feature**: 006-clusters
**Date**: 2024-12-20
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for implementing a comprehensive observability stack in Keystone Clusters. The stack provides metrics collection, visualization, alerting, and log aggregation using Grafana ecosystem tools.

## Research Areas

### 1. Kube-Prometheus-Stack

**Decision**: Use kube-prometheus-stack Helm chart as the foundation

**Rationale**:
- Deploys complete Prometheus + Grafana + Alertmanager stack
- Includes ServiceMonitor and PodMonitor CRDs for auto-discovery
- Pre-configured dashboards for Kubernetes components
- Well-maintained by Prometheus community

**Components Deployed**:
```
kube-prometheus-stack/
├── prometheus-operator       # Manages Prometheus instances
├── prometheus                # Metrics collection and storage
├── alertmanager              # Alert routing and silencing
├── grafana                   # Visualization and dashboards
├── kube-state-metrics        # Kubernetes object metrics
├── node-exporter            # Host-level metrics (DaemonSet)
└── prometheus-adapter       # Metrics API for HPA
```

**Helm Values**:
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ceph-block
          resources:
            requests:
              storage: 50Gi
    # Scrape all ServiceMonitors
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ceph-block
          resources:
            requests:
              storage: 10Gi

grafana:
  persistence:
    enabled: true
    storageClassName: ceph-block
    size: 10Gi
  adminPassword: ${GRAFANA_ADMIN_PASSWORD}
  grafana.ini:
    auth:
      disable_login_form: false
    auth.anonymous:
      enabled: false
```

**Alternatives Considered**:
- **Victoria Metrics**: Better compression, but smaller ecosystem
- **Thanos**: For multi-cluster, overkill for single cluster
- **Mimir**: Grafana's Prometheus alternative, newer/less tested

### 2. Loki Architecture

**Decision**: Deploy Loki in Simple Scalable mode with S3 backend

**Rationale**:
- Handles moderate log volumes (up to 100GB/day)
- Separates read/write paths for better resource utilization
- S3 backend enables long-term retention without local storage
- Simpler than microservices mode, more scalable than monolithic

**Deployment Modes**:

| Mode | Use Case | Complexity | Scale |
|------|----------|------------|-------|
| Monolithic | Dev/small | Low | <10GB/day |
| **Simple Scalable** | Production | Medium | <100GB/day |
| Microservices | Large scale | High | >100GB/day |

**Architecture (Simple Scalable)**:
```
                ┌─────────────────────────────────────┐
                │           Gateway (nginx)           │
                └─────────────┬───────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
    ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
    │  Write Path   │ │  Read Path    │ │   Backend     │
    │  (Ingester)   │ │  (Querier)    │ │  (Compactor)  │
    │  ×3 replicas  │ │  ×2 replicas  │ │  ×1 replica   │
    └───────────────┘ └───────────────┘ └───────────────┘
            │                 │                 │
            └─────────────────┼─────────────────┘
                              ▼
                    ┌─────────────────┐
                    │   Object Store  │
                    │   (S3 / Ceph)   │
                    └─────────────────┘
```

**Helm Values**:
```yaml
loki:
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

  storage:
    type: s3
    s3:
      endpoint: http://rgw.ceph.svc:80
      bucketnames: loki-chunks
      access_key_id: ${LOKI_S3_ACCESS_KEY}
      secret_access_key: ${LOKI_S3_SECRET_KEY}
      s3ForcePathStyle: true

  limits_config:
    retention_period: 90d
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20

deploymentMode: SimpleScalable

backend:
  replicas: 1
read:
  replicas: 2
write:
  replicas: 3
```

### 3. Grafana Alloy vs Promtail

**Decision**: Use Grafana Alloy as the unified collection agent

**Rationale**:
- Alloy is the next-gen replacement for Promtail
- Supports logs, metrics, and traces in one agent
- Component-based configuration (more flexible)
- Better resource utilization than separate agents
- Active development focus from Grafana Labs

**Comparison**:

| Feature | Promtail | Alloy |
|---------|----------|-------|
| Log collection | Yes | Yes |
| Metric collection | No | Yes |
| Trace collection | No | Yes |
| Config format | YAML | River (HCL-like) |
| Pipeline processing | Limited | Extensive |
| Status | Maintenance | Active development |

**Alloy Configuration**:
```river
// Log collection from Kubernetes pods
loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.process.pipeline.receiver]
}

// Log processing pipeline
loki.process "pipeline" {
  stage.json {
    expressions = {
      level = "level",
      msg   = "msg",
    }
  }

  stage.labels {
    values = {
      level = "",
    }
  }

  forward_to = [loki.write.default.receiver]
}

// Send to Loki
loki.write "default" {
  endpoint {
    url = "http://loki-gateway.monitoring.svc:80/loki/api/v1/push"
  }
}

// Also scrape Prometheus metrics
prometheus.scrape "node_exporter" {
  targets = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.default.receiver]
}
```

**Deployment**:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: alloy
spec:
  template:
    spec:
      containers:
        - name: alloy
          image: grafana/alloy:latest
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: containers
              mountPath: /var/lib/docker/containers
              readOnly: true
```

### 4. Dashboard Provisioning

**Decision**: Use Grafana provisioning for dashboards-as-code

**Rationale**:
- Dashboards stored in Git alongside configuration
- Automatic deployment with Helm/ArgoCD
- Version control for dashboard changes
- Reproducible across environments

**Dashboard Sources**:

1. **Built-in** (kube-prometheus-stack):
   - Kubernetes cluster overview
   - Node exporter metrics
   - CoreDNS, etcd, API server

2. **Custom Keystone Dashboards**:
   - ZFS pool health and I/O
   - Ceph cluster status
   - Headscale node connectivity
   - Primer server status

3. **Loki Log Dashboards**:
   - Log volume by namespace
   - Error rate trends
   - Log search interface

**Provisioning ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: keystone-dashboards
  labels:
    grafana_dashboard: "1"
data:
  zfs-health.json: |
    {
      "title": "ZFS Pool Health",
      "panels": [...]
    }
  ceph-overview.json: |
    {
      "title": "Ceph Cluster Overview",
      "panels": [...]
    }
```

### 5. Alert Routing (Alertmanager)

**Decision**: Configure Alertmanager with severity-based routing

**Architecture**:
```
┌─────────────┐     ┌─────────────────┐     ┌───────────────┐
│ Prometheus  │────►│  Alertmanager   │────►│  Receivers    │
│ Alert Rules │     │  (routing tree) │     │ - Slack       │
└─────────────┘     └─────────────────┘     │ - PagerDuty   │
                                            │ - Email       │
                                            │ - Webhook     │
                                            └───────────────┘
```

**Alertmanager Configuration**:
```yaml
global:
  resolve_timeout: 5m
  slack_api_url: ${SLACK_WEBHOOK_URL}

route:
  group_by: ['alertname', 'severity', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true
    - match:
        severity: warning
      receiver: 'slack'
    - match_re:
        alertname: ^(Watchdog|InfoInhibitor)$
      receiver: 'null'

receivers:
  - name: 'null'
  - name: 'default'
    slack_configs:
      - channel: '#alerts'
        send_resolved: true
  - name: 'slack'
    slack_configs:
      - channel: '#alerts-warning'
        send_resolved: true
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: ${PAGERDUTY_KEY}
        severity: critical
```

**Default Alert Rules** (Keystone-specific):

```yaml
groups:
  - name: keystone.rules
    rules:
      # ZFS Pool Health
      - alert: ZFSPoolDegraded
        expr: node_zfs_zpool_state{state!="online"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "ZFS pool {{ $labels.zpool }} is degraded"

      # Ceph Health
      - alert: CephHealthWarning
        expr: ceph_health_status == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Ceph cluster health is WARN"

      # Headscale Connectivity
      - alert: HeadscaleNodeOffline
        expr: headscale_node_online == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Headscale node {{ $labels.hostname }} is offline"

      # Primer Server
      - alert: PrimerServerUnreachable
        expr: up{job="primer"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Primer server is unreachable"
```

### 6. Storage and Retention

**Metrics (Prometheus)**:
- Hot: 15 days local (ceph-block PVC)
- Cold: Optional Thanos sidecar for long-term (S3)
- Estimated storage: ~2GB per day for small cluster

**Logs (Loki)**:
- Hot: 7 days in ingesters
- Cold: 90 days in S3/Ceph RGW
- Estimated storage: ~10GB per day for small cluster

**Retention Configuration**:
```yaml
# Prometheus
prometheus:
  prometheusSpec:
    retention: 15d
    retentionSize: 45GB

# Loki
loki:
  limits_config:
    retention_period: 2160h  # 90 days
  compactor:
    retention_enabled: true
    retention_delete_delay: 2h
```

## Integration Points

### With Ceph/Rook
- Ceph MGR Prometheus module enabled by default
- Rook creates ServiceMonitor for automatic scraping
- Pre-built Ceph dashboards in kube-prometheus-stack

### With ZFS
- node_exporter collects ZFS metrics via sysfs
- Custom ZFS dashboard shows pool health, I/O, capacity

### With Headscale
- Custom metrics exporter for Headscale API
- Node online/offline status monitoring
- Network latency between nodes

### With AWS
- CloudWatch integration via YACE exporter (optional)
- EC2 instance metrics for cloud nodes

## Key Findings Summary

1. **kube-prometheus-stack is the foundation** - batteries included, well-maintained
2. **Loki Simple Scalable for logs** - right balance of simplicity and scale
3. **Alloy over Promtail** - unified agent, future-proof, more capable
4. **Dashboard provisioning** - GitOps for observability config
5. **Severity-based routing** - right alerts to right people
6. **Tiered retention** - hot/cold storage for cost efficiency

## Open Questions Resolved

- **Q**: Should we use Tempo for tracing?
  - **A**: Not in MVP; add later if application tracing is needed

- **Q**: How do we handle multi-tenancy in Loki?
  - **A**: Use Loki's multi-tenancy feature with namespace as tenant ID

- **Q**: What's the resource overhead of the observability stack?
  - **A**: ~2-4GB RAM total for small cluster (Prometheus 1GB, Loki 1GB, Grafana 512MB, Alloy 256MB per node)

- **Q**: Can we use Ceph RGW instead of cloud S3 for Loki?
  - **A**: Yes, Loki supports any S3-compatible storage; configure with s3ForcePathStyle

## Next Steps

1. Create Helm values file for kube-prometheus-stack
2. Create Helm values file for Loki (Simple Scalable mode)
3. Create Alloy DaemonSet configuration
4. Define Keystone-specific PrometheusRules
5. Create custom Grafana dashboards (ZFS, Ceph, Headscale)
6. Configure Alertmanager routing for Slack/PagerDuty
