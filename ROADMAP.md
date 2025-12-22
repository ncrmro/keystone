# Keystone Roadmap

NixOS-based self-sovereign infrastructure platform for deploying secure, encrypted systems on any hardware.

> **Specifications**: [spec.md](specs/001-keystone-os/spec.md) | [plan.md](specs/001-keystone-os/plan.md)

---

## v0.0.1 — Secure Foundation
**Status**: Core complete, polish pending

Encrypted NixOS server with TPM2 auto-unlock and Secure Boot.

| Component | Status |
|-----------|--------|
| ZFS root with native encryption (credstore pattern) | Done |
| TPM2 enrollment with PCR binding | Done |
| Secure Boot via Lanzaboote | Done |
| ISO installer with nixos-anywhere support | Done |
| Server base module (SSH, mDNS, firewall) | Done |
| Installation documentation | Pending |
| TPM error recovery procedures | Pending |
| Multi-disk configurations | Pending |

---

## v0.0.2 — Developer Environment
**Status**: Core complete, integration pending

Terminal development environment accessible via SSH from any client OS.

| Component | Status |
|-----------|--------|
| Terminal dev module (Helix, Zsh, Zellij, Ghostty, Git) | Done |
| User management with home-manager integration | Done |
| Server-side home-manager integration | Pending |
| Remote development documentation | Pending |

---

## v0.0.3 — Workstation Desktop
**Status**: Implemented, testing phase

Hyprland desktop for local or remote workstation use.

| Component | Status |
|-----------|--------|
| Hyprland + UWSM session management | Done |
| Greetd login manager | Done |
| PipeWire audio | Done |
| Desktop applications (Firefox, VS Code, VLC) | Done |
| Screen locking (Hyprlock/Hypridle) | Done |
| Remote desktop access (RDP/VNC/Sunshine) | Pending |
| Multi-monitor configuration | Pending |

**Out of scope**: Laptop-specific features, multi-GPU, fractional scaling.

---

## v0.0.4 — Universal Development
**Status**: Mac support in progress

Multi-platform support for Apple Silicon Macs and portable home-manager.

| Component | Status |
|-----------|--------|
| Apple Silicon Mac module (operating-system-mac) | Done |
| ext4 + LUKS storage for Mac | Done |
| Base module extraction (users, services, nix) | Done |
| Portable home-manager flake with platform detection | Pending |
| GitHub Codespaces integration | Pending |
| macOS support via nix-darwin | Pending |
| Cross-platform secrets handling (agenix/sops-nix) | Pending |

**Mac Platform Notes**:
- Uses `nixos-apple-silicon` for M1/M2/M3 hardware
- ext4 only (ZFS untested)
- No TPM or Secure Boot (uses Apple's boot chain)
- Manual password entry on boot

---

## Future Releases

| Version | Focus |
|---------|-------|
| 0.1.0 | Production: backups, monitoring, secrets management, disaster recovery |
| 0.2.0 | Infrastructure: k3s, self-hosted services, mesh VPN, distributed storage |
| 0.3.0 | Enterprise: LDAP, compliance automation, audit logging, PKI |

---

## Current Priority

1. **Now**: Polish v0.0.1 — documentation, error recovery, automated testing
2. **Next**: Finalize v0.0.2 — server home-manager, remote dev workflows
3. **Then**: Stabilize v0.0.3 — remote desktop, multi-monitor support
