#!/usr/bin/env bash
# Test remote builder connectivity using project-local SSH config
#
# This script uses ssh/config in the project directory, avoiding
# any modifications to ~/.ssh/config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="${SCRIPT_DIR}/ssh/config"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           Testing Remote Builder (via ProxyJump)               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Using SSH config: ${SSH_CONFIG}"
echo ""

# Test 1: SSH to builder
echo "1. Testing SSH to nixbuilder (via Mac Pro)..."
if ssh -F "${SSH_CONFIG}" -o ConnectTimeout=10 nixbuilder echo "OK" 2>/dev/null; then
    pass "SSH to nixbuilder"
else
    fail "Cannot SSH to nixbuilder. Check ssh/config has correct ProxyJump settings."
fi

# Test 2: Nix version
echo "2. Testing Nix on builder..."
NIX_VERSION=$(ssh -F "${SSH_CONFIG}" nixbuilder nix --version 2>/dev/null || echo "FAILED")
if [[ "$NIX_VERSION" != "FAILED" ]]; then
    pass "Nix on builder: $NIX_VERSION"
else
    fail "Nix not working on builder"
fi

# Test 3: Remote build
echo "3. Testing remote build (nixpkgs#hello)..."
if NIX_SSHOPTS="-F ${SSH_CONFIG}" nix build \
    --builders "ssh://nixbuilder aarch64-linux" \
    --max-jobs 0 \
    nixpkgs#hello \
    --no-link 2>/dev/null; then
    pass "Remote build succeeded"
else
    fail "Remote build failed"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${GREEN}All tests passed!${NC} Ready to deploy with ./scripts/deploy.sh"
