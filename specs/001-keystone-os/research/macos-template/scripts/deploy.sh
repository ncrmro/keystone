#!/usr/bin/env bash
# Deploy NixOS to MacBook Air using OrbStack as remote builder
#
# Architecture:
#   This Machine ──nixos-rebuild──▶ nixbuilder (via ProxyJump) ──builds──▶
#                                                                         │
#   This Machine ──────────────────────────────────────────deploys────────▶ MacBook Air
#
# This script uses a project-local SSH config (ssh/config) to avoid
# modifying ~/.ssh/config. The -F flag tells SSH to use our config file.
#
# Usage:
#   ./scripts/deploy.sh                    # Deploy default configuration
#   ./scripts/deploy.sh .#my-config        # Deploy specific flake target
#
# Environment variables:
#   TARGET_HOST   - MacBook SSH host alias (default: macbook)

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
    --sudo

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Complete!                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Connect with: ssh -F ${SSH_CONFIG} ${TARGET_HOST}"
