# Feature Specification: Multi-VM Headscale Connectivity Testing

**Feature Branch**: `001-multi-vm-headscale`
**Created**: 2025-11-09
**Status**: Draft
**Input**: User description: "Test three local vms can all connect via headscale service. This allows us to have a network/dns distributed across networks ontop ofh encrypted wireguard connections"

## Clarifications

### Session 2025-11-09

- Q: Where should the Headscale control server run for these tests? → A: Dedicated VM - One of the test VMs is designated as the Headscale server
- Q: How should VMs authenticate when registering with the Headscale server? → A: Pre-authentication keys only - Automated token-based registration
- Q: Which web server should be used for testing service binding to the mesh interface (User Story 3)? → A: nginx
- Q: What logging and observability mechanism should be used to validate test success? → A: Journald + headscale CLI - Use systemd logs and headscale status commands
- Q: How should the test suite handle edge case failures (e.g., duplicate hostnames, server unavailable)? → A: Stop on first failure - Halt testing immediately when any edge case fails

## User Scenarios & Testing

### User Story 1 - Basic Mesh Network Connectivity (Priority: P1)

As a system administrator, I need to verify that three virtual machines can establish a mesh network through a coordination service, so that I can validate the basic connectivity infrastructure before deploying to production environments.

**Why this priority**: This is the foundational capability - without basic mesh connectivity, none of the advanced features (DNS, cross-network routing) can function. This represents the minimum viable test that proves the coordination service is operational.

**Independent Test**: Can be fully tested by deploying three VMs with mesh networking clients, connecting them to a coordination server, and verifying bidirectional connectivity between any two nodes. Delivers immediate value by confirming the mesh is established correctly.

**Acceptance Scenarios**:

1. **Given** three VMs are deployed with Headscale client installed, **When** each VM registers with the Headscale control server, **Then** all three VMs appear in the Headscale node list with "connected" status
2. **Given** all three VMs are registered with Headscale, **When** VM-A initiates a ping to VM-B, **Then** VM-A receives successful ping responses from VM-B
3. **Given** all three VMs are connected to the mesh, **When** VM-A initiates a ping to VM-C, **Then** VM-A receives successful ping responses from VM-C
4. **Given** the mesh network is established, **When** VM-B initiates a ping to VM-C, **Then** VM-B receives successful ping responses from VM-C
5. **Given** a VM loses connectivity to the Headscale server, **When** connectivity is restored, **Then** the VM automatically rejoins the mesh network without manual intervention

---

### User Story 2 - Cross-Network Communication (Priority: P2)

As a system administrator, I need to verify that VMs on different simulated networks can communicate through the mesh network, so that I can validate the service works across network boundaries (simulating real-world scenarios like home network to cloud VPS).

**Why this priority**: This validates the core value proposition - enabling communication across network boundaries that would normally require complex NAT traversal or VPN configuration. This is essential for real-world deployments but builds on P1's basic connectivity.

**Independent Test**: Can be tested by configuring VMs on different virtual networks (different subnets) and verifying they can communicate via mesh-assigned IP addresses. Delivers value by proving the solution works in realistic network topologies.

**Acceptance Scenarios**:

1. **Given** VM-A is on network 192.168.1.0/24 and VM-B is on network 10.0.0.0/24, **When** both VMs connect to Headscale, **Then** VM-A can reach VM-B using the Headscale-assigned IP address
2. **Given** VMs are on different networks, **When** a connection is established via Headscale, **Then** the traffic is routed through the encrypted WireGuard tunnel (not the underlying network)
3. **Given** one network has restrictive firewall rules blocking direct connections, **When** VMs communicate via Headscale, **Then** communication succeeds using the Headscale mesh routing

---

### User Story 3 - Service Binding to Mesh Network (Priority: P3)

As a system administrator, I need to verify that services can be configured to listen exclusively on the mesh network interface, so that I can ensure applications are only accessible through the secure mesh network and not exposed to untrusted networks.

**Why this priority**: This validates a critical security use case - ensuring services can be isolated to the trusted mesh network. This capability is essential for production deployments where services should only be accessible to authenticated mesh members, not the public internet or local network.

**Independent Test**: Can be tested by deploying nginx on one VM configured to bind only to the mesh interface, then verifying it's accessible from other mesh VMs but not from the underlying network. Delivers value by proving network isolation and security boundaries work correctly.

**Acceptance Scenarios**:

1. **Given** VM-A has nginx configured to listen only on its mesh interface, **When** VM-B makes an HTTP request to VM-A's mesh IP address, **Then** the request succeeds and returns the expected response
2. **Given** VM-A has nginx bound to the mesh interface, **When** an external client attempts to connect to VM-A's physical network interface, **Then** the connection fails (connection refused or timeout)
3. **Given** nginx is running on VM-A's mesh interface, **When** VM-C (on a different subnet) makes a request using the mesh IP, **Then** the request succeeds regardless of underlying network topology
4. **Given** nginx is bound to the mesh interface with hostname-based DNS, **When** VM-B makes a request using the hostname instead of IP, **Then** the request resolves and succeeds

---

### User Story 4 - Distributed DNS Resolution (Priority: P4)

As a system administrator, I need to verify that VMs can resolve each other by hostname through the distributed DNS system, so that services can use friendly names instead of IP addresses.

**Why this priority**: DNS resolution provides user-friendly naming but is not essential for basic connectivity. It's a quality-of-life improvement that makes the mesh network more practical for application deployments. Can be added after core connectivity and service binding are proven.

**Independent Test**: Can be tested by enabling the distributed DNS feature and verifying hostname resolution between nodes. Delivers value by enabling service discovery and human-readable addressing.

**Acceptance Scenarios**:

1. **Given** all VMs are registered and distributed DNS is enabled, **When** VM-A queries the hostname of VM-B, **Then** the query resolves to VM-B's mesh IP address
2. **Given** distributed DNS is configured, **When** a new VM joins the mesh, **Then** all existing VMs can resolve the new VM's hostname within 30 seconds
3. **Given** a VM changes its hostname, **When** the change is registered with the coordination server, **Then** all other VMs resolve the updated hostname to the correct IP address
4. **Given** DNS resolution is configured, **When** a VM leaves the mesh network, **Then** hostname queries for that VM fail appropriately (NXDOMAIN or timeout)

---

### Edge Cases

- What happens when two VMs attempt to register with the same hostname?
- How does the system handle a VM with intermittent connectivity (flapping connection)?
- What happens when the Headscale control server becomes temporarily unavailable?
- How does the mesh recover when a VM is forcefully removed without proper deregistration?
- What happens when VMs are deployed with mismatched Headscale client versions?
- How does the system handle network partitions where some VMs can reach the control server but not each other?
- What happens when a service tries to bind to the mesh interface before the mesh connection is established?
- How does service binding behave when the mesh connection is lost and restored?

## Requirements

### Functional Requirements

- **FR-001**: The system MUST provide a Headscale control server that can manage node registration and authorization
- **FR-002**: Each VM MUST be able to install and configure a Headscale client (Tailscale client compatible with Headscale)
- **FR-003**: VMs MUST be able to register with the Headscale control server using pre-authentication keys for automated registration
- **FR-004**: The system MUST establish encrypted WireGuard tunnels between all registered VMs (full mesh topology)
- **FR-005**: VMs MUST be able to communicate with each other using Headscale-assigned IP addresses regardless of their underlying network topology
- **FR-006**: The system MUST maintain connectivity state for all registered nodes (online/offline status)
- **FR-007**: The system MUST support DNS name resolution for registered nodes across the mesh network
- **FR-008**: The system MUST persist VM registration state across VM reboots
- **FR-009**: The system MUST provide a method to view all registered nodes and their connection status via headscale CLI commands
- **FR-009a**: The system MUST log service events to systemd journald for troubleshooting and validation
- **FR-010**: VMs MUST be able to deregister from the Headscale network cleanly
- **FR-011**: The system MUST support testing with three simultaneous VM connections as a minimum
- **FR-012**: The Headscale control server MUST run as a persistent service on a dedicated VM, separate from the client nodes being tested
- **FR-013**: VMs MUST provide a mechanism to identify the mesh network interface (name or IP address)
- **FR-014**: Services running on VMs MUST be able to bind exclusively to the mesh network interface
- **FR-015**: The system MUST prevent external network access to services bound only to the mesh interface
- **FR-016**: Services bound to the mesh interface MUST be accessible from all other mesh-connected VMs

### Key Entities

- **Headscale Control Server**: Central coordination service that manages node registration, issues WireGuard keys, and provides DNS resolution. Acts as the control plane for the mesh network.
- **VM Node**: A virtual machine running a Headscale-compatible client. Represents an endpoint in the mesh network with attributes including hostname, Headscale IP address, WireGuard public key, and connection status.
- **WireGuard Tunnel**: Encrypted peer-to-peer connection between two VM nodes. Exists independently for each pair of communicating nodes in the mesh.
- **Pre-Authentication Key**: Time-limited token used to authorize new nodes to join the Headscale network. Simplifies testing by avoiding interactive authorization flows.
- **DNS Record**: Mapping between a VM's hostname and its Headscale IP address, distributed across all nodes in the mesh.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All three VMs successfully establish connectivity within 2 minutes of registration
- **SC-002**: Ping latency between any two VMs is less than 50ms (excluding network simulation delays)
- **SC-003**: The mesh network maintains 99% uptime during a 1-hour continuous test period
- **SC-004**: DNS resolution for registered hostnames completes in under 1 second
- **SC-005**: VMs automatically reconnect to the mesh within 30 seconds after a simulated network interruption
- **SC-006**: Zero plaintext traffic is transmitted between VMs (all traffic uses WireGuard encryption)
- **SC-007**: The test environment can be deployed from scratch in under 15 minutes
- **SC-008**: Connection establishment between VMs succeeds on the first attempt in 95% of test runs

## Scope

### In Scope

- Setting up a Headscale control server in the test environment
- Deploying three virtual machines configured with Headscale clients
- Configuring VMs to register with the Headscale control server
- Testing bidirectional connectivity between all VM pairs
- Deploying nginx on one VM bound exclusively to the mesh interface
- Verifying nginx on the mesh interface is accessible from other mesh VMs
- Verifying nginx on the mesh interface is NOT accessible from external networks
- Verifying DNS resolution across the mesh network
- Simulating different network topologies (different subnets)
- Validating encrypted tunnel establishment
- Testing reconnection behavior after network interruptions
- Using systemd journald logs and headscale CLI for validation and troubleshooting
- Documenting the test setup and validation procedures

### Out of Scope

- Production deployment of Headscale
- Integration with external authentication systems (OAuth, OIDC)
- ACL (Access Control List) configuration beyond basic connectivity
- Performance benchmarking under high load
- IPv6 support (IPv4 only for initial testing)
- Multi-region or geographically distributed deployments
- Headscale server high availability or failover
- Mobile or embedded device clients (VM-only testing)
- Exit node functionality
- Subnet routing configuration

## Assumptions

- VMs will be created using the existing Keystone VM testing infrastructure (libvirt/QEMU)
- Headscale will be deployed as a NixOS service on a dedicated server VM (not a client VM)
- The test requires a total of four VMs: one Headscale server + three client nodes
- Network simulation (different subnets) can be achieved using libvirt virtual networks
- Headscale clients will use the standard Tailscale client package compatible with Headscale
- Pre-authentication keys will be used for node registration to simplify testing
- The test environment will use IPv4 addressing
- VMs will have internet connectivity for initial package downloads
- Test duration will be measured in hours, not days or weeks
- Success metrics are based on local network performance (no WAN latency simulation)

## Dependencies

- Existing Keystone VM build and management infrastructure (`bin/build-vm`, `bin/virtual-machine`)
- NixOS package repository for Headscale and Tailscale client packages
- Libvirt/QEMU for VM creation and network virtualization
- Git repository for version-controlling test configurations

## Constraints

- Testing must be performed on local hardware (no cloud resources)
- VMs must use resources available on the host system (memory, CPU limits apply)
- Network bandwidth is limited by host system capabilities
- Test execution time should not exceed 1 hour for full validation
- Solution must integrate with existing Keystone NixOS configurations
- Test suite must halt immediately on first failure for strict validation
