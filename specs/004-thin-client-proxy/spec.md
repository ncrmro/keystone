# Thin Client Proxy Specification

## Overview

- **Goal**: Enable workstations/servers to host local development servers accessible via the same hostname from both local connections and remote thin clients over Headscale VPN.
- **Scope**: DNS resolution, reverse proxy configuration, and certificate management for seamless local/remote development workflows.
- **Use Case**: A developer on a workstation runs `localhost:3000` and thin clients on the same Headscale network can access it via `dev.workstation.tailnet` using the same URLs.

## Problem Statement

When developing on a workstation, services typically bind to `localhost` or `127.0.0.1`. This creates friction when:

1. Switching between the workstation and a thin client (laptop, tablet)
2. Testing from multiple devices on the same network
3. Sharing development previews with team members on the tailnet

Currently, developers must manually configure port forwarding, update `/etc/hosts`, or use different URLs depending on access location.

## Functional Requirements

### FR-001: Unified Hostname Resolution

- Local connections on the workstation resolve `dev.hostname` to `127.0.0.1`
- Thin clients on the Headscale network resolve `dev.hostname` to the workstation's tailnet IP
- Resolution must work without manual `/etc/hosts` configuration on clients

### FR-002: Reverse Proxy

- A reverse proxy runs on the workstation to forward requests to local dev servers
- Support for multiple simultaneous dev servers (e.g., `app.dev.hostname`, `api.dev.hostname`)
- WebSocket support for hot-reload functionality
- Configurable port mappings (e.g., `app` → `localhost:3000`, `api` → `localhost:8080`)

### FR-003: TLS Certificates

- Automatic TLS certificate generation for dev domains
- Certificates trusted by both local and remote clients
- Support for wildcard certificates (`*.dev.hostname`)
- Integration with system trust stores

### FR-004: Service Discovery

- Automatic detection of running dev servers (optional)
- Manual registration of port mappings via configuration
- Status dashboard showing active proxied services

### FR-005: Headscale Integration

- Register DNS records with Headscale MagicDNS
- Advertise routes if needed for subnet access
- Handle tailnet reconnection gracefully

## Non-Functional Requirements

### NFR-001: Zero-Configuration Thin Clients

- Thin clients should require no additional setup beyond Headscale connection
- DNS and certificate trust should propagate automatically via tailnet

### NFR-002: Low Latency

- Proxy overhead should be negligible for local connections (<1ms added latency)
- Remote connections should only add tailnet transport latency

### NFR-003: Security

- Only tailnet-authenticated clients can access proxied services
- Local-only services can optionally be excluded from remote access
- Audit logging for remote access attempts

### NFR-004: Reliability

- Proxy should auto-restart on failure
- Graceful handling of dev server restarts
- No orphaned connections on service changes

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        WORKSTATION                               │
│  ┌─────────────────┐     ┌─────────────────┐                    │
│  │   Dev Server    │     │   Dev Server    │                    │
│  │  localhost:3000 │     │  localhost:8080 │                    │
│  └────────┬────────┘     └────────┬────────┘                    │
│           │                       │                              │
│           └───────────┬───────────┘                              │
│                       ▼                                          │
│           ┌───────────────────────┐                              │
│           │    Reverse Proxy      │                              │
│           │  (Caddy/nginx/traefik)│                              │
│           │   - TLS termination   │                              │
│           │   - Host routing      │                              │
│           └───────────┬───────────┘                              │
│                       │                                          │
│     ┌─────────────────┴─────────────────┐                        │
│     ▼                                   ▼                        │
│  ┌──────┐                         ┌──────────┐                   │
│  │ eth0 │                         │ tailnet0 │                   │
│  │ LAN  │                         │ 100.x.x.x│                   │
│  └──────┘                         └──────────┘                   │
└─────────────────────────────────────────────────────────────────┘
           │                               │
           ▼                               ▼
    ┌─────────────┐               ┌──────────────────┐
    │ Local       │               │ Headscale Server │
    │ Browser     │               │ - MagicDNS       │
    │ (workstation)│              │ - ACLs           │
    └─────────────┘               └────────┬─────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │   Thin Client   │
                                  │   (laptop)      │
                                  │ dev.workstation │
                                  │  → 100.x.x.x    │
                                  └─────────────────┘
```

## Implementation Options

### Option A: Caddy with Tailscale Integration

- Use Caddy's automatic HTTPS with tailnet certificates
- Tailscale's `tailscale cert` for trusted certificates
- Simple configuration, batteries-included

### Option B: Traefik with Custom CA

- Self-hosted CA for development certificates
- More control over certificate lifecycle
- Requires trust store management

### Option C: nginx + mkcert + systemd

- Traditional reverse proxy setup
- mkcert for local CA management
- Systemd services for lifecycle

## Configuration Model

```nix
keystone.devProxy = {
  enable = true;

  # Base domain for dev services
  domain = "dev.${config.networking.hostName}";

  # Services to proxy
  services = {
    app = {
      port = 3000;
      # Optional: restrict to local only
      localOnly = false;
    };
    api = {
      port = 8080;
    };
    docs = {
      port = 4000;
      localOnly = true;  # Not exposed to thin clients
    };
  };

  # Headscale integration
  headscale = {
    enable = true;
    # Register DNS with MagicDNS
    registerDns = true;
  };

  # Certificate configuration
  tls = {
    # "tailscale" | "mkcert" | "acme"
    provider = "tailscale";
  };
};
```

## DNS Resolution Strategy

### Local Resolution (on workstation)

1. Configure systemd-resolved or dnsmasq to resolve `*.dev.hostname` to `127.0.0.1`
2. Alternatively, use `/etc/hosts` entries generated by NixOS module

### Remote Resolution (thin clients via Headscale)

1. Register `dev.hostname` A record pointing to workstation's tailnet IP
2. Use Headscale MagicDNS for automatic propagation
3. Wildcard support depends on Headscale capabilities

## Certificate Trust

### Tailscale Certificates (Recommended)

- Use `tailscale cert dev.hostname` to obtain Let's Encrypt certificates
- Automatically trusted by all clients
- Requires tailnet domain configuration

### Self-Signed CA (Fallback)

- Generate CA on workstation
- Distribute CA certificate to thin clients via:
  - NixOS configuration (for managed thin clients)
  - Manual installation instructions
  - Headscale-distributed configuration

## Out of Scope (for now)

- Load balancing across multiple workstations
- Service mesh integration
- Production deployment (this is explicitly for dev workflows)
- Non-HTTP protocols (database connections, etc.) - use direct tailnet IPs
- Automatic dev server detection via process monitoring

## Open Questions

1. Should we support exposing Docker container ports automatically?
2. How to handle port conflicts when multiple dev servers want the same subdomain?
3. Should we integrate with existing project configuration (`.env`, `docker-compose.yml`)?
4. What's the fallback behavior when Headscale is unreachable?

## Success Criteria

1. Developer can run `npm run dev` on workstation and access it from thin client within 5 seconds
2. Same URL works from both workstation browser and thin client browser
3. Hot reload / WebSocket connections work seamlessly
4. No manual DNS or hosts file configuration required on thin clients
5. TLS works without browser warnings on any connected client
