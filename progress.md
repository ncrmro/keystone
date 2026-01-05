# macOS Remote Builder Template - Progress

## Current State: Remote Builder Connection Issue

### What's Working
1. **SSH connectivity** - All SSH connections work via project-local `ssh/config`:
   - Workstation → Mac Pro ✅
   - Workstation → nixbuilder (via ProxyJump) ✅
   - Workstation → MacBook ✅

2. **Flake configuration** - All required inputs and modules configured:
   - Added `hyprland`, `walker`, `elephant`, `omarchy` inputs
   - Added `specialArgs` and `extraSpecialArgs` for passing inputs
   - Applied `keystone.overlays.default` for `pkgs.keystone.claude-code`
   - Removed duplicate terminal module from sharedModules

3. **Asahi firmware handling** - Using `extractPeripheralFirmware = false`:
   - No more `/boot/asahi` path error
   - Enables pure remote builds without `--impure`
   - Documented in README with alternatives

4. **Hardware configuration** - Updated with MacBook's actual disk config:
   - Root: `/dev/disk/by-label/nixos`
   - Boot: `/dev/disk/by-partuuid/456551a3-4160-44c0-8763-b5dd56969569`

### Current Blocker

**Error**: `Failed to find a machine for remote build!`

The build evaluates successfully (545 derivations identified) but fails to dispatch builds to nixbuilder.

**Root cause**: The local Nix daemon doesn't trust the current user to specify `--builders`:
```
warning: ignoring the client-specified setting 'builders', because it is a restricted setting and you are not a trusted user
```

**Solution needed**: Add current user to `trusted-users` in `/etc/nix/nix.conf` on the Linux workstation:
```nix
# /etc/nix/nix.conf or via NixOS configuration
trusted-users = root @wheel ncrmro
```

Then restart nix-daemon: `sudo systemctl restart nix-daemon`

### Files Modified

| File | Changes |
|------|---------|
| `flake.nix` | Added inputs, overlay, specialArgs, extraSpecialArgs |
| `configuration.nix` | Added `hardware.asahi` with `extractPeripheralFirmware = false`, `allowUnsupportedSystem = true` |
| `hardware-configuration.nix` | Updated with actual MacBook disk UUIDs |
| `scripts/deploy.sh` | Reverted to simple architecture (no rsync approach) |
| `README.md` | Updated architecture diagram, added firmware handling docs, linked issue #172 |

### Key Research

From [nixos-apple-silicon issue #172](https://github.com/nix-community/nixos-apple-silicon/issues/172):

| Approach | Remote Build | Pure Evaluation | Reproducible |
|----------|--------------|-----------------|--------------|
| `extractPeripheralFirmware = false` | ✅ Yes | ✅ Yes | ✅ Yes |
| `--impure` with `/boot/asahi` | ❌ No* | ❌ No | ❌ No |
| Copy firmware to repo | ✅ Yes | ✅ Yes | ✅ Yes |

*Remote builds with `--impure` require the firmware path to exist on the machine running `nix build`.

### Next Steps

1. **Fix trusted-users** - Add user to trusted-users on Linux workstation
2. **Test deploy** - Run `./scripts/deploy.sh` after nix-daemon restart
3. **Handle gpu-screen-recorder** - Currently using `allowUnsupportedSystem = true` as workaround; should fix in Keystone desktop module with platform checks

### Architecture (Working)

```
Linux Workstation ──nixos-rebuild──▶ nixbuilder (via ProxyJump) ──builds──▶
                                                                          │
Linux Workstation ──────────────────────────────────────────deploys───────▶ MacBook Air
```

### Test Commands

```bash
# Test SSH connectivity
./scripts/test-builder.sh

# Test deploy (after fixing trusted-users)
./scripts/deploy.sh

# Manual SSH to machines
ssh -F ssh/config nixbuilder
ssh -F ssh/config macbook
```
