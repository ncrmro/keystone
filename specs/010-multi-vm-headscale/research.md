# Research: Multi-VM Headscale Connectivity Testing

**Date**: 2025-11-10
**Feature**: 010-multi-vm-headscale

This document resolves all "NEEDS CLARIFICATION" items identified in the Technical Context section of plan.md.

---

## 1. Headscale Configuration Options for DNS/Mesh Networking

### Decision: Use MagicDNS with SQLite database

**Rationale**:
- MagicDNS provides automatic hostname-to-IP resolution across mesh nodes
- SQLite is officially recommended by Headscale developers (PostgreSQL is "highly discouraged" and only maintained for legacy reasons)
- SQLite is sufficient for test workloads (3 client nodes) and simpler to configure

**Key Configuration Options**:

```nix
services.headscale = {
  enable = true;
  address = "0.0.0.0";
  port = 8080;
  settings = {
    server_url = "http://headscale.example.com:8080";

    # Database configuration (SQLite recommended)
    db_type = "sqlite3";
    db_path = "/var/lib/headscale/db.sqlite";

    # DNS/MagicDNS configuration
    dns_config = {
      override_local_dns = true;
      magic_dns = true;
      base_domain = "mesh.internal";  # Must differ from server_url domain
      nameservers = [ "1.1.1.1" "8.8.8.8" ];
      domains = [];  # Optional: split DNS for specific domains
    };

    # IP allocation for mesh nodes
    ip_prefixes = [ "100.64.0.0/10" ];  # CGNAT range (Tailscale default)
  };
};
```

**How it works**:
- Nodes are accessible as `hostname.mesh.internal` (where `mesh.internal` is the base_domain)
- DNS queries resolved locally by Tailscale client with override from Headscale
- Clients must use `--accept-dns=true` for DNS configuration to take effect
- NixOS with systemd-resolved automatically handles DNS integration

**Alternatives Considered**:
- PostgreSQL database: Rejected because Headscale developers explicitly discourage it for new deployments. SQLite is the primary focus for optimization and testing.
- Manual /etc/hosts entries: Rejected because it doesn't scale and defeats the purpose of distributed DNS validation.

---

## 2. Tailscale Client Systemd Service Configuration for Headscale Compatibility

### Decision: Use Tailscale client with --login-server flag and preauth keys

**Rationale**:
- Tailscale client is fully compatible with Headscale control servers
- Pre-authentication keys enable automated, non-interactive registration
- NixOS services.tailscale module provides clean systemd integration

**Configuration Approach**:

```nix
# Enable Tailscale on NixOS client VMs
services.tailscale = {
  enable = true;
  useRoutingFeatures = "client";  # or "both" if using subnet routing/exit nodes
};

# Registration command (run after Tailscale daemon starts)
# tailscale up --login-server=http://headscale.example.com:8080 \
#   --authkey=<PREAUTH_KEY> \
#   --accept-dns=true
```

**Pre-authentication Key Generation** (on Headscale server):

```bash
# Create a namespace (user group) for nodes
headscale namespaces create default

# Generate a pre-authentication key
headscale --namespace default preauthkeys create --reusable --expiration 24h
```

**State Persistence**:
- Tailscale stores state in `/var/lib/tailscale/tailscaled.state`
- NixOS systemd service uses StateDirectory=/var/lib/tailscale automatically
- State persists across VM reboots as long as VM disk is preserved
- Clean deregistration: `tailscale logout` or `headscale nodes delete <node-id>`

**Alternatives Considered**:
- Manual registration with web UI: Rejected for testing because it requires interactive browser authentication
- Custom Headscale client: Rejected because Tailscale client is officially supported and well-maintained

---

## 3. Best Practices for Libvirt Network Topology Simulation (Multiple Subnets)

### Decision: Create two isolated libvirt NAT networks with different subnets

**Rationale**:
- NAT networks provide isolation by default (no direct routing between networks)
- Multiple networks simulate real-world scenarios (home network vs cloud VPS)
- Easy to attach VMs to specific networks via XML domain configuration

**Network XML Definitions**:

**Subnet A (192.168.1.0/24):**
```xml
<network>
  <name>headscale-subnet-a</name>
  <forward mode='nat'/>
  <bridge name='virbr10' stp='on' delay='0'/>
  <ip address='192.168.1.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.1.100' end='192.168.1.200'/>
      <host mac='52:54:00:00:01:10' name='client-node-1' ip='192.168.1.10'/>
    </dhcp>
  </ip>
</network>
```

**Subnet B (10.0.0.0/24):**
```xml
<network>
  <name>headscale-subnet-b</name>
  <forward mode='nat'/>
  <bridge name='virbr11' stp='on' delay='0'/>
  <ip address='10.0.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.0.0.100' end='10.0.0.200'/>
      <host mac='52:54:00:00:02:10' name='client-node-2' ip='10.0.0.10'/>
      <host mac='52:54:00:00:02:11' name='client-node-3' ip='10.0.0.11'/>
    </dhcp>
  </ip>
</network>
```

**Management Commands**:
```bash
# Create networks
virsh net-define subnet-a.xml
virsh net-define subnet-b.xml

# Start networks
virsh net-start headscale-subnet-a
virsh net-start headscale-subnet-b

# Enable autostart
virsh net-autostart headscale-subnet-a
virsh net-autostart headscale-subnet-b

# Verify isolation (should have no route between 192.168.1.0/24 and 10.0.0.0/24)
ip route show
```

**VM Network Attachment** (in domain XML):
```xml
<interface type='network'>
  <source network='headscale-subnet-a'/>
  <model type='virtio'/>
  <mac address='52:54:00:00:01:10'/>
</interface>
```

**Integration with bin/virtual-machine**:
- Current script supports --network option but defaults to keystone-net
- Can extend script to accept custom network names
- Alternative: Manually attach VMs to networks after creation using `virsh edit <vm-name>`

**Verification Steps**:
1. Check VM IP: `ssh vm "ip addr show"`
2. Confirm subnet: VM on subnet A should have 192.168.1.x, subnet B should have 10.0.0.x
3. Test isolation: Direct ping from 192.168.1.10 to 10.0.0.10 should fail (no route)
4. Test mesh: Ping via Headscale IP (100.64.x.x) should succeed after mesh established

**Alternatives Considered**:
- Routed networks: Rejected because they allow direct routing, which doesn't test mesh's cross-network capability
- Single network with firewall rules: Rejected because it's more complex and doesn't simulate realistic topology

---

## 4. Headscale State Persistence Requirements

### Decision: Use default SQLite database with /var/lib/headscale persistence

**Rationale**:
- SQLite is the recommended database (as established in research item #1)
- NixOS headscale service automatically manages /var/lib/headscale StateDirectory
- Simple backup/restore via single SQLite file

**State Components**:

1. **Database** (`/var/lib/headscale/db.sqlite`):
   - Node registry (hostnames, IPs, public keys)
   - Pre-authentication keys
   - Namespace (user groups) configuration
   - DNS records

2. **Configuration** (`/etc/headscale/config.yaml`):
   - Server settings (URL, ports, DNS config)
   - Managed by NixOS, persists across rebuilds

3. **Private Keys** (embedded in database):
   - Headscale server private key (generated on first run)
   - Not stored separately

**NixOS Integration**:
```nix
services.headscale = {
  enable = true;
  # State automatically persisted in /var/lib/headscale via systemd StateDirectory
  settings = {
    db_type = "sqlite3";
    db_path = "/var/lib/headscale/db.sqlite";
  };
};
```

**Persistence Guarantees**:
- VM disk must be persistent (not ephemeral tmpfs)
- Use libvirt qcow2 disk images (default for bin/virtual-machine)
- State survives VM reboots as long as disk is not destroyed
- For test environment, can snapshot disk after initial setup

**Backup/Restore**:
```bash
# Backup (optional for testing)
systemctl stop headscale
cp /var/lib/headscale/db.sqlite /backup/headscale-$(date +%Y%m%d).sqlite
systemctl start headscale

# Restore
systemctl stop headscale
cp /backup/headscale-20251110.sqlite /var/lib/headscale/db.sqlite
systemctl start headscale
```

**Pre-authentication Key Lifecycle**:
- Keys stored in database
- Can be generated with expiration (e.g., 24h for testing)
- Reusable keys can be used for multiple node registrations
- List keys: `headscale preauthkeys list --namespace default`

**Alternatives Considered**:
- PostgreSQL: Rejected (see research item #1)
- External key storage: Rejected because Headscale manages keys internally in database

---

## 5. Automated Test Framework Options (NixOS Test Framework vs Bash Scripts)

### Decision: Use bash script orchestration with libvirt VMs for Phase 1, consider NixOS test framework for future iteration

**Rationale**:
- Bash orchestration integrates seamlessly with existing Keystone bin/virtual-machine tooling
- Provides flexibility for multi-phase testing (setup → test → cleanup)
- Easier to debug failures in incremental test scenarios
- NixOS test framework is powerful but requires learning curve and may not integrate well with persistent libvirt VMs

**Recommended Approach: Bash Script Orchestration**

**Structure**:
```bash
test/multi-vm-headscale/orchestration/
├── setup-test-env.sh           # Create VMs, networks, deploy configs
├── run-connectivity-tests.sh   # Execute P1-P4 test scenarios
├── cleanup-test-env.sh         # Destroy VMs and networks
└── lib/
    ├── vm-utils.sh             # VM lifecycle (start, stop, SSH exec)
    └── validation-utils.sh     # Assertions (assert_ping, assert_http, etc.)
```

**Key Implementation Patterns**:

1. **Wait for services**:
```bash
wait_for_ssh() {
  local vm_ip=$1
  local timeout=60
  while ! ssh -o ConnectTimeout=2 root@$vm_ip true 2>/dev/null; do
    sleep 2
    timeout=$((timeout - 2))
    [[ $timeout -le 0 ]] && return 1
  done
  return 0
}
```

2. **Execute commands in VMs**:
```bash
vm_exec() {
  local vm_ip=$1
  shift
  ssh -o StrictHostKeyChecking=no root@$vm_ip "$@"
}
```

3. **Halt on first failure**:
```bash
set -e  # Exit on any command failure
trap 'echo "Test failed at line $LINENO"; cleanup_test_env' ERR
```

4. **Test assertions**:
```bash
assert_ping() {
  local from_vm=$1
  local to_ip=$2
  vm_exec $from_vm "ping -c 3 -W 2 $to_ip" || {
    echo "FAIL: $from_vm cannot ping $to_ip"
    return 1
  }
  echo "PASS: $from_vm can ping $to_ip"
}
```

**Advantages for This Project**:
- ✅ Integrates with existing bin/virtual-machine script
- ✅ Easy to run subset of tests (just P1, or P1+P2)
- ✅ Clear failure messages with context
- ✅ Supports persistent VMs (can inspect after test failure)
- ✅ Familiar to developers (bash + SSH)

**Disadvantages**:
- ⚠️ Manual orchestration code (not declarative)
- ⚠️ Requires careful error handling
- ⚠️ Less integration testing magic than NixOS framework

**NixOS Test Framework (Future Consideration)**:

The NixOS test framework would be excellent for:
- Regression testing after mesh networking module is stable
- Declarative test definitions in repository
- Automated CI/CD pipeline integration

**Why not using it now**:
- Requires defining all VMs as NixOS test nodes (different from libvirt approach)
- Less flexibility for incremental debugging during development
- bin/virtual-machine creates persistent libvirt VMs, while NixOS test creates ephemeral QEMU VMs
- Test framework VMs don't integrate with libvirt networks defined via virsh

**Hybrid Approach for Future**:
Once bash orchestration proves the test scenarios, migrate to NixOS test framework for CI/CD automation:

```nix
# Future: test/multi-vm-headscale/nixos-test.nix
import <nixpkgs/nixos/tests/make-test-python.nix> {
  name = "headscale-mesh";
  nodes = {
    server = { ... };  # Headscale server config
    client1 = { ... };  # Client on subnet A
    client2 = { ... };  # Client on subnet B
  };
  testScript = ''
    # Python test script
    start_all()
    server.wait_for_unit("headscale.service")
    client1.succeed("tailscale up --login-server...")
    client1.succeed("ping -c 1 client2")
  '';
}
```

**Alternatives Considered**:
- Pure NixOS test framework: Rejected for Phase 1 due to integration challenges with existing tooling
- Manual testing only: Rejected because automation is required for regression testing and validation

---

## Summary of Decisions

| Research Area | Decision | Key Technology |
|---------------|----------|----------------|
| Headscale DNS | MagicDNS with SQLite | services.headscale.settings.dns_config |
| Client Configuration | Tailscale client with preauth keys | services.tailscale + tailscale up --login-server |
| Network Topology | Two isolated NAT networks | virsh net-define with different subnets |
| State Persistence | SQLite in /var/lib/headscale | NixOS StateDirectory automatic persistence |
| Test Automation | Bash orchestration (Phase 1) | SSH-based VM command execution with assertions |

All NEEDS CLARIFICATION items have been resolved and technical decisions documented with rationale.
