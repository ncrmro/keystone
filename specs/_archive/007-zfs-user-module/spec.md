# Feature Specification: ZFS User Module

**Feature ID**: 007-zfs-user-module
**Status**: Planning
**Created**: 2025-11-04

## Overview

A NixOS module that creates user accounts with home directories backed by individual ZFS datasets. Each user will have permissions to manage their own ZFS dataset, enabling snapshots, dataset management, and quota control.

## User Requirements

As a system administrator, I want to:
- Create user accounts that automatically get ZFS-backed home directories
- Grant users permissions to manage their own ZFS datasets (snapshots, quotas, etc.)
- Ensure proper ZFS dataset organization and naming conventions
- Maintain security isolation between user datasets
- Verify this functionality in automated deployment tests

## Functional Requirements

1. **User Creation**: The module MUST create standard NixOS user accounts with specified attributes
2. **ZFS Dataset Creation**: For each user, the module MUST create a dedicated ZFS dataset at `rpool/crypt/home/<username>`
3. **Automatic Mounting**: User datasets MUST be automatically mounted to `/home/<username>` at boot
4. **ZFS Permissions**: Users MUST be granted ZFS delegation permissions for their own datasets, including:
   - Child dataset creation and deletion (`create`, `destroy`)
   - Snapshot creation/deletion (`snapshot`, `destroy`)
   - Dataset property modification (`compression`, `quota`, etc.)
   - Space monitoring (`list`, `diff`)
   - Send/receive operations (`send`, `receive`) for backup and replication
   - Mount/unmount operations (`mount`, `unmount`)
   - All other necessary permissions to fully manage their dataset tree
5. **Dataset Properties**: The module SHOULD support configuring default ZFS properties per user (compression, quota, recordsize, etc.)
6. **Existing Pool Integration**: The module MUST work with the existing `rpool` pool from the disko-single-disk-root module
7. **Test Integration**: The module MUST include verification checks in `bin/test-deployment`

## Non-Functional Requirements

1. **Security**: Users MUST NOT have permissions to access other users' datasets
2. **Idempotence**: Re-applying the configuration MUST NOT destroy existing user data
3. **Performance**: Dataset creation MUST complete within system activation time
4. **Composability**: The module MUST integrate seamlessly with existing Keystone modules (server, client)
5. **Testability**: Module functionality MUST be verifiable in automated deployment testing

## Technical Constraints

1. Must use NixOS module system conventions
2. Must integrate with existing `rpool` ZFS pool
3. Must work with both encrypted and unencrypted ZFS pools
4. Must handle ZFS delegation permissions correctly
5. Must validate that ZFS is available and pool exists before attempting operations
6. Must use systemd activation scripts for dataset creation and permission assignment

## Out of Scope

- Creating new ZFS pools (uses existing rpool)
- Migrating existing users to ZFS datasets
- Backup/replication configuration
- ZFS encryption per-user dataset (relies on pool-level encryption)
- Home-manager integration

## Success Criteria

1. Users can create child datasets within their home directory
2. Users can create snapshots of their home directories using `zfs snapshot`
3. Users can check their disk usage with `zfs list`
4. Users can modify their dataset properties (within delegated permissions)
5. Users can send and receive snapshots for backup/restore operations
6. Users can delete their own datasets and snapshots
7. The module can be enabled in any Keystone configuration (server or client)
8. `bin/test-deployment` includes automated checks for ZFS user functionality
9. Documentation includes examples for common user ZFS operations including backup workflows

## Examples

```nix
# In a NixOS configuration
{
  keystone.users = {
    alice = {
      uid = 1000;
      description = "Alice Smith";
      extraGroups = [ "wheel" ];
      zfsProperties = {
        quota = "100G";
        compression = "lz4";
      };
    };
    bob = {
      uid = 1001;
      description = "Bob Jones";
      zfsProperties = {
        quota = "50G";
      };
    };
  };
}
```

## Test Verification

The `bin/test-deployment` script includes automated checks for (7 active tests):
1. ✅ ZFS dataset exists at `rpool/crypt/home/<username>`
2. ✅ Dataset is mounted at `/home/<username>`
3. ⏸️ User can create child datasets - COMMENTED OUT (Linux kernel mount restriction, see GitHub #10648)
4. ✅ User can create snapshots (`zfs snapshot rpool/crypt/home/<username>@test`)
5. ✅ User can list their dataset (`zfs list rpool/crypt/home/<username>`)
6. ✅ User can send/receive snapshots for backup purposes
7. ✅ User can delete snapshots
8. ⏸️ User can delete child datasets - COMMENTED OUT (dependent on #3)
9. ✅ User cannot destroy parent dataset (security check)

**Note**: Tests 3 and 8 are commented out due to Linux kernel restrictions on non-root filesystem mounting. See research.md for details and workarounds.

## References

- ZFS delegation: `man zfs-allow`
- NixOS users/groups: https://nixos.org/manual/nixos/stable/#sec-user-management
- Keystone disko module: modules/disko-single-disk-root/default.nix
- Deployment testing: bin/test-deployment
