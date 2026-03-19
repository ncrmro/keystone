# Keystone TODOs

- [ ] **Establish UID Conventions**: Formalize and document UID ranges for different user types across Keystone to prevent collisions and keep `id` outputs clean.
  - **Humans**: `1000 - 2999` (Standard NixOS/Linux default)
  - **Services**: `3000 - 3999` (For services that require `isNormalUser = true` for features like subuids or systemd linger, e.g., `gitea-runner`)
  - **Agents**: `4000+` (Currently implemented via `agentUidBase` in `os/agents/lib.nix`)