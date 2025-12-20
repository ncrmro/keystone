# Tasks: Keystone Clusters (006-clusters)

## Story Map

```
                                    Keystone Clusters
                                          │
    ┌─────────────┬────────────┬──────────┼──────────┬────────────┬─────────────┐
    │             │            │          │          │            │             │
 Spike        Phase 1      Phase 2    Phase 3    Phase 4      Phase 5      Phase 6
 Primer      Networking    Cloud      Storage   Observ.      Ingress       TUI
    │             │            │          │          │            │             │
 ┌──┴──┐     ┌────┴────┐   ┌───┴───┐  ┌───┴───┐  ┌───┴───┐   ┌───┴───┐    ┌───┴───┐
 │Boot │     │Headscale│   │ OIDC  │  │ Rook  │  │Prom.  │   │Tunnel │    │Wizard │
 │ZFS  │     │ ACLs    │   │ AWS   │  │ Ceph  │  │Grafana│   │Access │    │Install│
 │etcd │     │ DERP    │   │ Op    │  │ RGW   │  │Loki   │   │       │    │       │
 └─────┘     └─────────┘   └───────┘  └───────┘  └───────┘   └───────┘    └───────┘
```

---

## Phase 0: Spike - Primer Server Bootstrap

**Goal**: Validate core bootstrap process with encrypted ZFS, etcd, and basic Kubernetes

**Time Box**: 2 weeks

### Epic: Bootable Primer Image

#### 0.1 Create Primer NixOS Configuration
- [ ] Create `modules/cluster/primer/default.nix` module structure
- [ ] Configure single-node etcd with systemd service
- [ ] Add k3s or kubeadm control plane configuration
- [ ] Enable automatic ZFS import on boot

#### 0.2 Integrate with Existing Disko Module
- [ ] Verify encrypted ZFS works with cluster workloads
- [ ] Configure etcd data directory on ZFS dataset
- [ ] Set up Kubernetes state directories (`/var/lib/kubernetes`, `/var/lib/etcd`)

#### [P] 0.3 Build Test Image
- [ ] Create qcow2 image for VM testing
- [ ] Configure `bin/virtual-machine` for primer testing
- [ ] Document manual installation steps for USB boot

### Epic: Cluster Credentials

#### 0.4 CA and Certificate Generation
- [ ] Implement cluster CA generation (stored on encrypted ZFS)
- [ ] Generate etcd peer certificates
- [ ] Generate Kubernetes API server certificates
- [ ] Generate admin kubeconfig

#### 0.5 Initial Secrets Storage
- [ ] Create credstore pattern for cluster secrets
- [ ] Integrate with existing Keystone credstore module
- [ ] Document secret rotation process

### Epic: Basic Kubernetes

#### 0.6 etcd Single-Node Setup
- [ ] Configure etcd systemd service
- [ ] Set up etcd client authentication
- [ ] Verify data persistence across reboots

#### 0.7 Kubernetes Control Plane
- [ ] Deploy k3s server or kubeadm control plane
- [ ] Configure API server with cluster CA
- [ ] Verify kubectl access from Primer node

### Spike Success Criteria
- [ ] Primer boots from qcow2 with encrypted ZFS
- [ ] etcd running and healthy (`etcdctl endpoint health`)
- [ ] kubectl works against local API server
- [ ] Credentials survive reboot

---

## Phase 1: Networking Foundation

**Goal**: Establish secure mesh networking with Headscale

**Depends on**: Phase 0 (Spike)

### Epic: Headscale Deployment

#### 1.1 Headscale NixOS Module
- [ ] Create `modules/cluster/primer/headscale.nix`
- [ ] Configure Headscale with PostgreSQL/SQLite backend
- [ ] Set up HTTPS with Let's Encrypt or self-signed cert
- [ ] Enable metrics endpoint

#### 1.2 ACL Configuration
- [ ] Define initial ACL structure (cluster-admins, developers)
- [ ] Configure machine vs cluster access patterns
- [ ] Document ACL update process

#### [P] 1.3 DERP Relay Setup
- [ ] Deploy DERP relay on Primer
- [ ] Configure custom DERP map
- [ ] Test NAT traversal scenarios

### Epic: Node Registration

#### 1.4 Pre-Auth Key Management
- [ ] Implement pre-auth key generation for new nodes
- [ ] Create API endpoint for key creation (protected)
- [ ] Document node onboarding process

#### 1.5 Worker Node Tailscale Integration
- [ ] Create `modules/cluster/worker/tailscale.nix`
- [ ] Configure automatic registration on boot
- [ ] Test cloud-init integration pattern

### Epic: Access Patterns

#### 1.6 Machine Access (SSH)
- [ ] Verify SSH over Headscale mesh
- [ ] Configure SSH host keys distribution
- [ ] Document SSH access workflow

#### 1.7 Cluster Access (kubectl)
- [ ] Generate kubeconfig with Headscale IPs
- [ ] Test API server access over mesh
- [ ] Document kubectl setup for developers

### Phase 1 Success Criteria
- [ ] Headscale running on Primer with valid ACLs
- [ ] At least one worker node registered via Headscale
- [ ] SSH works to all nodes via Headscale
- [ ] kubectl works via Headscale network

---

## Phase 2: Cloud Provider Integration

**Goal**: Enable AWS node provisioning via OIDC

**Depends on**: Phase 1 (Networking)

### Epic: OIDC Provider

#### 2.1 OIDC Issuer Implementation
- [ ] Create `modules/cluster/primer/oidc-provider.nix`
- [ ] Implement `/.well-known/openid-configuration` endpoint
- [ ] Implement `/keys` JWKS endpoint
- [ ] Generate and manage signing keys

#### 2.2 Token Issuance
- [ ] Configure Kubernetes service account token projection
- [ ] Set correct audience for AWS STS
- [ ] Test token validation flow

### Epic: AWS Integration

#### 2.3 IAM Configuration
- [ ] Create Terraform/Pulumi for IAM OIDC provider
- [ ] Define IAM role with trust policy
- [ ] Configure least-privilege EC2 permissions

#### [P] 2.4 Test OIDC Flow
- [ ] Verify token validation with AWS STS
- [ ] Test AssumeRoleWithWebIdentity
- [ ] Document troubleshooting steps

### Epic: Node Pool Operator

#### 2.5 Operator Scaffolding
- [ ] Initialize kubebuilder project in `operators/keystone-operator/`
- [ ] Define NodePool CRD schema
- [ ] Generate controller scaffolding

#### 2.6 EC2 Provisioning Logic
- [ ] Implement Launch Template creation
- [ ] Implement instance provisioning
- [ ] Handle Auto Scaling Group integration

#### 2.7 Node Lifecycle Management
- [ ] Implement node health monitoring
- [ ] Handle spot instance interruption
- [ ] Implement scaling operations

### Epic: Cloud-Init Bootstrap

#### 2.8 Bootstrap Script Generation
- [ ] Create cloud-init template with Headscale registration
- [ ] Include NixOS configuration deployment
- [ ] Handle credential injection (pre-auth keys, etc.)

#### [P] 2.9 Test Cloud Node Join
- [ ] Provision test EC2 instance
- [ ] Verify Headscale registration
- [ ] Verify kubelet join

### Phase 2 Success Criteria
- [ ] OIDC provider endpoints working
- [ ] NodePool CRD creates EC2 instances
- [ ] EC2 instances auto-join cluster via Headscale
- [ ] No long-lived AWS credentials stored in cluster

---

## Phase 3: Storage Layer

**Goal**: Distributed storage with Rook/Ceph and cloud backup

**Depends on**: Phase 1 (Networking)

### Epic: Rook/Ceph Deployment

#### 3.1 Rook Operator Installation
- [ ] Create Helm values for Rook operator
- [ ] Deploy to monitoring namespace
- [ ] Verify CRD installation

#### 3.2 CephCluster Configuration
- [ ] Configure CephCluster CRD for ZFS backing
- [ ] Set up MON, MGR, MDS pods
- [ ] Configure OSD discovery for ZFS datasets

#### 3.3 ZFS OSD Backend
- [ ] Create ZFS dataset layout for Ceph OSDs
- [ ] Configure BlueStore on ZFS directories
- [ ] Tune ZFS settings per research doc

### Epic: Storage Classes

#### 3.4 Block Storage (RBD)
- [ ] Create ceph-block StorageClass
- [ ] Test PVC creation and binding
- [ ] Verify pod volume attachment

#### [P] 3.5 Filesystem Storage (CephFS)
- [ ] Deploy MDS for CephFS
- [ ] Create ceph-filesystem StorageClass
- [ ] Test ReadWriteMany access

#### [P] 3.6 Object Storage (RGW)
- [ ] Deploy RGW pods
- [ ] Create CephObjectStore CRD
- [ ] Configure S3 user and bucket creation

### Epic: Backup Integration

#### 3.7 ZFS Snapshot Automation
- [ ] Create systemd timer for periodic snapshots
- [ ] Implement snapshot rotation policy
- [ ] Document restore process

#### 3.8 Cloud Sync to S3
- [ ] Configure RGW cloud sync to AWS S3
- [ ] Set up lifecycle policies for archival
- [ ] Test disaster recovery flow

### Phase 3 Success Criteria
- [ ] Ceph cluster healthy with 3+ OSDs
- [ ] All three StorageClasses working
- [ ] RGW accessible with S3-compatible API
- [ ] Snapshots being taken and synced to cloud

---

## Phase 4: Observability

**Goal**: Full monitoring and logging stack

**Depends on**: Phase 3 (Storage for persistence)

### Epic: Prometheus Stack

#### 4.1 kube-prometheus-stack Deployment
- [ ] Create Helm values for kube-prometheus-stack
- [ ] Configure Prometheus retention and storage
- [ ] Enable ServiceMonitor discovery

#### 4.2 Alertmanager Configuration
- [ ] Configure severity-based routing
- [ ] Set up Slack/PagerDuty receivers
- [ ] Create initial alert rules

### Epic: Loki Logging

#### 4.3 Loki Simple Scalable Deployment
- [ ] Create Helm values for Loki
- [ ] Configure S3 backend via RGW
- [ ] Set retention policies

#### 4.4 Alloy Log Collection
- [ ] Deploy Alloy DaemonSet
- [ ] Configure log pipeline processing
- [ ] Add Kubernetes metadata enrichment

### Epic: Grafana Dashboards

#### [P] 4.5 Custom Keystone Dashboards
- [ ] Create ZFS pool health dashboard
- [ ] Create Ceph cluster overview dashboard
- [ ] Create Headscale status dashboard

#### 4.6 Dashboard Provisioning
- [ ] Configure Grafana dashboard provisioning
- [ ] Add dashboards to Git
- [ ] Test automatic deployment

### Epic: ServiceMonitors

#### 4.7 Component Monitoring
- [ ] Create ServiceMonitor for Headscale
- [ ] Create ServiceMonitor for etcd
- [ ] Create ServiceMonitor for Ceph

### Phase 4 Success Criteria
- [ ] Prometheus scraping all cluster components
- [ ] Grafana accessible with custom dashboards
- [ ] Loki collecting logs from all pods
- [ ] Alertmanager routing alerts to configured channels

---

## Phase 5: Ingress

**Goal**: Zero-trust public access via Cloudflare Tunnel

**Depends on**: Phase 4 (for Grafana, ArgoCD exposure)

### Epic: Cloudflare Tunnel

#### 5.1 Tunnel Setup
- [ ] Create Cloudflare tunnel via CLI
- [ ] Store credentials in Kubernetes Secret
- [ ] Configure DNS records

#### 5.2 cloudflared Deployment
- [ ] Create Deployment manifest for cloudflared
- [ ] Configure ingress rules ConfigMap
- [ ] Enable HA with multiple replicas

#### [P] 5.3 Cloudflare Access
- [ ] Configure Access application for Grafana
- [ ] Set up GitHub SSO integration
- [ ] Create access policies per service

### Epic: Ingress Configuration

#### 5.4 Service Exposure
- [ ] Expose Grafana via tunnel
- [ ] Expose ArgoCD via tunnel
- [ ] Document adding new services

#### 5.5 Monitoring Integration
- [ ] Create ServiceMonitor for cloudflared
- [ ] Add tunnel health dashboard
- [ ] Configure alerts for tunnel disconnection

### Phase 5 Success Criteria
- [ ] Grafana accessible via public URL
- [ ] Cloudflare Access enforcing authentication
- [ ] Multiple cloudflared replicas for HA
- [ ] Tunnel metrics visible in Prometheus

---

## Phase 6: TUI Installer

**Goal**: User-friendly installation experience

**Depends on**: All previous phases (installer configures everything)

### Epic: Go TUI Framework

#### 6.1 Project Setup
- [ ] Initialize Go module in `modules/iso-installer/tui/`
- [ ] Add Bubbletea and Bubbles dependencies
- [ ] Create basic application scaffold

#### 6.2 Wizard Framework
- [ ] Implement multi-step wizard state machine
- [ ] Create step navigation (next/back/quit)
- [ ] Add validation between steps

### Epic: Hardware Detection

#### 6.3 System Detection
- [ ] Implement CPU detection
- [ ] Implement memory detection
- [ ] Implement TPM2 detection
- [ ] Detect Secure Boot status

#### 6.4 Disk Detection
- [ ] Enumerate available disks via lsblk
- [ ] Detect disk type (NVMe, SSD, HDD)
- [ ] Calculate usable space

### Epic: Installation Steps

#### 6.5 Disk Configuration Step
- [ ] Create disk selection UI
- [ ] Add partition preview
- [ ] Support multiple disk layouts

#### 6.6 Encryption Step
- [ ] Create encryption method selection
- [ ] Add password strength meter
- [ ] Support TPM2 auto-unlock toggle

#### 6.7 Network Configuration Step
- [ ] Detect network interfaces
- [ ] Support DHCP and static IP
- [ ] Configure hostname

#### 6.8 Cluster Configuration Step
- [ ] Input cluster name
- [ ] Configure initial admin user
- [ ] Generate cluster credentials

### Epic: NixOS Integration

#### 6.9 Configuration Generation
- [ ] Generate hardware-configuration.nix
- [ ] Generate disko-config.nix
- [ ] Generate main configuration.nix

#### 6.10 Installation Execution
- [ ] Run disko for partitioning
- [ ] Execute nixos-install
- [ ] Handle errors with recovery options

### Epic: Testing

#### [P] 6.11 qcow2 Test Workflow
- [ ] Create automated VM testing script
- [ ] Implement keystroke injection for TUI
- [ ] Add assertions for successful installation

#### 6.12 Hardware Testing
- [ ] Test on 3+ different hardware configs
- [ ] Document supported hardware
- [ ] Create compatibility matrix

### Phase 6 Success Criteria
- [ ] TUI installer runs from ISO
- [ ] All wizard steps navigable
- [ ] NixOS installs successfully
- [ ] Post-install, system boots with Primer services

---

## Cross-Cutting Concerns

### Documentation
- [ ] User guide for Primer installation
- [ ] Developer guide for extending operators
- [ ] Troubleshooting guide for common issues
- [ ] Architecture decision records

### Testing
- [ ] Unit tests for Go operators
- [ ] Integration tests for each phase
- [ ] End-to-end test for full cluster setup
- [ ] Performance benchmarks for storage

### CI/CD
- [ ] GitHub Actions for operator builds
- [ ] Automated ISO builds
- [ ] Nix flake checks
- [ ] Container image publishing

---

## Legend

- `[ ]` - Not started
- `[x]` - Complete
- `[P]` - Can be done in parallel with previous task
- **Epic** - Group of related tasks
- **Phase** - Milestone with deliverable

## Notes

- Tasks marked `[P]` can be parallelized to speed up development
- Each phase has explicit success criteria before moving forward
- Spike (Phase 0) is time-boxed to validate approach before full implementation
- Cloud provider integration (Phase 2) is optional for on-prem only deployments
