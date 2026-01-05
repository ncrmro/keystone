# Plan: Self-Contained Deploy with Project SSH Config

## Goal

Make deployment fully self-contained using a project-local SSH config file with `ssh -F`.

## Key Insight

SSH's `-F` flag specifies an alternate config file. Combined with `NIX_SSHOPTS`, we can use a project-local config:

```bash
export NIX_SSHOPTS="-F ${SCRIPT_DIR}/ssh/config"
nixos-rebuild --builders "ssh://nixbuilder aarch64-linux" ...
```

This avoids:
- Modifying `~/.ssh/config`
- Known issues with inline `-J` and `NIX_SSHOPTS`
- Complex nested SSH scripts

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Linux Workstation (runs nixos-rebuild)                                      │
│                                                                             │
│  ./scripts/deploy.sh                                                        │
│       │                                                                     │
│       │ NIX_SSHOPTS="-F ./ssh/config"                                       │
│       │ nixos-rebuild --builders "ssh://nixbuilder" --target-host macbook   │
│       │                                                                     │
│       ├─────── ProxyJump (via ssh/config) ───────┐                          │
│       │                                          │                          │
│       │                                          ▼                          │
│       │    ┌─────────────────────────────────────────────────────────────┐  │
│       │    │ Mac Pro (nicholas@unsup-16-pro.local)                       │  │
│       │    │                                                             │  │
│       │    │  ┌─────────────────────────────────────────────────────┐   │  │
│       │    │  │ OrbStack VM (nixbuilder) - aarch64-linux            │   │  │
│       │    │  │                                                     │   │  │
│       │    │  │  • Native ARM compilation (no emulation!)           │   │  │
│       │    │  │  • NixOS with flakes enabled                        │   │  │
│       │    │  └─────────────────────────────────────────────────────┘   │  │
│       │    └─────────────────────────────────────────────────────────────┘  │
│       │                                                                     │
│       └─────── Direct SSH ───────────┐                                      │
│                                      ▼                                      │
│       ┌─────────────────────────────────────────────────────────────────┐   │
│       │ MacBook Air (root@192.168.1.64) - Asahi Linux                   │   │
│       └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Changes Required

| File | Action |
|------|--------|
| `ssh/config` | Rename from `config.example`, full working config |
| `scripts/deploy.sh` | Use `NIX_SSHOPTS="-F ./ssh/config"` |
| `scripts/test-builder.sh` | Use `ssh -F ./ssh/config` |
| `README.md` | Update to explain project-local config |

### `ssh/config` - Project-Local SSH Config

```ssh
# Project-local SSH config for Keystone Apple Silicon deployment
# Used via: ssh -F ./ssh/config nixbuilder

Host nixbuilder
  HostName nixbuilder.orb.local
  User root
  ProxyJump nicholas@unsup-16-pro.local
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new

Host macbook
  HostName 192.168.1.64
  User root
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
```

### `scripts/deploy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="${SCRIPT_DIR}/ssh/config"
FLAKE_TARGET="${1:-.#macbook}"
TARGET_HOST="${TARGET_HOST:-macbook}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Keystone Deploy - Apple Silicon                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Builder: nixbuilder (via Mac Pro)"
echo "  Target:  ${TARGET_HOST}"
echo "  Flake:   ${FLAKE_TARGET}"
echo "  Config:  ${SSH_CONFIG}"
echo ""

cd "$SCRIPT_DIR"

# Use project-local SSH config for all Nix SSH operations
export NIX_SSHOPTS="-F ${SSH_CONFIG}"

nixos-rebuild switch \
    --flake "${FLAKE_TARGET}" \
    --target-host "${TARGET_HOST}" \
    --builders "ssh://nixbuilder aarch64-linux" \
    --max-jobs 0 \
    --use-remote-sudo

echo ""
echo "✓ Deployment complete!"
echo "Connect with: ssh -F ${SSH_CONFIG} ${TARGET_HOST}"
```

### `scripts/test-builder.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="${SCRIPT_DIR}/ssh/config"

echo "=== Testing Remote Builder ==="
echo "Using SSH config: ${SSH_CONFIG}"
echo ""

echo "1. SSH to nixbuilder (via Mac Pro)..."
ssh -F "${SSH_CONFIG}" nixbuilder echo "OK"

echo "2. Nix version on builder..."
ssh -F "${SSH_CONFIG}" nixbuilder nix --version

echo "3. Remote build test..."
NIX_SSHOPTS="-F ${SSH_CONFIG}" \
    nix build --builders "ssh://nixbuilder aarch64-linux" \
    --max-jobs 0 nixpkgs#hello --no-link

echo ""
echo "✓ All tests passed!"
```

## Benefits

1. **Zero global config** - No `~/.ssh/config` changes
2. **Portable** - Config travels with the project
3. **Reliable** - Uses SSH config (recommended approach) without global changes
4. **Explicit** - All settings visible in `ssh/config`

## Prerequisites (Already Done)

These were completed in a previous session:
- ✅ OrbStack installed on Mac Pro
- ✅ NixOS VM `nixbuilder` created
- ✅ SSH enabled in VM with `lib.mkForce true`
- ✅ Flakes enabled in VM
- ✅ SSH keys set up (Mac Pro → VM)

## Usage

```bash
# Test connectivity
./scripts/test-builder.sh

# Deploy to MacBook
./scripts/deploy.sh

# Deploy specific flake target
./scripts/deploy.sh .#my-custom-config
```
