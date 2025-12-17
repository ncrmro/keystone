# Data Model: ZFS User Module Options

**Feature**: 007-zfs-user-module
**Date**: 2025-11-04

This document defines the NixOS module options schema for the ZFS User Module.

---

## Module Option Namespace

```
keystone.users
```

---

## Option Hierarchy

```nix
keystone.users = {
  <username> = {
    uid = <int>;
    description = <string>;
    extraGroups = [<string>];
    initialPassword = <string>;  # optional
    hashedPassword = <string>;   # optional
    zfsProperties = {
      quota = <string>;          # optional
      compression = <string>;     # optional
      recordsize = <string>;      # optional
      atime = <string>;           # optional
    };
  };
};
```

**Note**: The module automatically detects when users have `zfsProperties` defined and provisions ZFS datasets. No separate enable flag required.

---

## Option Definitions

### `keystone.users.<name>`

**Type:** `types.attrsOf (types.submodule)`
**Default:** `{}`
**Description:** Attribute set of users to create with ZFS-backed home directories.

**Structure:** Each attribute name is the username, and the value is a submodule defining user properties.

---

## User Submodule Options

### `keystone.users.<name>.uid`

**Type:** `types.int`
**Default:** None (required)
**Description:** User ID for the system user.

**Validation:**
- Must be unique across all users
- Typically 1000+ for regular users
- Module adds assertion to check uniqueness

**Example:**
```nix
keystone.users.alice.uid = 1000;
```

---

### `keystone.users.<name>.description`

**Type:** `types.str`
**Default:** `""`
**Description:** Full name or description of the user (GECOS field).

**Example:**
```nix
keystone.users.alice.description = "Alice Smith";
```

---

### `keystone.users.<name>.extraGroups`

**Type:** `types.listOf types.str`
**Default:** `[]`
**Description:** Additional groups the user should be a member of.

**Common Groups:**
- `wheel`: Administrative privileges (sudo)
- `networkmanager`: Network management
- `audio`: Audio device access
- `video`: Video device access

**Example:**
```nix
keystone.users.alice.extraGroups = [ "wheel" "networkmanager" ];
```

---

### `keystone.users.<name>.initialPassword`

**Type:** `types.nullOr types.str`
**Default:** `null`
**Description:** Initial password for the user (plaintext). **Warning:** Stored in Nix store, visible to all users. Use `hashedPassword` for production.

**Example:**
```nix
keystone.users.alice.initialPassword = "changeme";
```

---

### `keystone.users.<name>.hashedPassword`

**Type:** `types.nullOr types.str`
**Default:** `null`
**Description:** Hashed password for the user (generated with `mkpasswd`).

**Generation:**
```bash
mkpasswd -m sha-512
```

**Example:**
```nix
keystone.users.alice.hashedPassword = "$6$rounds=656000$...";
```

---

### `keystone.users.<name>.zfsProperties`

**Type:** `types.submodule`
**Default:** `{}`
**Description:** ZFS properties to set on the user's home dataset.

---

## ZFS Properties Submodule

### `keystone.users.<name>.zfsProperties.quota`

**Type:** `types.nullOr types.str`
**Default:** `null`
**Description:** Storage quota for the user (includes all child datasets and snapshots).

**Format:** Number with unit suffix (K, M, G, T, P)

**Example:**
```nix
keystone.users.alice.zfsProperties.quota = "100G";
```

---

### `keystone.users.<name>.zfsProperties.compression`

**Type:** `types.str`
**Default:** `"lz4"`
**Description:** Compression algorithm for the dataset.

**Valid Values:**
- `"off"`: No compression
- `"lz4"`: Fast compression (recommended)
- `"zstd"`: Better compression, more CPU
- `"gzip"`, `"gzip-1"` through `"gzip-9"`: Slower, higher compression

**Example:**
```nix
keystone.users.alice.zfsProperties.compression = "lz4";
```

---

### `keystone.users.<name>.zfsProperties.recordsize`

**Type:** `types.nullOr types.str`
**Default:** `null` (inherits ZFS default of 128K)
**Description:** Block size for the dataset. Optimize based on workload.

**Guidelines:**
- `"128K"`: Default, good for general use
- `"1M"`: Large files (videos, ISOs)
- `"16K"` or `"32K"`: Databases, small files

**Example:**
```nix
keystone.users.alice.zfsProperties.recordsize = "128K";
```

---

### `keystone.users.<name>.zfsProperties.atime`

**Type:** `types.enum ["on" "off"]`
**Default:** `"off"`
**Description:** Whether to update access time on file reads.

**Performance:**
- `"off"`: Better performance (recommended)
- `"on"`: Track access times (rarely needed)

**Example:**
```nix
keystone.users.alice.zfsProperties.atime = "off";
```

---

## Complete Configuration Example

```nix
{
  keystone.users = {
    alice = {
      uid = 1000;
      description = "Alice Smith";
      extraGroups = [ "wheel" "networkmanager" ];
      hashedPassword = "$6$rounds=656000$...";
      zfsProperties = {
        quota = "100G";
        compression = "lz4";
        recordsize = "128K";
        atime = "off";
      };
    };

    bob = {
      uid = 1001;
      description = "Bob Jones";
      extraGroups = [ "audio" "video" ];
      zfsProperties = {
        quota = "50G";
        compression = "zstd";
      };
    };

    charlie = {
      uid = 1002;
      description = "Charlie Brown";
      extraGroups = [ "wheel" ];
      initialPassword = "changeme";  # Dev/test only
      zfsProperties = {
        quota = "200G";
        compression = "lz4";
        recordsize = "1M";  # Large file workload
      };
    };
  };
}
```

---

## Module Assertions

The module will include the following runtime assertions:

### Pool Existence
```nix
{
  assertion = config.boot.supportedFilesystems or [] == ["zfs"] ||
              elem "zfs" config.boot.supportedFilesystems;
  message = "ZFS must be enabled (boot.supportedFilesystems must include 'zfs')";
}
```

### Parent Dataset Validation
```nix
{
  assertion = cfg.enable -> (builtins.match "^[^/]+/.*" cfg.parentDataset != null);
  message = "parentDataset must be a child dataset (e.g., 'rpool/crypt/home'), not a pool root";
}
```

### UID Uniqueness
```nix
{
  assertion =
    let
      uids = lib.mapAttrsToList (_: u: u.uid) cfg.users;
      uniqueUids = lib.unique uids;
    in
    length uids == length uniqueUids;
  message = "All user UIDs must be unique";
}
```

---

## Generated NixOS Configuration

When the module is enabled, it generates the following in the NixOS configuration:

### Standard Users

```nix
users.users = {
  alice = {
    isNormalUser = true;
    uid = 1000;
    description = "Alice Smith";
    home = "/home/alice";
    createHome = false;  # ZFS dataset is the home
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "$6$...";
  };
  # ... other users
};
```

### Systemd Service

```nix
systemd.services.zfs-user-datasets = {
  description = "Create ZFS datasets for user home directories";
  wantedBy = ["multi-user.target"];
  after = ["zfs-mount.service"];
  before = ["display-manager.service" "systemd-user-sessions.service"];
  requires = ["zfs-mount.service"];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = ''
    # Dataset creation, property setting, permission delegation
    # (see research.md for implementation details)
  '';
};
```

---

## ZFS Delegation Permissions

Users automatically receive the following ZFS permissions on their home dataset:

**Standard Permissions:**
- `create`: Create child datasets
- `snapshot`: Create snapshots
- `rollback`: Rollback to snapshots
- `diff`: Compare snapshots
- `send`: Send snapshots (backup)
- `receive`: Receive snapshots (restore)
- `hold`: Hold snapshots
- `release`: Release held snapshots
- `bookmark`: Create bookmarks

**Property Permissions:**
- `compression`: Change compression algorithm
- `quota`: Set storage quotas
- `refquota`: Set quotas excluding snapshots
- `recordsize`: Change block size
- `atime`: Control access time updates
- `readonly`: Make datasets read-only
- `userprop`: Set custom properties

**Restricted Permissions:**
- `destroy`: Only on descendants (cannot destroy parent home dataset)

**Example Delegation Commands (generated by module):**
```bash
zfs allow -u alice \
  create,snapshot,rollback,diff,send,receive,hold,release,bookmark,\
  compression,quota,refquota,recordsize,atime,readonly,userprop \
  rpool/crypt/home/alice

zfs allow -d -u alice destroy rpool/crypt/home/alice
```

---

## Data Flow

1. **Configuration Phase:**
   - Administrator defines users in `keystone.users`
   - Nix evaluates configuration, checks assertions

2. **Build Phase:**
   - Module generates systemd service script
   - Module generates users.users configuration

3. **Activation Phase (first boot):**
   - systemd starts `zfs-user-datasets.service`
   - Service validates pool and parent dataset exist
   - Service creates user datasets with `zfs create -p`
   - Service sets ZFS properties with `zfs set`
   - Service grants permissions with `zfs allow`
   - Service completes, users can log in

4. **Update Phase (nixos-rebuild):**
   - Service does NOT re-run (RemainAfterExit=true)
   - Changes to properties take effect next boot
   - New users get datasets created on next boot

---

## State Management

### Idempotency

All operations are idempotent:
- `zfs create -p`: No-op if dataset exists
- `zfs set`: Safe to re-run, updates properties
- `zfs allow`: Safe to re-run, grants permissions

### User Removal

**Removing a user from configuration does NOT delete their dataset.**

To fully remove a user:
```bash
# 1. Remove from configuration, rebuild
nixos-rebuild switch

# 2. Manually destroy dataset (as root)
zfs destroy -r rpool/crypt/home/alice
```

This prevents accidental data loss.

### Property Changes

Changing ZFS properties in configuration:
```nix
# Before
alice.zfsProperties.quota = "100G";

# After
alice.zfsProperties.quota = "200G";
```

**Effect:** Property is updated on next boot (or immediately if service is restarted).

---

## Validation Rules

| Field | Validation | Error Message |
|-------|------------|---------------|
| `enable` | Boolean | N/A |
| `poolName` | Non-empty string | "poolName cannot be empty" |
| `parentDataset` | Must contain `/` | "parentDataset must be a child dataset path" |
| `users.<name>.uid` | Positive integer | "UID must be positive" |
| `users.<name>.uid` | Unique across users | "UIDs must be unique" |
| `zfsProperties.quota` | Valid ZFS size format | "Invalid quota format (use 100G, 1T, etc.)" |
| `zfsProperties.compression` | Valid algorithm | "Unknown compression algorithm" |

---

## Related Files

- **Implementation:** `modules/users/default.nix`
- **Tests:** `bin/test-deployment` (ZFS user verification section)
- **Documentation:** `specs/007-zfs-user-module/quickstart.md`

---

## Next Steps

After data model definition:
1. Generate quickstart.md with usage examples
2. Update agent context with module structure
3. Proceed to Phase 2 task generation (/speckit.tasks)
