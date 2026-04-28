---
title: 1Password Integration
description: First-class 1Password CLI, SSH agent, and git signing integration for Keystone
---

# 1Password Integration

Keystone provides a first-class 1Password integration with feature parity to the
self-hosted [Vaultwarden](../server.md) path. Choose 1Password for a managed cloud
service with biometric unlock and a polished desktop experience; choose Vaultwarden
when you want full self-hosted control with no vendor dependency.

## Prerequisites

- A [1Password](https://1password.com/) account (individual, family, or Teams/Business)
- The 1Password desktop app installed and signed in on each machine that needs the SSH agent or biometric unlock
- NixOS (the `keystone.os.onePassword` module) or any system where `programs._1password` is available

---

## NixOS Module — System-Level Integration

The `keystone.os.onePassword` module handles:

- Installing the `op` CLI with correct setuid bits (`programs._1password`)
- Optionally installing the 1Password GUI and configuring polkit for biometric unlock and browser extension auto-fill

Add to your NixOS host configuration:

```nix
keystone.os.onePassword = {
  enable = true;          # installs op CLI

  gui = {
    enable = true;        # installs 1Password.app + op-ssh-sign
    polkitPolicyOwners = [ "alice" ];  # users allowed polkit integration
  };
};
```

> **Note:** `polkitPolicyOwners` is required for the browser extension and
> biometric (fingerprint/Touch ID) unlock to work. Add every username that will
> use 1Password on this machine.

### Standalone flake import

If you only want the 1Password module without the full `operating-system` bundle:

```nix
# flake.nix
{
  inputs.keystone.url = "github:ncrmro/keystone";

  outputs = { keystone, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      modules = [
        keystone.nixosModules.onePassword
        {
          keystone.os.onePassword = {
            enable = true;
            gui.enable = true;
            gui.polkitPolicyOwners = [ "alice" ];
          };
        }
      ];
    };
  };
}
```

---

## Home-Manager Module — User-Level Integration

The `keystone.terminal.onePassword` module is part of `keystone.terminal` and
handles:

- Installing the `op` CLI in the user environment
- Setting `SSH_AUTH_SOCK` to the 1Password agent socket
- Configuring `~/.ssh/config` with `IdentityAgent`
- Wiring `op-ssh-sign` as the git SSH signing program

```nix
# In your home-manager config (or via keystone.terminal):
keystone.terminal = {
  enable = true;

  onePassword = {
    enable = true;
    # sshAgent.enable = true;    (default)
    # gitSigning.enable = true;  (default)
  };

  git = {
    enable     = true;
    userName   = "Alice Smith";
    userEmail  = "alice@example.com";
    signingKey = "key::ssh-ed25519 AAAAC3Nz... alice@example.com";
  };
};
```

### SSH agent

When `sshAgent.enable = true` (the default), the module:

1. Sets `SSH_AUTH_SOCK=$HOME/.1password/agent.sock` in `home.sessionVariables`
2. Adds `IdentityAgent ~/.1password/agent.sock` under a `Host *` block in `~/.ssh/config`

The 1Password app must be running and its SSH agent enabled
(**Settings → Developer → Use the SSH agent**).

### Git commit/tag signing

When `gitSigning.enable = true` (the default) and `keystone.terminal.git.enable = true`,
the module sets:

```
gpg.ssh.program = /nix/store/.../bin/op-ssh-sign
```

Set `keystone.terminal.git.signingKey` to the public key of the SSH key stored
in your 1Password vault (use `key::` prefix for inline keys):

```nix
keystone.terminal.git = {
  signingKey = "key::ssh-ed25519 AAAAC3Nz... alice@example.com";
};
```

Every commit and tag will prompt the 1Password app (once per session with
biometrics enabled).

### Opting out of sub-features

```nix
keystone.terminal.onePassword = {
  enable        = true;
  sshAgent.enable   = false;  # keep op CLI but use default ssh-agent
  gitSigning.enable = false;  # manage git signing separately
};
```

---

## Authentication Modes

| Mode                     | How it works                                                                    | Requires          |
| ------------------------ | ------------------------------------------------------------------------------- | ----------------- |
| **Biometric (Touch ID)** | 1Password app unlocks via fingerprint/Face ID; no master password per session   | GUI + polkit      |
| **Master password**      | Enter master password once; vault stays unlocked for the session                | CLI or GUI        |
| **Service account**      | Non-interactive token for CI/agents (`OP_SERVICE_ACCOUNT_TOKEN` env var)        | CLI only          |

For desktop users, biometric unlock is strongly recommended — enable `gui.enable = true`
and add yourself to `polkitPolicyOwners`.

---

## Parity vs Self-Hosted Vaultwarden

| Capability                     | 1Password (this module)              | Vaultwarden (`keystone.terminal.secrets`) |
| ------------------------------ | ------------------------------------ | ----------------------------------------- |
| **Secret retrieval (CLI)**     | ✅ `op read op://vault/item/field`   | ✅ `rbw get "item"`                       |
| **SSH key agent**              | ✅ Built into 1Password GUI          | ⚠️ Requires separate `ssh-agent`          |
| **SSH commit signing**         | ✅ `op-ssh-sign` (GUI package)       | ⚠️ Manual key + `ssh-add`                 |
| **Git tag signing**            | ✅ Same as above                     | ⚠️ Manual key + `ssh-add`                 |
| **Browser auto-fill**          | ✅ Native browser extension          | ✅ Bitwarden browser extension            |
| **Desktop biometric unlock**   | ✅ Touch ID / fingerprint via polkit | ❌ Not supported                          |
| **Self-hosted / air-gapped**   | ❌ Cloud service only                | ✅ Full self-host with Vaultwarden        |
| **Cost**                       | 💰 Subscription (~$3/mo individual) | 🆓 Free (server infra cost only)          |
| **Mobile app**                 | ✅ iOS + Android                     | ✅ Bitwarden mobile apps                  |
| **TOTP / 2FA codes**           | ✅ Built-in                          | ✅ Built-in                               |
| **Passkeys**                   | ✅ Supported                         | ⚠️ Limited (Vaultwarden ≥ 1.30)          |
| **Teams / sharing**            | ✅ Native teams vaults               | ⚠️ Manual org setup                      |
| **Secrets automation (CI)**    | ✅ Service accounts + op CLI         | ⚠️ Requires custom token handling        |

### Known gaps (1Password)

- **Air-gapped / self-hosted**: 1Password requires internet connectivity to sync vaults. Choose Vaultwarden if your threat model requires no external services.
- **op-ssh-sign on headless servers**: `op-ssh-sign` is shipped in `_1password-gui`. On headless NixOS servers where the GUI is not installed, you cannot use `op-ssh-sign` for git signing. Use a plain SSH key with `ssh-add` instead, or configure a 1Password service account with `op read` for secret injection.

### When to choose 1Password

- You already pay for 1Password or want a managed SaaS with zero ops overhead
- Biometric unlock and polished cross-platform apps matter to you
- You need Teams vaults with fine-grained sharing
- You want native passkey support out of the box

### When to choose Vaultwarden

- You prefer full data sovereignty with no vendor lock-in
- You run an existing Keystone server and want everything on-prem
- You need to keep secrets in an air-gapped environment
- Cost is a deciding factor

---

## Example Consumer Flake Snippet

Below is a minimal `nixos-config` flake showing both the NixOS and home-manager sides:

```nix
# nixos-config/flake.nix
{
  description = "My Keystone infrastructure";

  inputs = {
    nixpkgs.url  = "github:NixOS/nixpkgs/nixos-unstable";
    keystone.url = "github:ncrmro/keystone";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Full Keystone OS bundle (includes operating-system + terminal HM module)
        keystone.nixosModules.operating-system

        # 1Password system-level integration
        keystone.nixosModules.onePassword

        {
          # ── System ──────────────────────────────────────────────────
          networking.hostName = "workstation";

          keystone.os = {
            enable  = true;
            storage = { type = "zfs"; devices = [ "/dev/nvme0n1" ]; };
            users.alice = { fullName = "Alice Smith"; };
          };

          keystone.os.onePassword = {
            enable = true;
            gui = {
              enable             = true;
              polkitPolicyOwners = [ "alice" ];
            };
          };

          # ── Home Manager (per-user) ──────────────────────────────────
          home-manager.users.alice = {
            keystone.terminal = {
              enable = true;

              onePassword = {
                enable = true;
                # sshAgent.enable   = true;  (default)
                # gitSigning.enable = true;  (default)
              };

              git = {
                userName   = "Alice Smith";
                userEmail  = "alice@example.com";
                # Public key of the SSH key stored in 1Password vault:
                signingKey = "key::ssh-ed25519 AAAAC3Nz... alice@example.com";
                sshPublicKeys = [
                  "ssh-ed25519 AAAAC3Nz... alice@example.com"
                ];
              };
            };
          };
        }
      ];
    };
  };
}
```

---

## Troubleshooting

### SSH_AUTH_SOCK not set / agent not found

Ensure the 1Password desktop app is running and the SSH agent is enabled:
**1Password → Settings → Developer → Use the SSH agent**.

```bash
# Verify the socket exists
ls -la ~/.1password/agent.sock

# Check loaded keys
SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l
```

### op-ssh-sign: permission denied

The `op-ssh-sign` binary requires the 1Password GUI to be installed and the
user to be in `polkitPolicyOwners`. Re-check your NixOS configuration:

```nix
keystone.os.onePassword.gui.polkitPolicyOwners = [ "alice" ];
```

Then rebuild and verify:

```bash
sudo nixos-rebuild switch --flake .#workstation
/run/current-system/sw/bin/op-ssh-sign --version
```

### Git commits not signed

1. Check that `keystone.terminal.git.signingKey` is set to the correct public key.
2. Run `git log --show-signature` on a recent commit.
3. Ensure the signing key exists in your 1Password vault under **SSH Keys**.
4. Try signing manually: `echo test | op-ssh-sign -Y sign -f ~/.ssh/id_ed25519.pub -n git`.

### op CLI not on PATH

The `_1password-cli` package is added to `home.packages` by the terminal module.
If you are using the standalone `keystone.nixosModules.onePassword` NixOS module
without the terminal module, install `pkgs._1password-cli` in your system or user
packages manually.
