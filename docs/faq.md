---
title: Keystone FAQ
description: Common questions about Keystone — comparisons, security, getting started, and day-to-day use
---

# Keystone FAQ

## Positioning & Comparisons

### How is Keystone different from Ansible?

Ansible is a **remote automation tool** — you write playbooks that SSH into existing
machines and run tasks imperatively. Keystone is a **declarative NixOS-based OS
platform** — you describe the entire machine state (disk encryption, services, users,
desktop) in Nix and the system is built reproducibly from that description.

| | **Keystone** | **Ansible** |
|---|---|---|
| **What it is** | A NixOS-based OS platform installed on bare metal via USB | A remote task-runner that configures existing machines over SSH |
| **Configuration model** | Declarative — describe *what* the system should be; Nix computes the difference | Imperative — describe *steps to run*; order and idempotency are your responsibility |
| **Reproducibility** | Fully reproducible — pinned flake inputs, binary cache, identical rebuilds | Best-effort — depends on upstream package repos, install order, and system state |
| **Scope** | Full stack: disk encryption, Secure Boot, TPM, ZFS, services, desktop, terminal, AI agents | Configuration management only — does not own the OS, bootloader, or disk layout |
| **Drift handling** | No drift — `nixos-rebuild switch` converges the entire system to the declared state | Drift is possible between runs; you re-run playbooks to correct it |
| **Rollbacks** | Instant — NixOS generations + ZFS snapshots let you boot any previous state | No built-in rollback; you write a reverse playbook or restore from backup |
| **Self-hosted services** | One toggle (`keystone.services.immich.enable = true;`) auto-configures TLS, DNS, reverse proxy | Write roles and playbooks per service, manage templates, handlers, and dependencies yourself |
| **OS agents (AI)** | First-class — sandboxed user accounts with their own UID, SSH keys, email, and task queues | Not a concept — requires bolting on an external agent framework |
| **Target audience** | Individuals and households who want to own their infrastructure end-to-end on their own hardware | Teams managing fleets of cloud or on-prem servers they don't control the OS image for |

Ansible operates *on top of* whatever OS a machine already runs. Keystone **is** the OS
— it replaces the need for post-install configuration management because the system is
defined before it is ever built.

See also: [Keystone Comparison](comparison.md)

---

### How does Keystone compare to Proxmox / TrueNAS / Unraid?

Proxmox, TrueNAS, and Unraid are GUI-driven appliance OSes focused on virtualization or
NAS workloads. They are powerful within their scope, but your configuration lives in a
web UI, not in version-controlled code.

Keystone is declarative and reproducible — your entire system config is committed Nix
code. Keystone includes ZFS with native encryption and snapshots (like TrueNAS), but
also covers:

- Secure Boot with custom key enrollment
- TPM2 auto-unlock
- A curated set of self-hosted services (Immich, Forgejo, Vaultwarden, Stalwart, Grafana, …)
- A Hyprland desktop environment with 15 themes
- A full terminal developer environment (Zsh, Helix, Zellij, AI tools)
- OS-level AI agent accounts

No web GUI required. Every change is a git commit you can diff, review, and roll back.

---

### How is Keystone different from just using plain NixOS?

Keystone is a curated layer of NixOS and Home Manager modules. Everything it does you
*could* wire up yourself on vanilla NixOS — Keystone saves you months of integration
work.

Concretely, Keystone adds:

- **Opinionated ZFS storage** — encrypted pool with TPM2 auto-unlock and snapshot defaults
- **One-toggle self-hosted services** — Immich, Forgejo, Vaultwarden, Stalwart, AdGuard, Headscale, Grafana, and more, each with automatic TLS, DNS, and reverse proxy
- **Complete terminal dev environment** — Zsh, Helix, Zellij, Git with SSH signing, AI coding tools, PIM (email, calendar, contacts, tasks)
- **Hyprland desktop** — tiling window manager with 15 themes, keybindings, and components
- **OS-level AI agents** — sandboxed user accounts with their own UID, SSH keys, email address, git workspace, and task queue
- **`ks` CLI** — fleet build, deploy, notification routing, and doctor commands
- **USB installer TUI** — guided install flow without writing Nix upfront

If you enjoy assembling the pieces yourself, plain NixOS is great. If you want an
integrated, opinionated starting point that keeps your config small, use Keystone.

---

### How does Keystone compare to Docker Compose / CasaOS / Umbrel for self-hosting?

Container-based homelab dashboards run services in Docker and expose a web UI to manage
them. They are easy to start but harder to reproduce and have no OS-level integration.

Keystone runs services as **native NixOS systemd units** with declarative configuration.
Benefits:

| | **Keystone** | **Docker Compose / CasaOS / Umbrel** |
|---|---|---|
| **Config model** | Declarative Nix — version-controlled, diffable | Web UI or `docker-compose.yml` files |
| **TLS / DNS** | Automatic via ACME and internal DNS | Manual or plugin-based |
| **Rollbacks** | Instant — NixOS generations | Re-deploy from a backup or previous compose file |
| **Runtime overhead** | None — no container daemon per service | Docker daemon running on top of the OS |
| **Secret management** | agenix — encrypted at rest, decrypted only on target machine | Env files or `.env` — often committed or left in plaintext |
| **OS integration** | Services share users, storage, and secret store with the rest of the system | Services run in isolated containers with volume mounts |

You can still run Docker containers inside Keystone for services that don't have NixOS
modules yet. Keystone's `nixpkgs` + `oci-containers` support makes this straightforward.

---

### How do Keystone OS Agents compare to cloud-hosted AI coding agents?

Cloud AI agents (Devin, GitHub Copilot Workspace, Codex Cloud, etc.) run on someone
else's infrastructure. Your code is uploaded to a remote machine you do not control.

Keystone OS Agents run **on your own hardware**:

| | **Keystone OS Agents** | **Cloud AI agents** |
|---|---|---|
| **Where they run** | Your physical machine, your UID, your home directory | Remote cloud infrastructure |
| **Your code** | Never leaves your machine | Uploaded to a third-party service |
| **Identity** | Own Unix user, SSH keys, email address, git config | Ephemeral cloud session |
| **Task queue** | Persistent, self-hosted — survives reboots | Tied to the cloud session |
| **Cost** | Hardware you already own | Per-use cloud billing |
| **Capabilities** | Fetch issues, write code, open PRs, send/receive email, process documents | Varies by provider |

See also: [OS Agents overview](agents/os-agents.md) · [Agent comparison](agents/comparison.md)

---

### Is Keystone like Terraform?

Not really — they operate at different layers.

**Terraform** manages cloud resources (VMs, networks, load balancers, DNS records)
declaratively via cloud provider APIs. It does not touch the OS running inside those VMs.

**Keystone** manages the OS on physical (or virtual) machines declaratively via Nix. It
handles everything from the bootloader up: disk encryption, Secure Boot, services,
desktop, users.

They complement each other well. A common pattern:

1. Use Terraform to provision a VPS from a cloud provider.
2. Boot the Keystone USB installer on that VPS.
3. Keystone manages the OS from there.

Terraform handles cloud API resources; Keystone handles the machine itself.

---

## Security & Trust

### How does full-disk encryption work? Do I need a TPM?

Keystone uses **ZFS native encryption** for the data pool and a **LUKS credstore
volume** for the key material. On first boot you enroll a TPM2 chip for automatic
unlock — subsequent boots require no passphrase. Secure Boot with custom key enrollment
ensures that only your signed bootloader and kernel can start the machine.

A TPM 2.0 chip is **recommended but not required**. Without it, you will be prompted for
your disk passphrase at each boot. With it, the unlock is fully automatic and the key
material is bound to the measured boot state.

See also: [TPM enrollment](os/tpm-enrollment.md) · [Installation guide](os/installation.md)

---

### What happens if my TPM fails or I update my BIOS?

TPM enrollment is bound to PCR (Platform Configuration Register) values — a fingerprint
of your firmware, Secure Boot certificates, and boot chain. A BIOS update or settings
change can change those values and invalidate the binding.

When that happens:

1. You will be prompted for your recovery key at boot.
2. Once logged in, re-enroll the TPM with `keystone-enroll-recovery`.
3. The new PCR values are measured and the binding is updated.

Keystone supports configurable PCR sets so you can balance resilience (fewer PCRs =
survives minor firmware updates) against security (more PCRs = tighter binding).

See also: [TPM enrollment](os/tpm-enrollment.md)

---

### Is my data safe if someone steals the physical machine?

Yes. Full disk encryption means the data is unreadable without the TPM + Secure Boot
chain (or the recovery key). With Secure Boot custom keys enrolled, an attacker cannot
boot a modified OS or live USB to extract data — the machine will refuse to run unsigned
code.

Your recovery key should be stored securely offline (printed, in a hardware password
manager, or in a geographically separate location). Do not store it on the same machine.

---

### How are secrets managed?

Keystone uses **[agenix](https://github.com/ryantm/agenix)** with age encryption and
optional YubiKey / FIDO2 hardware key support.

- Secrets are encrypted at rest inside your `keystone-config` repo using `age` public
  keys (SSH host keys, YubiKey PIV keys, or age keypairs).
- During system activation, agenix decrypts each secret only on the target machine, into
  a tmpfs location that is not world-readable.
- No secrets are ever stored in plaintext in the Nix store.

This replaces tools like HashiCorp Vault or SOPS for machine-level secrets. For
human-facing passwords (web logins, etc.), Vaultwarden (a self-hosted Bitwarden backend)
is available as a one-toggle service.

See also: [Hardware keys](os/hardware-keys.md)

---

## Getting Started & Requirements

### What hardware do I need?

- **Architecture**: x86_64 (AMD64). ARM is not currently supported.
- **Firmware**: UEFI required. Legacy BIOS is not supported.
- **TPM**: TPM 2.0 recommended for automatic disk unlock. Optional — without it you enter a passphrase at boot.
- **RAM**: 4 GB minimum for server-only deployments; 8 GB or more for desktop.
- **Storage**: An NVMe or SATA SSD for the ZFS pool. Spinning disks work but are slower for ZFS metadata.
- **Form factor**: Any machine — tower, rack server, mini-PC, laptop, or workstation.

---

### Can I try Keystone in a VM before committing real hardware?

Yes. The Makefile includes VM targets that build and launch QEMU VMs:

```bash
# Terminal-only VM
make build-vm-terminal

# Full Hyprland desktop VM
make build-vm-desktop
```

These build in minutes and give you a live Keystone environment. Note that VM mode does
not include disk encryption or Secure Boot — those require real hardware with a TPM.
VMs are for testing configuration, not the security stack.

See also: [VM testing](os/testing-vm.md) · [ISO and OS VM testing](testing/iso-os-virtual-machine.md)

---

### Can I install Keystone alongside my existing OS (dual boot)?

No. The Keystone installer and the `disko` module format the **entire target disk** with
a ZFS layout. This is a full-wipe install.

Options:

- Use a dedicated machine or a drive you are willing to erase.
- Test in a VM first (see above) to validate your config before touching real hardware.

---

### Do I need to know Nix to use Keystone?

**For initial installation**: No. The USB installer TUI handles disk selection, user
creation, and first boot without writing Nix.

**For ongoing configuration**: Yes, eventually. Enabling services, adding users,
customizing the desktop, and managing fleet-wide settings all involve editing Nix files
in your `keystone-config` repo. The syntax is approachable for common tasks — many
options are single boolean or string values.

**For deep customization**: Nix fluency helps. Writing new modules, overriding
packages, or integrating third-party NixOS modules benefits from understanding the Nix
language and the NixOS module system.

---

## Self-Hosted Services

### What services are included and how do I enable them?

Enable any service with a single option in your `keystone-config`. Keystone
auto-configures TLS certificates (via ACME / Let's Encrypt), reverse proxy (nginx), and
internal DNS for each service.

| Service | What it replaces |
|---|---|
| **Immich** | Google Photos |
| **Forgejo** | GitHub |
| **Vaultwarden** | 1Password / Bitwarden cloud |
| **Stalwart** | Gmail / Fastmail — full mail server |
| **AdGuard Home** | Pi-hole |
| **Headscale** | Tailscale control plane |
| **Grafana + Prometheus + Loki** | Datadog / CloudWatch |
| **Miniflux** | Feedly |
| **Attic** | Cachix — Nix binary cache |
| **SeaweedFS** | AWS S3 |

Example:

```nix
keystone.services.immich.enable = true;
keystone.services.forgejo.enable = true;
```

See also: [OS module reference](os/server.md)

---

### Can I add my own services that aren't in the Keystone module list?

Yes. Keystone is standard NixOS underneath. You can add any NixOS service, Docker
container (via `oci-containers`), or custom systemd unit alongside Keystone-managed
services in your `keystone-config`.

Keystone's nginx reverse proxy and ACME certificate management are exposed as standard
NixOS options and can be extended for your own virtual hosts. Agenix secrets work the
same way for your custom services.

---

### How do backups work?

Keystone uses **ZFS snapshots** and optional **ZFS replication** for data protection:

- **ZFS snapshots** — instant, space-efficient point-in-time copies. Creating a snapshot
  takes milliseconds; restoring is a single command. Snapshots protect against accidental
  deletion and ransomware.
- **ZFS replication with syncoid** — automated, incremental replication of your pool to
  a second machine (an offsite VPS, a NAS, or another Keystone host). Only changed blocks
  are transferred.
- **NixOS generations** — every `nixos-rebuild switch` creates a new generation. Roll
  back the entire system *configuration* independently of data.

These are complementary: ZFS snapshots protect data; NixOS generations protect config.

---

## OS Agents

### What are OS Agents and why would I want them?

OS Agents are **autonomous user accounts** that run on your system with their own
identity:

- A dedicated Unix user (UID)
- SSH keys for git and remote access
- An email address for receiving task assignments
- A git workspace for code
- A persistent task queue

Agents can fetch issues from GitHub or Forgejo, write code, open pull requests, send and
receive email, and process documents — all running on your hardware, not a cloud service.

This is useful for individuals who want AI-assisted development without sending their
code to a third-party service, and for small teams who want a persistent local agent that
accumulates context over time.

See also: [OS Agents overview](agents/os-agents.md) · [Agent comparison](agents/comparison.md)

---

### Are agents sandboxed? Can they break my system?

Agents run as separate Unix users with their own home directories. They:

- Do **not** have root or sudo access
- Cannot modify system configuration
- Cannot read other users' home directories
- Are scoped to their own workspace, repos, and task queue

The blast radius of a misbehaving agent is limited to its own user account. System
configuration changes require your admin credentials, not the agent's.

---

### What can agents actually do today?

Current agent capabilities:

- Sync git repositories from GitHub and Forgejo
- Fetch and triage issues from connected forges
- Run AI coding tools (Claude Code, Gemini CLI, and others in the Keystone overlay)
- Open pull requests with generated changes
- Send and receive email (via Stalwart + Himalaya)
- Process documents in the agent workspace

The agent platform is actively evolving. See [OS Agents overview](agents/os-agents.md)
for the latest capability details.

---

## Desktop & Terminal

### Can I use Keystone without the desktop (server-only)?

Yes. The Hyprland desktop module is entirely optional. A server-only Keystone deployment
imports only `keystone.nixosModules.operating-system` and
`keystone.nixosModules.server`. The desktop module (`keystone.nixosModules.desktop`) is
not imported and nothing Hyprland-related is installed.

Server-only is the most common Keystone deployment for NAS and headless service hosts.

---

### Can I use the terminal environment on macOS without Keystone OS?

Yes. `keystone.terminal` is a **Home Manager module** that runs entirely in userspace.
It works on:

- **macOS** — via nix-darwin + Home Manager
- **Ubuntu / other Linux** — via Nix package manager + standalone Home Manager
- **WSL2** — inside a WSL2 Linux distribution
- **Existing NixOS** — as a home-manager module without the Keystone OS layer

You get Zsh, Helix, Zellij, Git with SSH signing, AI coding tools, and PIM (email,
calendar, contacts, tasks) — without replacing your OS.

See also: [Terminal module overview](terminal/terminal.md) · [Install the terminal environment](terminal/tui-install.md) · [Cross-platform comparison](comparison.md)

---

### What if I don't like Helix / Zellij / Zsh — can I swap components?

The terminal module is opinionated by default but built on standard Home Manager options.
You can disable individual components and substitute your own in your `keystone-config`:

```nix
keystone.terminal.enable = true;
# Override specific components via standard home-manager options
programs.vim.enable = true;   # use vim instead of Helix
programs.tmux.enable = true;  # use tmux instead of Zellij
```

If you want full modularity with no opinions, you can use individual Home Manager modules
directly and skip the Keystone terminal module entirely. Keystone provides a curated,
integrated experience; every piece is replaceable.

---

## Day-to-Day Operations

### How do I update Keystone and my services?

From your `keystone-config` repo:

```bash
# Update all inputs, rebuild, and deploy to the current host
ks update --lock

# Deploy to specific hosts
ks update --lock ocean,mercury

# Home Manager-only changes (faster — no system rebuild)
ks update --dev
```

`ks update` pulls upstream Keystone changes, locks flake inputs, builds the new system
closure, and deploys atomically. The previous generation remains bootable throughout.

See also: [Keystone CLI (`ks`)](ks.md)

---

### What happens if an update breaks something?

Every `nixos-rebuild switch` creates a new **NixOS generation**. If something breaks:

1. Reboot the machine.
2. At the boot menu, select the previous generation.
3. You are instantly back to the exact previous system state — same kernel, same
   packages, same service configuration.

For data, ZFS snapshots provide the same instant rollback for files. NixOS generations
protect configuration; ZFS snapshots protect data.

---

### How do I manage multiple machines from one config?

Create a `keystone-config` repo with multiple `nixosConfigurations` in your `flake.nix`
— one per host. A typical layout:

```
keystone-config/
  flake.nix           # one nixosConfiguration per host
  shared.nix          # users, repos, service placement, global settings
  hosts/
    server.nix        # disk IDs, hardware-specific config
    workstation.nix
    laptop.nix
```

Shared settings (users, repos, which services run where) go in a shared module. Per-host
settings (disk IDs, hardware quirks, GPU config) go in host-specific files.

Deploy to a specific host:

```bash
ks update --lock server
```

See also: [keystone-config reference](keystone-config.md)

---

### Can multiple people in my household have their own accounts?

Yes. Declare users in your Keystone config with `keystone.os.users`. Each user gets:

- Their own home directory
- SSH key management
- An optional Home Manager profile (terminal environment, dotfiles, AI tools)
- Configurable group memberships and roles

```nix
keystone.os.users = {
  alice = { ... };
  bob   = { ... };
};
```

See also: [User management](os/users.md)

---

## Project & Community

### Is Keystone production-ready?

Keystone is actively used for real infrastructure — servers, workstations, and laptops.
The core modules (ZFS storage, Secure Boot, TPM, self-hosted services) are stable. The
agent platform and some newer modules are under active development.

Check the [CHANGELOG](../CHANGELOG.md) and release notes for the stability status of
specific features before relying on them in critical environments.

---

### What's the license?

MIT. You can use, modify, and distribute Keystone freely, including for commercial
purposes. See the [LICENSE](https://github.com/ncrmro/keystone/blob/main/LICENSE) file
for the full text.

---

### How do I contribute?

Contributions are welcome across all areas:

- **Documentation** — clarifications, corrections, new guides
- **Testing and bug reports** — hardware compatibility, edge cases, reproducibility
- **Security auditing** — review of the encryption, TPM, and Secure Boot stack
- **Module development** — new services, improved defaults, NixOS option coverage
- **Platform support** — new hardware, firmware configurations

See the [GitHub repository](https://github.com/ncrmro/keystone) for open issues and
discussions. If you are unsure where to start, documentation improvements and bug reports
are always valuable.
