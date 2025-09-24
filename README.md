# keystone

Self Sovereign Infrastructure. Infrastructure consists of clients and servers. Clients are devices used by end users while 
servers provide services for any clients. All storage is encrypted both on the client and on remote backups. A distributed network for clients and services is made available via a VPN. Infrastructure belonging to one group (user, family, friends, business) should allow for shared allocation of resources (storage/compute), for example two or more business partners, family households, friends, states etc should be able to pool limit defined resources.

## Getting Started

- [ISO Generation](docs/iso-generation.md) - Create bootable USB with SSH keys for remote NixOS installation
- [Build Platforms](docs/build-platforms.md) - Platform-specific setup instructions

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
