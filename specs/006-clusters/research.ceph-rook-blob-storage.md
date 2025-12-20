# Research: Ceph/Rook + Blob Storage Integration

**Feature**: 006-clusters
**Date**: 2024-12-20
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for implementing distributed storage in Keystone Clusters using Ceph managed by the Rook operator, running on top of ZFS, with integration to cloud blob storage for offsite backup and object storage.

## Research Areas

### 1. Rook Operator Deployment Patterns

**Decision**: Deploy Rook operator with Ceph as the storage backend

**Rationale**:
- Rook is the CNCF graduated project for cloud-native storage
- Manages Ceph lifecycle entirely within Kubernetes
- Provides storage classes for block, filesystem, and object storage
- Handles Ceph upgrades, scaling, and self-healing

**Deployment Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│  ┌─────────────────────────────────────────────────┐    │
│  │              Rook Operator                       │    │
│  │  - Watches CephCluster CRD                       │    │
│  │  - Manages OSD, MON, MGR pods                   │    │
│  └─────────────────────────────────────────────────┘    │
│                          │                               │
│  ┌───────────────────────▼───────────────────────────┐  │
│  │              CephCluster                          │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐           │  │
│  │  │  MON×3  │  │  MGR×2  │  │  MDS×2  │           │  │
│  │  └─────────┘  └─────────┘  └─────────┘           │  │
│  │  ┌─────────────────────────────────────────────┐ │  │
│  │  │              OSDs (on ZFS datasets)          │ │  │
│  │  │  Node1: OSD.0, OSD.1   Node2: OSD.2, OSD.3  │ │  │
│  │  └─────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Alternatives Considered**:
- **Longhorn**: Simpler but less mature, no object storage
- **OpenEBS**: Multiple engines, more complexity
- **Portworx**: Commercial, expensive for self-hosted
- **MinIO**: Object storage only, no block storage

### 2. Ceph on ZFS Considerations

**Decision**: Use ZFS datasets as OSD backing store with filestore mode

**Rationale**:
- Leverage ZFS checksums and self-healing alongside Ceph replication
- ZFS snapshots provide instant local backups before Ceph operations
- ZFS compression reduces disk usage (LZ4 fast enough for real-time)
- Existing Keystone infrastructure already uses ZFS

**Configuration**:
```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
spec:
  storage:
    useAllNodes: true
    useAllDevices: false
    deviceFilter: "^zd[0-9]+$"  # ZFS zvols
    config:
      storeType: bluestore
      osdsPerDevice: "1"
```

**ZFS Dataset Layout**:
```bash
# Per-node ZFS structure
rpool/ceph/
├── osd.0/     # Dataset for OSD 0 (mounted as directory)
├── osd.1/     # Dataset for OSD 1
└── journal/   # Shared WAL/DB on fast storage (optional)
```

**Important Considerations**:
- **Don't use zvols for OSDs** - use directories on ZFS datasets instead
- Ceph BlueStore on raw ZFS datasets provides best performance
- Disable ZFS sync for Ceph datasets (Ceph handles consistency)
- Set `recordsize=64K` to match Ceph object size

**ZFS Settings for Ceph**:
```bash
zfs create -o mountpoint=/var/lib/ceph/osd/ceph-0 \
           -o compression=lz4 \
           -o atime=off \
           -o recordsize=64K \
           -o sync=disabled \
           rpool/ceph/osd.0
```

### 3. Storage Classes

**Decision**: Provide three storage classes for different workload types

**Block Storage (RBD)**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
```

**Use Cases**: Databases (PostgreSQL, MySQL), stateful applications, high-performance workloads

**Filesystem Storage (CephFS)**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-filesystem
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: cephfs
  pool: cephfs-data0
reclaimPolicy: Delete
allowVolumeExpansion: true
```

**Use Cases**: Shared storage (ReadWriteMany), content management, build artifacts

**Object Storage (RGW)**:
```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: my-store
spec:
  metadataPool:
    replicated:
      size: 3
  dataPool:
    replicated:
      size: 3
  gateway:
    type: s3
    port: 80
    instances: 2
```

**Use Cases**: Backups, logs, container registry, static assets

### 4. S3-Compatible Storage via RGW

**Decision**: Deploy Ceph RADOS Gateway for S3-compatible object storage

**Rationale**:
- Drop-in replacement for AWS S3 APIs
- Applications using AWS SDK work without modification
- Supports bucket policies, versioning, lifecycle rules
- Can federate with cloud S3 for hybrid storage

**RGW Configuration**:
```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: keystone-s3
spec:
  metadataPool:
    replicated:
      size: 3
  dataPool:
    erasureCoded:
      dataChunks: 2
      codingChunks: 1
  preservePoolsOnDelete: true
  gateway:
    type: s3
    sslCertificateRef: rgw-tls
    port: 443
    securePort: 443
    instances: 2
    resources:
      limits:
        cpu: "2"
        memory: 4Gi
```

**User/Bucket Management**:
```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: backup-user
spec:
  store: keystone-s3
  displayName: "Backup Service"
  capabilities:
    bucket: "*"
    user: "read"
```

### 5. Cloud Blob Storage Integration

**Decision**: Integrate with AWS S3 for offsite backup and tiering

**Use Cases**:
1. **ZFS Snapshot Offsite Backup**: Send ZFS snapshots to S3 for disaster recovery
2. **Ceph RGW Cloud Sync**: Replicate objects to cloud S3
3. **Log/Metrics Archival**: Move old data to cheaper cloud storage

**ZFS to S3 Backup**:
```bash
# Incremental ZFS snapshot to S3
zfs send -i @yesterday rpool/data@today | \
  zstd -T0 | \
  aws s3 cp - s3://keystone-backup/zfs/data-$(date +%Y%m%d).zst
```

**Ceph Cloud Sync**:
```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectZoneGroup
metadata:
  name: keystone
spec:
  realm: keystone
  master: true
  zones:
    - name: local
      endpoints:
        - http://rgw-local:80
    - name: aws
      endpoints:
        - https://s3.us-west-2.amazonaws.com
      cloudProvider: aws
```

**Lifecycle Policies**:
```json
{
  "Rules": [{
    "ID": "ArchiveOldLogs",
    "Status": "Enabled",
    "Filter": {"Prefix": "logs/"},
    "Transitions": [{
      "Days": 30,
      "StorageClass": "GLACIER"
    }],
    "Expiration": {"Days": 365}
  }]
}
```

### 6. Performance Considerations

**Network**:
- Ceph requires 10Gbps+ for production workloads
- Separate cluster network for OSD traffic recommended
- Use jumbo frames (MTU 9000) if possible

**Memory**:
- OSDs: 4GB RAM per OSD minimum (8GB recommended)
- MONs: 4GB RAM per monitor
- RGW: 4GB RAM per gateway instance

**Disk**:
- NVMe for BlueStore WAL/DB (or use ZFS SLOG)
- SSD minimum for OSDs; HDD acceptable for cold storage
- 3+ OSDs per node for resilience

**Tuning for ZFS Backend**:
```bash
# Ceph OSD tuning
[osd]
osd_memory_target = 4294967296
bluestore_cache_size = 3221225472

# Disable Ceph scrubbing during business hours
osd_scrub_begin_hour = 22
osd_scrub_end_hour = 6
```

### 7. Disaster Recovery

**Ceph Native**:
- 3-way replication across failure domains (nodes, racks)
- Automatic rebalancing on node failure
- Built-in scrubbing detects and repairs bit rot

**ZFS Layer**:
- Instant snapshots before risky operations
- ZFS send/receive to remote site
- Checksums catch silent corruption

**Cloud Backup**:
- RGW sync to cloud S3 for geo-redundancy
- ZFS snapshots archived to S3 Glacier
- Recovery time: minutes (local), hours (cloud)

## Integration Points

### With AWS OIDC
- RGW uses S3 API; can share OIDC credentials with AWS
- Cloud sync uses IRSA for AWS authentication

### With Observability
- Ceph MGR Prometheus module exports metrics
- Rook creates ServiceMonitor for Prometheus Operator
- Pre-built Grafana dashboards for Ceph health

### With ZFS Snapshots
- ZFS snapshots complement Ceph replication
- Can recover from Ceph corruption using ZFS rollback
- Snapshot before Ceph upgrades as safety net

## Key Findings Summary

1. **Rook + Ceph is production-ready** - CNCF graduated, widely deployed
2. **ZFS as OSD backing works** - use directories, not zvols
3. **Three storage classes cover most use cases** - block, filesystem, object
4. **RGW provides S3 compatibility** - drop-in for AWS SDK applications
5. **Cloud sync enables hybrid storage** - local + cloud without application changes
6. **Performance requires planning** - network, memory, disk considerations

## Open Questions Resolved

- **Q**: Can Ceph run on ZFS without issues?
  - **A**: Yes, use ZFS datasets (directories), not zvols; disable ZFS sync for Ceph datasets

- **Q**: How does replication interact with ZFS checksums?
  - **A**: Both layers provide integrity checks; ZFS catches local corruption, Ceph replicates across nodes

- **Q**: What's the minimum cluster size for Ceph?
  - **A**: 3 nodes minimum for production (MON quorum); can run on single node for development

- **Q**: Can we use cloud S3 as a Ceph backend?
  - **A**: Not directly; RGW can sync to cloud S3, but local storage is required for primary

## Next Steps

1. Define ZFS dataset layout for Ceph OSDs in disko module
2. Create Helm values for Rook operator deployment
3. Define StorageClass resources for each storage type
4. Configure RGW for S3 compatibility
5. Set up cloud sync to AWS S3
6. Create Grafana dashboards for Ceph monitoring
