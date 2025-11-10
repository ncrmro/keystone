# Quickstart: Multi-VM Headscale Connectivity Testing

**Feature**: 010-multi-vm-headscale
**Estimated Time**: 30 minutes for full test suite execution

This guide provides step-by-step instructions to set up and execute the Headscale mesh networking test environment.

---

## Prerequisites

- NixOS host system with libvirt/QEMU installed
- Minimum 16GB RAM (4 VMs × 4GB each)
- Minimum 4 CPU cores
- 40GB available disk space for VM images
- Existing Keystone repository cloned and working
- `bin/virtual-machine` script functional

---

## Quick Start (TL;DR)

```bash
# 1. Setup test environment
cd test/multi-vm-headscale/orchestration
./setup-test-env.sh

# 2. Run all connectivity tests (P1-P4)
./run-connectivity-tests.sh

# 3. Cleanup
./cleanup-test-env.sh
```

---

## Detailed Step-by-Step Guide

### Step 1: Clone Repository and Navigate to Feature Branch

```bash
cd ~/code/keystone
git checkout 010-multi-vm-headscale
cd test/multi-vm-headscale
```

**Expected Outcome**:
- Working directory: `keystone/test/multi-vm-headscale/`
- Branch: `010-multi-vm-headscale`

---

### Step 2: Review Test Infrastructure

```bash
tree orchestration/
```

**Expected Output**:
```
orchestration/
├── config.sh                   # Environment configuration
├── setup-test-env.sh           # Create VMs and networks
├── run-connectivity-tests.sh   # Execute P1-P4 test scenarios
├── cleanup-test-env.sh         # Destroy VMs and networks
└── lib/
    ├── vm-utils.sh             # VM lifecycle helper functions
    └── validation-utils.sh     # Test assertion helpers
```

---

### Step 3: Configure Test Environment (Optional)

Edit `orchestration/config.sh` to customize settings:

```bash
nano orchestration/config.sh
```

**Key Configuration Variables**:

```bash
# Headscale server configuration
HEADSCALE_SERVER_IP="192.168.1.5"      # Physical IP on subnet A
HEADSCALE_SERVER_PORT="8080"

# Client node physical IPs
CLIENT_NODE_1_PHYSICAL_IP="192.168.1.10"  # Subnet A
CLIENT_NODE_2_PHYSICAL_IP="10.0.0.10"     # Subnet B
CLIENT_NODE_3_PHYSICAL_IP="10.0.0.11"     # Subnet B

# Test thresholds
MAX_PING_LATENCY_MS=50
DNS_RESOLUTION_TIMEOUT_SEC=1
```

**Note**: Default values work for standard test setup.

---

### Step 4: Setup Test Environment

```bash
cd orchestration
./setup-test-env.sh
```

**What This Does**:
1. Creates two libvirt virtual networks (subnet-a, subnet-b)
2. Builds NixOS configurations for 4 VMs:
   - Headscale server (192.168.1.5)
   - Client node 1 (192.168.1.10)
   - Client node 2 (10.0.0.10)
   - Client node 3 (10.0.0.11)
3. Creates and starts VMs using `bin/virtual-machine`
4. Waits for VMs to boot and SSH to become available
5. Verifies Headscale service is running
6. Generates pre-authentication key
7. Deploys Tailscale configurations to client VMs
8. Waits for all nodes to register with mesh

**Expected Duration**: 10-15 minutes (includes Nix builds and VM boots)

**Success Indicators**:
```
[INFO] Creating virtual networks...
[OK] Networks created successfully

[INFO] Building VM configurations...
[OK] All NixOS configurations built

[INFO] Creating VMs...
[OK] VM headscale-server created
[OK] VM client-node-1 created
[OK] VM client-node-2 created
[OK] VM client-node-3 created

[INFO] Waiting for VMs to boot...
[OK] All VMs are accessible via SSH

[INFO] Generating pre-auth key...
[OK] PreAuth key: preauthkey-abc123...

[INFO] Registering client nodes...
[OK] client-node-1 registered (100.64.0.1)
[OK] client-node-2 registered (100.64.0.2)
[OK] client-node-3 registered (100.64.0.3)

[SUCCESS] Test environment ready!
```

**Troubleshooting**:
- If VM creation fails: Check available disk space and memory
- If SSH fails: Wait an additional 30 seconds and retry
- If registration fails: Check Headscale logs: `ssh root@192.168.1.5 "journalctl -u headscale -n 50"`

---

### Step 5: Run Connectivity Tests

```bash
./run-connectivity-tests.sh
```

**What This Does**:
Executes test scenarios in priority order (P1 → P4):

**P1 - Basic Mesh Network Connectivity**:
- Verifies all 3 nodes appear in Headscale registry
- Tests bidirectional ping between all node pairs (6 total tests)
- Validates connection status is "online"

**P2 - Cross-Network Communication**:
- Confirms node 1 (subnet A) can ping nodes 2 & 3 (subnet B)
- Verifies traffic routes through mesh IPs (100.64.x.x), not physical IPs
- Validates no direct routing between subnets (isolation test)

**P3 - Service Binding to Mesh Network**:
- Deploys nginx on node 1 bound to mesh interface only
- Verifies nginx is accessible from nodes 2 & 3 via mesh IP
- Confirms nginx is NOT accessible from physical network
- Tests hostname-based service access (http://client-node-1.mesh.internal)

**P4 - Distributed DNS Resolution**:
- Tests DNS queries from each node for all other nodes
- Validates resolution to correct mesh IPs
- Verifies sub-second DNS response times
- Tests DNS update propagation (simulated hostname change)

**Expected Duration**: 5-10 minutes

**Success Indicators**:
```
=== Running P1: Basic Mesh Network Connectivity ===
[TEST] Node registration validation...
[PASS] 3 nodes registered with Headscale

[TEST] Bidirectional connectivity...
[PASS] client-node-1 → client-node-2 (2ms)
[PASS] client-node-1 → client-node-3 (1ms)
[PASS] client-node-2 → client-node-1 (2ms)
[PASS] client-node-2 → client-node-3 (1ms)
[PASS] client-node-3 → client-node-1 (2ms)
[PASS] client-node-3 → client-node-2 (1ms)

=== P1 Results: 6/6 tests passed ===

=== Running P2: Cross-Network Communication ===
[TEST] Subnet A → Subnet B connectivity...
[PASS] Node-1 (192.168.1.10) → Node-2 (10.0.0.10) via mesh
[PASS] Node-1 (192.168.1.10) → Node-3 (10.0.0.11) via mesh

[TEST] Network isolation verification...
[PASS] Direct ping 192.168.1.10 → 10.0.0.10 fails (as expected)

=== P2 Results: 3/3 tests passed ===

=== Running P3: Service Binding to Mesh Network ===
[TEST] Deploy nginx on node-1...
[PASS] nginx deployed and listening on 100.64.0.1:80

[TEST] Mesh network accessibility...
[PASS] Node-2 can access nginx via mesh IP
[PASS] Node-3 can access nginx via mesh IP
[PASS] Node-2 can access nginx via hostname

[TEST] Physical network isolation...
[PASS] Nginx not accessible from physical IP 192.168.1.10

=== P3 Results: 5/5 tests passed ===

=== Running P4: Distributed DNS Resolution ===
[TEST] DNS resolution from all nodes...
[PASS] Node-1 resolves node-2.mesh.internal → 100.64.0.2
[PASS] Node-1 resolves node-3.mesh.internal → 100.64.0.3
[PASS] Node-2 resolves node-1.mesh.internal → 100.64.0.1
[PASS] Node-2 resolves node-3.mesh.internal → 100.64.0.3
[PASS] Node-3 resolves node-1.mesh.internal → 100.64.0.1
[PASS] Node-3 resolves node-2.mesh.internal → 100.64.0.2

[TEST] DNS resolution latency...
[PASS] All queries < 1 second

=== P4 Results: 7/7 tests passed ===

=================================================================
FINAL RESULTS: 21/21 tests passed
Test suite execution time: 8 minutes 32 seconds
=================================================================
```

**Halt on First Failure**:
If any test fails, the script will:
1. Print failure details (expected vs actual)
2. Dump relevant logs (journalctl from affected VMs)
3. Exit with code 1 (halts subsequent tests)

---

### Step 6: Manual Inspection (Optional)

While the test environment is running, you can manually inspect VMs:

```bash
# SSH to Headscale server
ssh root@192.168.1.5

# View registered nodes
headscale nodes list

# Check service status
systemctl status headscale
journalctl -u headscale -n 50

# SSH to client node
ssh root@192.168.1.10

# Check Tailscale status
tailscale status

# View mesh interface
ip addr show tailscale0

# Test manual ping
tailscale ping 100.64.0.2
```

---

### Step 7: Cleanup Test Environment

```bash
./cleanup-test-env.sh
```

**What This Does**:
1. Deregisters all client nodes from Headscale
2. Stops and destroys all VMs
3. Removes VM disk images
4. Deletes virtual networks
5. Cleans up temporary files

**Expected Duration**: 2-3 minutes

**Success Indicators**:
```
[INFO] Deregistering client nodes...
[OK] 3 nodes deregistered

[INFO] Stopping VMs...
[OK] All VMs stopped

[INFO] Destroying VMs...
[OK] VMs destroyed

[INFO] Removing virtual networks...
[OK] Networks removed

[SUCCESS] Test environment cleaned up!
```

---

## Test Scenarios Reference

### P1 - Basic Mesh Network Connectivity

**Objective**: Verify three VMs can establish encrypted mesh network

**Acceptance Criteria**:
- All 3 nodes appear in `headscale nodes list` with "online" status
- Bidirectional ping succeeds between all pairs (node1↔node2, node1↔node3, node2↔node3)
- Ping latency < 50ms

**Time**: ~2 minutes

---

### P2 - Cross-Network Communication

**Objective**: Validate mesh works across different subnets

**Acceptance Criteria**:
- Node on 192.168.1.0/24 can ping nodes on 10.0.0.0/24
- Direct ping between physical IPs fails (confirms network isolation)
- Traffic routes through mesh IPs (100.64.x.x)

**Time**: ~1 minute

---

### P3 - Service Binding to Mesh Network

**Objective**: Confirm services can bind exclusively to mesh interface

**Acceptance Criteria**:
- nginx listens only on mesh IP (100.64.0.1:80)
- Service accessible from other mesh nodes
- Service NOT accessible from physical network
- Hostname-based access works (http://node-1.mesh.internal)

**Time**: ~3 minutes (includes nginx deployment)

---

### P4 - Distributed DNS Resolution

**Objective**: Verify MagicDNS provides hostname-to-IP resolution

**Acceptance Criteria**:
- All nodes can resolve each other's hostnames (e.g., node-2.mesh.internal)
- DNS queries complete in < 1 second
- Resolution returns correct mesh IPs

**Time**: ~2 minutes

---

## Troubleshooting Common Issues

### VM Won't Boot

**Symptom**: Setup script times out waiting for SSH

**Solutions**:
1. Check VM status: `virsh list --all`
2. View VM console: `virsh console <vm-name>`
3. Check host resources: `free -h` and `df -h`
4. Increase timeout in config.sh

---

### Node Registration Fails

**Symptom**: "Failed to register with Headscale"

**Solutions**:
1. Check Headscale is running: `ssh root@192.168.1.5 "systemctl status headscale"`
2. Verify network connectivity: `ping 192.168.1.5`
3. Check preauth key validity: `ssh root@192.168.1.5 "headscale preauthkeys list"`
4. View Tailscale logs: `ssh root@<client-ip> "journalctl -u tailscaled -n 50"`

---

### Ping Tests Fail

**Symptom**: "No response" or timeout

**Solutions**:
1. Verify nodes are online: `ssh root@192.168.1.5 "headscale nodes list"`
2. Check mesh interface exists: `ssh root@<client-ip> "ip addr show tailscale0"`
3. Verify WireGuard tunnels: `ssh root@<client-ip> "tailscale status"`
4. Check for firewall issues: `ssh root@<client-ip> "iptables -L -n"`

---

### DNS Resolution Fails

**Symptom**: "NXDOMAIN" or wrong IP returned

**Solutions**:
1. Verify MagicDNS enabled: `ssh root@192.168.1.5 "grep -A5 dns_config /etc/headscale/config.yaml"`
2. Check Tailscale DNS acceptance: `ssh root@<client-ip> "tailscale status | grep DNS"`
3. Test with dig: `ssh root@<client-ip> "dig node-2.mesh.internal"`
4. Restart Tailscale: `ssh root@<client-ip> "systemctl restart tailscaled"`

---

### Service Binding Test Fails

**Symptom**: nginx not accessible or accessible from wrong interface

**Solutions**:
1. Verify nginx config: `ssh root@<client-ip> "cat /etc/nginx/nginx.conf | grep listen"`
2. Check listening sockets: `ssh root@<client-ip> "ss -tlnp | grep nginx"`
3. Test from same VM: `ssh root@<client-ip> "curl -v http://100.64.0.1"`
4. Check nginx logs: `ssh root@<client-ip> "journalctl -u nginx -n 50"`

---

## Next Steps After Quickstart

1. **Review Generated Artifacts**:
   - Read test logs in `orchestration/logs/`
   - Inspect VM configurations in `vms/`
   - Review network definitions in `networks/`

2. **Explore Advanced Scenarios**:
   - Test reconnection after simulated network interruption
   - Add a 4th client node dynamically
   - Test service discovery with multiple services

3. **Prepare for Implementation**:
   - Review [plan.md](./plan.md) for implementation roadmap
   - Study [data-model.md](./data-model.md) for entity relationships
   - Reference [contracts/](./contracts/) for CLI interfaces

4. **Contribute**:
   - Report issues or improvements
   - Extend test scenarios
   - Optimize VM configurations

---

## Additional Resources

- **Feature Spec**: [spec.md](./spec.md) - Complete requirements and user stories
- **Implementation Plan**: [plan.md](./plan.md) - Technical architecture and decisions
- **Research**: [research.md](./research.md) - Technology choices and rationale
- **Data Model**: [data-model.md](./data-model.md) - Entity definitions and relationships
- **Contracts**: [contracts/](./contracts/) - CLI interfaces and configuration schemas

- **Headscale Docs**: https://headscale.net/stable/
- **Tailscale Docs**: https://tailscale.com/kb/
- **NixOS Libvirt**: https://wiki.nixos.org/wiki/Libvirt
- **Keystone Docs**: [CLAUDE.md](../../CLAUDE.md)

---

**Congratulations!** You've successfully completed the Headscale mesh networking test suite. This validates encrypted WireGuard connectivity, cross-network communication, service binding, and distributed DNS resolution for production deployment.
