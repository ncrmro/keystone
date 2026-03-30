# Release Context for Keystone

## Versioning

Keystone uses semantic versioning. The ROADMAP.md originally used `v0.0.x` for feature milestones, but this is incorrect — patch versions are for bug/security fixes only.

**Correct mapping of ROADMAP milestones to semver:**

| ROADMAP Label         | Correct Version | Content                              |
| --------------------- | --------------- | ------------------------------------ |
| Secure Foundation     | v0.1.0          | ZFS, LUKS, TPM, Secure Boot, desktop |
| Developer Environment | v0.2.0          | Home-manager, remote dev             |
| Workstation Desktop   | v0.3.0          | Remote desktop, multi-monitor        |
| Universal Development | v0.4.0          | Portable config, Codespaces, macOS   |
| Production            | v1.0.0          | Backups, monitoring, secrets, DR     |

**Rules:**

- **Patch (0.x.Y)**: Bug fixes and security patches ONLY
- **Minor (0.Y.0)**: New features and capabilities (most milestones)
- **Major (Y.0.0)**: Breaking changes requiring migration

## Conventions

- Release artifacts stored in `releases/[version]/` — see `releases/0.1.0/` for the established pattern
- CHANGELOG.md at repo root follows Keep a Changelog format
- Tags use `v` prefix: `v0.1.0`, `v0.2.0`, etc.
- Pre-1.0 releases are alpha channel

## Last Updated

- Date: 2026-03-03
- From conversation about: First release workflow test run — versioning correction learning
