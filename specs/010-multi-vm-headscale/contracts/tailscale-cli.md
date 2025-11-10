# Contract: Tailscale CLI Interface (Client)

**Feature**: 010-multi-vm-headscale
**Type**: Command-Line Interface
**Version**: Tailscale 1.x (NixOS stable, Headscale-compatible)

This document defines the Tailscale client CLI commands used on VM nodes for registration, connectivity testing, and validation.

---

## Node Registration

### Connect to Headscale Server

**Command**:
```bash
tailscale up --login-server=<headscale-url> \
  --authkey=<preauth-key> \
  [--accept-dns=true] \
  [--accept-routes=true] \
  [--hostname=<hostname>]
```

**Purpose**: Register this node with the Headscale control server

**Parameters**:
- `--login-server` (required): URL of Headscale server (e.g., http://192.168.1.5:8080)
- `--authkey` (required): Pre-authentication key from Headscale
- `--accept-dns` (optional, recommended): Accept MagicDNS configuration from server
- `--accept-routes` (optional): Accept subnet routes advertised by other nodes
- `--hostname` (optional): Override system hostname for mesh network

**Success Output**:
```
Success.
```

**Alternative Success** (if already registered):
```
Already logged in.
```

**Error Cases**:
- Invalid authkey: "Failed to authenticate"
- Server unreachable: "Failed to connect to control server"
- Expired authkey: "PreAuth key expired"

**Example**:
```bash
tailscale up --login-server=http://192.168.1.5:8080 \
  --authkey=preauthkey-abc123... \
  --accept-dns=true \
  --hostname=client-node-1
```

**Usage in Tests**:
- Run during VM first boot or test setup phase
- Automated via NixOS systemd service or startup script
- Must complete before connectivity tests begin

---

## Connection Status

### Show Mesh Status

**Command**:
```bash
tailscale status
```

**Purpose**: Display connection status and peer list

**Success Output** (table format):
```
100.64.0.1   client-node-1        default      linux   active; direct 192.168.1.10:41641
100.64.0.2   client-node-2        default      linux   active; direct 10.0.0.10:41641
100.64.0.3   client-node-3        default      linux   active; direct 10.0.0.11:41641
```

**Key Fields**:
- Column 1: Mesh IP address
- Column 2: Hostname
- Column 3: Namespace
- Column 4: OS type
- Column 5: Connection status and method (direct/relay)

**Connection Status Values**:
- `active; direct`: Peer-to-peer WireGuard tunnel established
- `active; relay`: Connection via DERP relay server (not ideal)
- `idle`: No recent communication
- `offline`: Node disconnected

**Usage in Tests**:
- Verify all expected peers appear in status
- Confirm "active; direct" connections (not relayed)
- Extract mesh IPs for test validation

---

### Check Interface Status

**Command**:
```bash
ip addr show tailscale0
```

**Purpose**: Verify Tailscale interface is up and has mesh IP

**Success Output**:
```
5: tailscale0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1280 qdisc fq_codel state UNKNOWN group default qlen 500
    inet 100.64.0.1/32 scope global tailscale0
       valid_lft forever preferred_lft forever
```

**Key Indicators**:
- Interface state: `UP,LOWER_UP` (interface active)
- Inet address: Mesh IP assigned by Headscale

**Error Cases**:
- Interface doesn't exist: "Device tailscale0 does not exist"
- No IP address: Interface created but not connected to mesh

**Usage in Tests**: Verify mesh interface before ping tests

---

## Connectivity Testing

### Ping Peer (Mesh IP)

**Command**:
```bash
tailscale ping <mesh-ip-or-hostname>
```

**Purpose**: Test connectivity to another mesh node via WireGuard tunnel

**Parameters**:
- `mesh-ip-or-hostname` (required): Target peer (e.g., 100.64.0.2 or client-node-2.mesh.internal)

**Success Output**:
```
pong from client-node-2 (100.64.0.2) via 10.0.0.10:41641 in 2ms
pong from client-node-2 (100.64.0.2) via 10.0.0.10:41641 in 1ms
pong from client-node-2 (100.64.0.2) via 10.0.0.10:41641 in 1ms
```

**Key Indicators**:
- "pong" response indicates successful connectivity
- "via" shows physical endpoint (confirms cross-network communication)
- Latency in milliseconds

**Error Cases**:
- Peer offline: "no response"
- Peer not in mesh: "unknown peer"

**Usage in Tests**:
- P1 (Basic Mesh Connectivity): Verify all node pairs can ping each other
- P2 (Cross-Network): Confirm "via" shows different physical subnet

---

### Standard Network Ping

**Command**:
```bash
ping -c 3 <mesh-ip-or-hostname>
```

**Purpose**: Test network layer connectivity (alternative to tailscale ping)

**Success Output**:
```
PING 100.64.0.2 (100.64.0.2) 56(84) bytes of data.
64 bytes from 100.64.0.2: icmp_seq=1 ttl=64 time=2.1 ms
64 bytes from 100.64.0.2: icmp_seq=2 ttl=64 time=1.8 ms
64 bytes from 100.64.0.2: icmp_seq=3 ttl=64 time=1.9 ms

--- 100.64.0.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
```

**Usage in Tests**: Alternative ping method, validates ICMP over WireGuard

---

## DNS Resolution Testing

### Resolve Hostname via MagicDNS

**Command**:
```bash
nslookup <hostname>.mesh.internal
```

**Purpose**: Test distributed DNS resolution across mesh

**Success Output**:
```
Server:         100.100.100.100
Address:        100.100.100.100#53

Name:   client-node-2.mesh.internal
Address: 100.64.0.2
```

**Key Indicators**:
- Server: Tailscale local DNS resolver (100.100.100.100)
- Address: Resolved mesh IP matches expected value

**Error Cases**:
- Hostname not found: "NXDOMAIN" or "server can't find"
- DNS not configured: Falls back to system resolver (wrong answer)

**Alternative Test**:
```bash
ping -c 1 client-node-2.mesh.internal
```

**Usage in Tests**:
- P4 (Distributed DNS): Verify all nodes can resolve each other by hostname
- Validate base_domain configuration (mesh.internal)

---

## Service Binding Validation

### Check Service Listening on Mesh Interface

**Command**:
```bash
ss -tlnp | grep tailscale0
```

**Purpose**: Verify services are bound to mesh interface, not physical interfaces

**Example Output** (nginx listening on mesh IP):
```
LISTEN 0      511      100.64.0.1:80      0.0.0.0:*    users:(("nginx",pid=1234,fd=6))
```

**Key Indicators**:
- First IP column: Must be mesh IP (100.64.0.x), not 0.0.0.0 or physical IP
- Service name: Expected service (e.g., nginx)

**Usage in Tests**:
- P3 (Service Binding): Confirm nginx only listens on mesh interface
- Negative test: Verify no binding on physical interface (192.168.1.x or 10.0.0.x)

---

### Test HTTP Service Accessibility

**Command** (from another node):
```bash
curl -v http://<mesh-ip-or-hostname>:80
```

**Purpose**: Validate service is accessible via mesh, not external network

**Success Output**:
```
* Connected to 100.64.0.1 (100.64.0.1) port 80
> GET / HTTP/1.1
> Host: 100.64.0.1
>
< HTTP/1.1 200 OK
< Server: nginx
...
```

**Error Cases** (expected for negative tests):
- Connection refused: Service not listening on that interface
- Timeout: No route to host (firewall or wrong interface)

**Usage in Tests**:
- P3: Verify service accessible from mesh peers
- P3: Verify service NOT accessible from physical network

---

## Node Deregistration

### Disconnect from Mesh

**Command**:
```bash
tailscale down
```

**Purpose**: Disconnect from mesh while keeping registration

**Success Output**:
```
Success.
```

**Effect**:
- WireGuard tunnels torn down
- Interface remains but no connectivity
- Node appears "offline" in `headscale nodes list`

**Usage in Tests**: Test reconnection behavior (P1 acceptance criteria #5)

---

### Deregister Completely

**Command**:
```bash
tailscale logout
```

**Purpose**: Remove node from mesh entirely

**Success Output**:
```
Success.
```

**Effect**:
- Node removed from Headscale registry
- All state cleared from /var/lib/tailscale
- Requires re-registration with new authkey

**Usage in Tests**: Cleanup after tests, edge case testing

---

## Systemd Service Management

### Check Tailscale Service Status

**Command**:
```bash
systemctl status tailscaled
```

**Purpose**: Verify Tailscale daemon is running

**Success Output**:
```
● tailscaled.service - Tailscale node agent
   Loaded: loaded (/nix/store/.../tailscaled.service; enabled)
   Active: active (running) since ...
   Main PID: 1234 (tailscaled)
```

**Usage in Tests**: Pre-flight check before connectivity tests

---

### View Tailscale Logs

**Command**:
```bash
journalctl -u tailscaled -n 50 --no-pager
```

**Purpose**: Debug connection failures, registration issues

**Key Log Patterns** (success):
```
tailscaled: Connected to control server
tailscaled: Received node config
tailscaled: WireGuard: peer ... endpoint updated
```

**Key Log Patterns** (failure):
```
tailscaled: Failed to connect to control server
tailscaled: Authentication failed
tailscaled: DNS configuration error
```

**Usage in Tests**: Failure diagnosis

---

## Expected Command Sequences in Tests

### VM Registration Phase

```bash
# 1. Verify Tailscale daemon running
systemctl status tailscaled || exit 1

# 2. Register with Headscale
tailscale up --login-server=http://$HEADSCALE_IP:8080 \
  --authkey=$PREAUTH_KEY \
  --accept-dns=true

# 3. Verify registration successful
tailscale status | grep -q "client-node" || exit 1

# 4. Verify mesh interface has IP
ip addr show tailscale0 | grep -q "100.64" || exit 1
```

### Connectivity Test Phase (Node A → Node B)

```bash
# 5. Verify peer appears in status
tailscale status | grep -q "$NODE_B_MESH_IP" || exit 1

# 6. Test connectivity via tailscale ping
tailscale ping $NODE_B_MESH_IP -c 3 || exit 1

# 7. Test connectivity via standard ping
ping -c 3 $NODE_B_MESH_IP || exit 1
```

### DNS Resolution Test Phase

```bash
# 8. Resolve peer hostname
nslookup client-node-2.mesh.internal | grep -q "100.64.0.2" || exit 1

# 9. Ping via hostname
ping -c 3 client-node-2.mesh.internal || exit 1
```

### Service Binding Test Phase (on Node B)

```bash
# 10. Verify service bound to mesh interface
ss -tlnp | grep "100.64.0.2:80" || exit 1

# 11. Verify service NOT bound to physical interface
! ss -tlnp | grep "192.168.1.10:80" || exit 1

# 12. Test service from Node A
curl -s http://client-node-2.mesh.internal | grep -q "Welcome to nginx" || exit 1
```

---

## Error Handling Contract

All Tailscale CLI commands follow this error contract:

**Exit Codes**:
- `0`: Success
- `1`: General error
- `2`: Command not found

**Error Output**: Printed to stderr

**Recommended Test Pattern**:
```bash
if ! tailscale <command>; then
  echo "FAIL: Tailscale command failed"
  journalctl -u tailscaled -n 20 --no-pager
  exit 1
fi
```

---

This CLI contract defines the expected behavior of Tailscale client commands used on VM nodes throughout the test suite.
