# Test Fixtures

This directory contains test-only credentials for automated testing of Keystone cluster components.

**WARNING: These keys are committed to the repository for reproducible testing. DO NOT use them in production!**

## SSH Keys

- `test-ssh-key` - ED25519 private key for SSH access to test microVMs
- `test-ssh-key.pub` - Corresponding public key

Used by:
- `tests/microvm/cluster-primer.nix`
- `tests/microvm/cluster-worker.nix`
- `bin/test-cluster-microvm`

## Agenix Secrets

These encrypted secrets are used to test the agenix secret management flow:

- `test-age-key.txt` - Age identity for decrypting secrets (test-only)
- `headscale-private.age` - Headscale private key (encrypted)
- `headscale-noise.age` - Headscale noise private key (encrypted)
- `headscale-derp.age` - Headscale DERP private key (encrypted)
- `secrets.nix` - Agenix secret definitions

Used by:
- `tests/microvm/cluster-primer.nix` (decrypts secrets via agenix)
- `modules/cluster/primer/headscale.nix` (creates K8s secrets from decrypted files)

## Regenerating Keys

### SSH Keys
```bash
ssh-keygen -t ed25519 -f tests/fixtures/test-ssh-key -N "" -C "keystone-test"
```

### Agenix Secrets
```bash
# Generate new age key
age-keygen -o tests/fixtures/test-age-key.txt

# Re-encrypt secrets with the new key
cd tests/fixtures
agenix -r -i test-age-key.txt
```
