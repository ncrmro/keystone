# Feature Specification: Cross-Realm Workloads

**Feature Branch**: `xyz-001-ha-cross-realm-workloads`
**Created**: 2025-12-13
**Status**: Draft

## Overview

Cross-realm workloads enable distinct entities (individuals, families, business partners, open-source communities) to share compute and storage resources across trust boundaries. A **realm** represents a distinct identity boundary - a person, household, organization, or community that owns and controls their own Keystone infrastructure.

Entities can **grant** resources to other realms, allowing workloads to run on infrastructure they don't directly own. These grants are managed via Kubernetes Custom Resource Definitions (CRDs) with controllers that reconcile state across clusters.

## Core Concepts

### Realms and Entities

- **Realm**: A trust boundary owned by a single identity (person, organization)
- **Entity**: The owner of a realm - can be an individual, family, business, or community
- **Super Entity**: A shared ownership structure owned by multiple entities (e.g., a family backup pool, a business partnership's shared infrastructure)

### Grants (Kubernetes CRD)

Grants define what resources one entity allows another to consume. Grants are Kubernetes Custom Resource Definitions (CRDs) managed by operators:
- **Declarative**: Defined as Kubernetes custom resources
- **Revocable**: Grantor can delete or modify at any time
- **Scoped**: Define specific resource limits (CPU, memory, storage, bandwidth)
- **Directional**: A grants to B does not imply B grants to A
- **Controller-managed**: Kubernetes operators reconcile grant state across clusters

### Network Policy Model

Grants control network egress:
- **No outbound by default**: If grant doesn't explicitly allow, workload can only communicate back to the requesting entity
- **Explicit egress grants**: Grantor can allow specific outbound destinations
- **Ingress always allowed**: From the entity that requested the workload

### Distributed Storage

- **Ceph**: For distributed storage networks across realms (shared pools)
- **ZFS**: For block storage and verified backup networks
- **Super Entity Backups**: Distributed, verified backup copies across multiple entity-owned nodes

## User Scenarios

### User Story 1 - Create a Grant for Another Entity (Priority: P1)

An entity (Alice) wants to allow another entity (Bob) to run workloads on her infrastructure. She creates a grant specifying resource limits and network policies.

**Acceptance Scenarios**:

1. **Given** Alice has a Keystone cluster, **When** she creates a grant for Bob's realm, **Then** the grant specifies CPU, memory, storage limits and network policy
2. **Given** a grant exists, **When** Bob's realm connects, **Then** Bob can deploy workloads up to the granted limits
3. **Given** a grant with no egress allowed, **When** Bob's workload runs, **Then** it can only communicate back to Bob's realm

---

### User Story 2 - Accept and Use a Grant (Priority: P1)

Bob receives a grant from Alice and connects his Keystone cluster to use her resources.

**Acceptance Scenarios**:

1. **Given** Bob has Alice's grant token/domain, **When** he registers it in his TUI, **Then** Alice's realm appears as available for workload placement
2. **Given** Bob deploys a workload targeting Alice's realm, **When** scheduled, **Then** it runs on Alice's infrastructure within granted limits
3. **Given** Bob exceeds granted limits, **When** deploying, **Then** deployment is rejected with clear resource violation message

---

### User Story 3 - Form a Super Entity (Priority: P2)

Alice and Bob create a shared super entity for family backups. Both contribute storage, and the super entity manages distributed backups.

**Acceptance Scenarios**:

1. **Given** Alice and Bob agree to form a super entity, **When** both approve via TUI, **Then** a super entity is created with shared ownership
2. **Given** a super entity exists, **When** either party contributes storage, **Then** it joins the distributed backup pool
3. **Given** backup data exists, **When** verified, **Then** copies exist across multiple entity-owned nodes

---

### User Story 4 - Revoke a Grant (Priority: P2)

Alice decides to revoke Bob's access to her resources.

**Acceptance Scenarios**:

1. **Given** an active grant exists, **When** Alice revokes it, **Then** the controller reconciles the revocation across clusters
2. **Given** workloads are running under a revoked grant, **When** revocation propagates, **Then** workloads are gracefully terminated with notice period
3. **Given** revocation is complete, **When** Bob attempts new deployments, **Then** they are rejected

---

### User Story 5 - Distributed Backup Verification (Priority: P3)

A super entity verifies that backups are properly distributed and intact across member nodes.

**Acceptance Scenarios**:

1. **Given** a super entity with backup data, **When** verification runs, **Then** each member node confirms data integrity
2. **Given** a backup copy is missing or corrupt, **When** detected, **Then** re-replication occurs from healthy copies
3. **Given** verification completes, **When** viewing status, **Then** shows backup health across all member realms

## Requirements

### Functional Requirements

- **FR-001**: System MUST support realm registration with unique identity
- **FR-002**: System MUST implement grants as Kubernetes Custom Resource Definitions (CRDs)
- **FR-003**: Grants MUST specify: CPU limits, memory limits, storage limits, bandwidth limits, network egress policy
- **FR-004**: System MUST enforce grant limits on workload scheduling
- **FR-005**: System MUST default to no-egress network policy (ingress only from requesting entity)
- **FR-006**: System MUST support super entity formation with multi-party ownership
- **FR-007**: System MUST integrate with Tailscale/Headscale for cross-realm networking
- **FR-008**: System MUST support Ceph for distributed storage pools
- **FR-009**: System MUST support ZFS for block storage backups
- **FR-010**: System MUST verify backup distribution for super entities
- **FR-011**: Grant revocation MUST propagate via Kubernetes controller reconciliation
- **FR-012**: System MUST provide workload migration when grants change

### Key Entities

- **Realm**: Identity boundary with unique identifier, owns infrastructure
- **Entity**: Owner of a realm (individual, org, community)
- **Super Entity**: Multi-owner structure (shared by multiple entities)
- **Grant**: Kubernetes CRD specifying resource allocation from grantor to grantee
- **Workload**: Deployable unit that consumes granted resources
- **Storage Pool**: Ceph or ZFS pool contributed by one or more realms

### Grant CRD Schema (High-Level)

Following the Kubernetes ResourceQuota pattern:

```yaml
apiVersion: keystone.io/v1alpha1
kind: Grant
metadata:
  name: alice-to-bob-compute
  namespace: keystone-system
spec:
  grantorRealm: alice-home
  granteeRealm: bob-home
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    requests.storage: "100Gi"
    requests.nvidia.com/gpu: 1
  networkPolicy:
    egressAllowed: false
    allowedDestinations: []  # Only if egressAllowed: true
  validity:
    validFrom: "2025-01-01T00:00:00Z"
    validUntil: "2026-01-01T00:00:00Z"  # Optional
status:
  phase: Active  # Pending | Active | Revoked | Expired
  used:
    requests.cpu: "1"
    requests.memory: "2Gi"
    limits.cpu: "2"
    limits.memory: "4Gi"
    requests.storage: "25Gi"
```

## Technologies

- **Orchestration**: Kubernetes (k3s for lightweight deployments)
- **Resource Management**: Kubernetes CRDs with custom controllers/operators
- **Identity/Networking**: Tailscale/Headscale for cross-realm mesh
- **Container Runtime**: containerd (via Kubernetes)
- **Distributed Storage**: Ceph for shared pools, ZFS for backups
- **TUI Client**: Rust with ratatui

## Success Criteria

- **SC-001**: Two distinct entities can establish a grant and run workloads within 10 minutes
- **SC-002**: Grant revocation propagates and terminates workloads within 5 minutes
- **SC-003**: Super entity backups maintain 3+ verified copies across member realms
- **SC-004**: Network policy enforcement prevents unauthorized egress 100% of the time

## Assumptions

- All participating realms run Keystone on NixOS
- Cross-realm networking established via Tailscale/Headscale
- Entities have established out-of-band trust before grant creation
- Each realm has at least one node with sufficient resources
