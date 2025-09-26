# Keystone

Keystone enables self-sovereign infrastructure that you fully control, whether running on bare-metal hardware or cloud services. Unlike traditional infrastructure solutions, Keystone is designed for seamless migration between different environments while maintaining security, availability, and shared resource access.

## Core Principles

**Self-Sovereign Infrastructure**: Your infrastructure belongs to you. All data is encrypted at rest and in transit, with cryptographic keys under your control. Whether running on a Raspberry Pi in your home or a cloud VPS, you maintain full ownership and control.

**Declarative Configuration**: Everything is configured as code and can be managed in version control systems like Git. Define your desired infrastructure state once in configuration files, and Keystone maintains it across different hardware and network environments. This goes beyond traditional disaster recovery—it enables live migration of services between bare-metal and cloud infrastructure as needs change.

**Flexible Resource Sharing**: Share compute and storage resources within trusted groups (family, friends, business partners) while maintaining security boundaries and resource limits.

## Getting Started

- [Installation Guide](docs/installation.md) - Complete installation process from ISO generation to first boot

# Infrastructure

At the most macro scale one could expect to have two clients 1 mobile phone and 1 desktop or laptop and a single baremetal or VPS server. The server though should have a public IP address though later we should support using another entities public ip address for ingress and egress. 

- raspberry pi or nuc attached to their home router with an external HDD as a server
- VPS on AWS, Vultr etc
  - using cheap storage for backups

The user can host a DNS server that blocks ads and trackers which their laptop client could take advantage of. Their laptop remotely backups to this device.

The server ideally is battery backed up but also configured to automatically restart anytime power is applied.

All devices use a TPM to store an encryption key that unlocks the root disk as long as hardware and bootloader attestations are verified.


Desktop and Laptop clients use Hyprland.  

Users typically have the following hardware.

- Laptop
- Workstation
- Server
  - Router
  - NAS

---

Typically these services are needed

- VPN
- Backups
- Compute

---

Workstation

---

Multiple ZFS Backup Targets distributed 

---

Windows TPM Pass Through

---

Home User Share with Friends and Family
Organization share with other founders/board/engineers members
