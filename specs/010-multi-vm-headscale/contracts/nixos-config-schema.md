# Contract: NixOS Configuration Schema

**Feature**: 010-multi-vm-headscale
**Type**: Configuration Schema
**Version**: NixOS 25.05

This document defines the NixOS configuration structure for Headscale server and Tailscale client modules used in the test environment.

---

## Headscale Server Configuration

### Module Path
`services.headscale.*`

### Required Options

```nix
services.headscale = {
  enable = true;  # Boolean, required

  address = "0.0.0.0";  # String (IP), bind address for server
  port = 8080;  # Integer, server listening port

  settings = {
    server_url = "http://headscale.example.com:8080";  # String (URL), must be reachable by clients

    # Database configuration
    db_type = "sqlite3";  # String (enum: "sqlite3", "postgres")
    db_path = "/var/lib/headscale/db.sqlite";  # String (path), required if db_type=sqlite3

    # IP allocation for mesh nodes
    ip_prefixes = [ "100.64.0.0/10" ];  # List[String (CIDR)], required

    # DNS/MagicDNS configuration
    dns_config = {
      magic_dns = true;  # Boolean, enable MagicDNS
      base_domain = "mesh.internal";  # String (domain), must differ from server_url domain
      override_local_dns = true;  # Boolean, force use of Headscale DNS
      nameservers = [ "1.1.1.1" "8.8.8.8" ];  # List[String (IP)], upstream DNS servers
      domains = [];  # List[String (domain)], optional split DNS
    };
  };
};
```

### Complete Example

```nix
{ config, pkgs, ... }:

{
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;

    settings = {
      server_url = "http://192.168.1.5:8080";  # Headscale server physical IP

      # SQLite database (recommended)
      db_type = "sqlite3";
      db_path = "/var/lib/headscale/db.sqlite";

      # Mesh IP allocation (CGNAT range, Tailscale compatible)
      ip_prefixes = [ "100.64.0.0/10" ];

      # MagicDNS configuration
      dns_config = {
        magic_dns = true;
        base_domain = "mesh.internal";
        override_local_dns = true;
        nameservers = [ "1.1.1.1" "8.8.8.8" ];
        domains = [];
      };

      # Log configuration
      log = {
        level = "info";  # "debug" | "info" | "warn" | "error"
      };
    };
  };

  # Open firewall for Headscale server
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
```

### Validation Rules

- `server_url` MUST be reachable from all client VMs
- `base_domain` MUST NOT match the domain in `server_url` (Headscale requirement)
- `ip_prefixes` MUST be valid CIDR notation
- `ip_prefixes` SHOULD use CGNAT range (100.64.0.0/10) for Tailscale compatibility
- `nameservers` MUST be valid IP addresses if `override_local_dns = true`
- `port` MUST be included in `networking.firewall.allowedTCPPorts`

---

## Tailscale Client Configuration

### Module Path
`services.tailscale.*`

### Required Options

```nix
services.tailscale = {
  enable = true;  # Boolean, required
  useRoutingFeatures = "client";  # String (enum: "none", "client", "server", "both"), optional
};
```

### Registration Script Pattern

Since NixOS module doesn't support `--login-server` directly, registration must be handled via systemd oneshot service or activation script:

```nix
systemd.services.tailscale-register = {
  description = "Register with Headscale server";
  after = [ "network-online.target" "tailscaled.service" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };

  script = ''
    ${pkgs.tailscale}/bin/tailscale up \
      --login-server=http://192.168.1.5:8080 \
      --authkey=${preauth_key} \
      --accept-dns=true \
      --hostname=${config.networking.hostName}
  '';
};
```

### Complete Example

```nix
{ config, pkgs, ... }:

let
  headscaleServerIP = "192.168.1.5";
  headscaleServerPort = "8080";
  preauthKey = "preauthkey-abc123...";  # From Headscale server
in
{
  # Enable Tailscale daemon
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";  # Enable client-side routing
  };

  # Register with Headscale on first boot
  systemd.services.tailscale-register = {
    description = "Register with Headscale server";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Check if already registered
      if ${pkgs.tailscale}/bin/tailscale status > /dev/null 2>&1; then
        echo "Already registered with mesh network"
        exit 0
      fi

      # Register with Headscale
      ${pkgs.tailscale}/bin/tailscale up \
        --login-server=http://${headscaleServerIP}:${headscaleServerPort} \
        --authkey=${preauthKey} \
        --accept-dns=true \
        --hostname=${config.networking.hostName}
    '';
  };

  # Ensure Tailscale interface is up
  systemd.network.networks."50-tailscale" = {
    matchConfig.Name = "tailscale0";
    networkConfig = {
      Description = "Tailscale mesh network interface";
    };
  };
}
```

### Validation Rules

- `useRoutingFeatures` SHOULD be set to "client" for receiving routes from mesh
- Preauth key MUST be valid and not expired
- Headscale server MUST be reachable from client VM
- Registration script MUST check if already registered (idempotency)
- Hostname SHOULD be unique across mesh network

---

## VM Network Configuration (Libvirt)

### Network XML Schema

```xml
<network>
  <name>string</name>  <!-- Required: unique network name -->
  <forward mode='nat'/>  <!-- Required for isolated NAT networks -->
  <bridge name='string' stp='on|off' delay='integer'/>  <!-- Required -->
  <ip address='ipv4' netmask='ipv4'>  <!-- Required -->
    <dhcp>
      <range start='ipv4' end='ipv4'/>  <!-- Optional: DHCP pool -->
      <host mac='mac-address' name='string' ip='ipv4'/>  <!-- Optional: static lease -->
    </dhcp>
  </ip>
</network>
```

### Example: Subnet A (192.168.1.0/24)

```xml
<network>
  <name>headscale-subnet-a</name>
  <forward mode='nat'/>
  <bridge name='virbr10' stp='on' delay='0'/>
  <ip address='192.168.1.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.1.100' end='192.168.1.200'/>
      <host mac='52:54:00:00:01:05' name='headscale-server' ip='192.168.1.5'/>
      <host mac='52:54:00:00:01:10' name='client-node-1' ip='192.168.1.10'/>
    </dhcp>
  </ip>
</network>
```

### Example: Subnet B (10.0.0.0/24)

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

### Validation Rules

- Network names MUST be unique
- Bridge names MUST be unique (e.g., virbr10, virbr11)
- IP address ranges MUST NOT overlap between networks
- MAC addresses MUST be unique across all VMs
- Static DHCP leases SHOULD be used for predictable IPs

---

## Test Orchestration Script Configuration

### Environment Variables

```bash
# Headscale server configuration
HEADSCALE_SERVER_IP="192.168.1.5"
HEADSCALE_SERVER_PORT="8080"
HEADSCALE_SERVER_URL="http://${HEADSCALE_SERVER_IP}:${HEADSCALE_SERVER_PORT}"

# Namespace configuration
HEADSCALE_NAMESPACE="default"

# Preauth key (generated dynamically)
PREAUTH_KEY=""  # Filled by setup script

# Client node configuration
CLIENT_NODE_1_HOSTNAME="client-node-1"
CLIENT_NODE_1_PHYSICAL_IP="192.168.1.10"
CLIENT_NODE_1_MESH_IP=""  # Filled after registration

CLIENT_NODE_2_HOSTNAME="client-node-2"
CLIENT_NODE_2_PHYSICAL_IP="10.0.0.10"
CLIENT_NODE_2_MESH_IP=""  # Filled after registration

CLIENT_NODE_3_HOSTNAME="client-node-3"
CLIENT_NODE_3_PHYSICAL_IP="10.0.0.11"
CLIENT_NODE_3_MESH_IP=""  # Filled after registration

# Test configuration
TEST_TIMEOUT=300  # Seconds to wait for full mesh establishment
PING_COUNT=3
CURL_TIMEOUT=5
```

### Configuration File Pattern

Test scripts SHOULD source a configuration file for environment-specific settings:

```bash
# test/multi-vm-headscale/orchestration/config.sh
#!/usr/bin/env bash

# Source this file at the beginning of test scripts

set -euo pipefail

# Headscale server
export HEADSCALE_SERVER_IP="192.168.1.5"
export HEADSCALE_SERVER_PORT="8080"
export HEADSCALE_NAMESPACE="default"

# SSH configuration
export SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
export SSH_USER="root"

# Test thresholds
export MAX_PING_LATENCY_MS=50
export DNS_RESOLUTION_TIMEOUT_SEC=1
export SERVICE_STARTUP_TIMEOUT_SEC=30
```

---

## Integration Contract

### Dependency Injection Pattern

Configuration values MUST be injected into NixOS configurations, not hardcoded:

```nix
{ config, lib, pkgs, headscaleServerIP, preauthKey, ... }:

{
  services.tailscale.enable = true;

  systemd.services.tailscale-register = {
    script = ''
      ${pkgs.tailscale}/bin/tailscale up \
        --login-server=http://${headscaleServerIP}:8080 \
        --authkey=${preauthKey} \
        --accept-dns=true
    '';
  };
}
```

### Build-Time vs Runtime Configuration

| Configuration | When Determined | Mechanism |
|---------------|-----------------|-----------|
| Headscale server IP | Build-time or runtime | Nix specialArgs or environment variable |
| Preauth key | Runtime | Generated by setup script, passed to VMs |
| Mesh IPs | Runtime | Assigned by Headscale, extracted from CLI |
| Physical IPs | Build-time | Libvirt network XML static DHCP leases |
| Hostnames | Build-time | NixOS config.networking.hostName |

---

This configuration schema defines the contract between NixOS modules, test scripts, and infrastructure components.
