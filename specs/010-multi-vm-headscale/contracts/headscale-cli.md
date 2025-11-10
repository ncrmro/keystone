# Contract: Headscale CLI Interface

**Feature**: 010-multi-vm-headscale
**Type**: Command-Line Interface
**Version**: Headscale 0.23+ (NixOS stable)

This document defines the Headscale CLI commands used for test orchestration and validation.

---

## Namespace Management

### Create Namespace

**Command**:
```bash
headscale namespaces create <namespace-name>
```

**Purpose**: Create a logical grouping for nodes (equivalent to Tailnet in Tailscale)

**Parameters**:
- `namespace-name` (required): Name of the namespace (e.g., "default", "test")

**Success Output**:
```
Namespace 'default' created
```

**Error Cases**:
- Namespace already exists: Exit code 1, message "Namespace already exists"

**Usage in Tests**: Create "default" namespace during test environment setup

---

### List Namespaces

**Command**:
```bash
headscale namespaces list
```

**Purpose**: Verify namespace exists before node operations

**Success Output** (table format):
```
ID | Name    | Created
1  | default | 2025-11-10 10:00:00
```

**Usage in Tests**: Verify namespace creation, debugging

---

## Pre-Authentication Key Management

### Create PreAuth Key

**Command**:
```bash
headscale --namespace <namespace> preauthkeys create \
  [--reusable] \
  [--ephemeral] \
  [--expiration <duration>]
```

**Purpose**: Generate authentication token for automated node registration

**Parameters**:
- `--namespace` (required): Namespace to grant access to
- `--reusable` (optional): Allow key to be used multiple times
- `--ephemeral` (optional): Remove nodes when they disconnect
- `--expiration` (optional): Key validity period (e.g., "24h", "7d")

**Success Output**:
```
<base64-encoded-preauth-key>
```

**Example**:
```bash
headscale --namespace default preauthkeys create --reusable --expiration 24h
# Output: preauthkey-abc123def456...
```

**Error Cases**:
- Namespace doesn't exist: Exit code 1, message "Namespace not found"
- Invalid expiration format: Exit code 1, message "Invalid duration"

**Usage in Tests**:
1. Generate reusable key with 24h expiration for test duration
2. Pass key to VM configurations for automated registration
3. Store key in test orchestration script variable

---

### List PreAuth Keys

**Command**:
```bash
headscale --namespace <namespace> preauthkeys list
```

**Purpose**: Verify key creation, check expiration status

**Success Output** (table format):
```
ID | Key              | Reusable | Ephemeral | Used  | Expiration          | Created
1  | preauthkey-abc.. | true     | false     | false | 2025-11-11 10:00:00 | 2025-11-10 10:00:00
```

**Usage in Tests**: Validate key generation, debug registration failures

---

## Node Management

### List Nodes

**Command**:
```bash
headscale nodes list [--namespace <namespace>]
```

**Purpose**: View all registered nodes, verify registration, check connection status

**Success Output** (table format):
```
ID | Hostname       | Name           | MachineKey | NodeKey  | IP addresses  | Ephemeral | Last seen           | Online | Expired
1  | client-node-1  | client-node-1  | mkey:...   | nodekey: | 100.64.0.1    | false     | 2025-11-10 10:05:00 | yes    | no
2  | client-node-2  | client-node-2  | mkey:...   | nodekey: | 100.64.0.2    | false     | 2025-11-10 10:05:05 | yes    | no
3  | client-node-3  | client-node-3  | mkey:...   | nodekey: | 100.64.0.3    | false     | 2025-11-10 10:05:10 | yes    | no
```

**Key Fields for Tests**:
- `Hostname`: Must match VM hostname
- `IP addresses`: Mesh IP for connectivity tests
- `Online`: Connection status (yes/no)
- `Last seen`: Freshness indicator

**Usage in Tests**:
- Verify all 3 client nodes registered successfully
- Extract mesh IPs for ping tests
- Validate "Online" status is "yes" before connectivity tests

---

### Show Node Details

**Command**:
```bash
headscale nodes show <node-id>
```

**Purpose**: Get detailed information about a specific node

**Success Output** (JSON format):
```json
{
  "id": "1",
  "hostname": "client-node-1",
  "given_name": "client-node-1",
  "user": {
    "name": "default"
  },
  "ip_addresses": ["100.64.0.1"],
  "online": true,
  "last_seen": "2025-11-10T10:05:00Z",
  "created_at": "2025-11-10T10:00:00Z"
}
```

**Usage in Tests**: Debug specific node issues, verify attributes

---

### Delete Node

**Command**:
```bash
headscale nodes delete <node-id>
```

**Purpose**: Remove node from mesh (for cleanup or edge case testing)

**Parameters**:
- `node-id` (required): Numeric ID from `nodes list` output

**Success Output**:
```
Node <node-id> deleted
```

**Usage in Tests**:
- Cleanup after test completion
- Test edge case: "VM leaves mesh without proper deregistration"

---

## DNS Management

### Verify DNS Configuration

**Command** (indirect - check via config file):
```bash
cat /etc/headscale/config.yaml | grep -A5 dns_config
```

**Purpose**: Validate DNS settings are correctly applied

**Expected Output**:
```yaml
dns_config:
  magic_dns: true
  base_domain: mesh.internal
  override_local_dns: true
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
```

**Usage in Tests**: Pre-flight check before starting node registration

---

## Service Management

### Check Headscale Service Status

**Command**:
```bash
systemctl status headscale
```

**Purpose**: Verify Headscale server is running

**Success Output**:
```
● headscale.service - Headscale server
   Loaded: loaded (/nix/store/.../headscale.service; enabled)
   Active: active (running) since ...
   Main PID: 1234 (headscale)
```

**Key Indicators**:
- `Active: active (running)`: Service is operational
- Process should have been running for >10 seconds to be stable

**Usage in Tests**: Pre-flight check in test setup phase

---

### View Headscale Logs

**Command**:
```bash
journalctl -u headscale -n 50 --no-pager
```

**Purpose**: Debug node registration failures, connection issues

**Key Log Patterns** (success):
```
headscale: Registering node ... from namespace default
headscale: Node ... registered successfully
headscale: Peer ... connected
```

**Key Log Patterns** (failure):
```
headscale: Invalid preauth key
headscale: Namespace not found
headscale: Database connection failed
```

**Usage in Tests**: Failure diagnosis, validation logging

---

## Expected Command Sequences in Tests

### Test Setup Phase

```bash
# 1. Verify Headscale is running
systemctl status headscale || exit 1

# 2. Create namespace
headscale namespaces create default

# 3. Generate preauth key
PREAUTH_KEY=$(headscale --namespace default preauthkeys create --reusable --expiration 24h)
echo "PreAuth Key: $PREAUTH_KEY"
```

### Node Registration Validation Phase

```bash
# 4. Wait for nodes to register (poll until count = 3)
while [ $(headscale nodes list --namespace default | wc -l) -lt 4 ]; do
  sleep 2
done

# 5. Verify all nodes online
headscale nodes list --namespace default | grep -c "yes" | grep -q "3" || exit 1

# 6. Extract mesh IPs for connectivity tests
MESH_IP_1=$(headscale nodes list | grep client-node-1 | awk '{print $6}')
MESH_IP_2=$(headscale nodes list | grep client-node-2 | awk '{print $6}')
MESH_IP_3=$(headscale nodes list | grep client-node-3 | awk '{print $6}')
```

### Test Cleanup Phase

```bash
# 7. List node IDs
NODE_IDS=$(headscale nodes list --namespace default | tail -n +2 | awk '{print $1}')

# 8. Delete all nodes
for node_id in $NODE_IDS; do
  headscale nodes delete $node_id
done
```

---

## Error Handling Contract

All Headscale CLI commands follow this error contract:

**Exit Codes**:
- `0`: Success
- `1`: General error (invalid arguments, operation failed)
- `2`: Command not found (Headscale not installed)

**Error Output**: Printed to stderr

**Recommended Test Pattern**:
```bash
if ! headscale <command>; then
  echo "FAIL: Headscale command failed"
  journalctl -u headscale -n 20 --no-pager
  exit 1
fi
```

---

This CLI contract defines the expected behavior of Headscale commands used throughout the test suite.
