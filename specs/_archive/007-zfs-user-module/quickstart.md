# Quick Start Guide: ZFS User Module

**Feature**: 007-zfs-user-module
**Audience**: System administrators using Keystone

This guide provides practical examples for using the ZFS User Module to create users with ZFS-backed home directories and delegated dataset management permissions.

---

## Prerequisites

1. **ZFS Enabled**: System must have ZFS support enabled
2. **Disko Module**: The disko-single-disk-root module must be configured (provides `rpool/crypt` dataset)
3. **NixOS 25.05+**: Compatible with Keystone's NixOS version

---

## Basic Usage

### Minimal Configuration

Create a single user with ZFS-backed home directory:

```nix
{
  # Enable the ZFS users module
  keystone.users = {
      alice = {
        uid = 1000;
        description = "Alice Smith";
        hashedPassword = "$6$rounds=656000$...";  # Generate with: mkpasswd -m sha-512
      };
  };
}
```

**What this does:**
- Creates user `alice` with UID 1000
- Creates ZFS dataset at `rpool/crypt/home/alice`
- Mounts dataset at `/home/alice`
- Grants Alice full ZFS management permissions on her home dataset
- Sets default ZFS properties (lz4 compression, no quota)

---

## Common Scenarios

### Scenario 1: Desktop Workstation (Single User)

```nix
{
  keystone.users = {
      myuser = {
        uid = 1000;
        description = "My Name";
        extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
        hashedPassword = "$6$...";

        zfsProperties = {
          quota = "500G";          # Limit home directory to 500GB
          compression = "lz4";     # Fast compression
          atime = "off";           # Better performance
        };
      };
  };
}
```

---

### Scenario 2: Multi-User Server

```nix
{
  keystone.users = {
      admin = {
        uid = 1000;
        description = "System Administrator";
        extraGroups = [ "wheel" ];  # sudo access
        hashedPassword = "$6$...";

        zfsProperties = {
          quota = "100G";
          compression = "lz4";
        };
      };

      developer1 = {
        uid = 1001;
        description = "Alice Developer";
        extraGroups = [ "developers" ];
        hashedPassword = "$6$...";

        zfsProperties = {
          quota = "200G";
          compression = "zstd";    # Better compression for code
          recordsize = "128K";
        };
      };

      developer2 = {
        uid = 1002;
        description = "Bob Developer";
        extraGroups = [ "developers" ];
        hashedPassword = "$6$...";

        zfsProperties = {
          quota = "200G";
          compression = "zstd";
        };
      };
  };
}
```

---

### Scenario 3: Media Server (Large Files)

```nix
{
  keystone.users = {
      media = {
        uid = 1000;
        description = "Media User";
        extraGroups = [ "audio" "video" ];
        hashedPassword = "$6$...";

        zfsProperties = {
          quota = "2T";             # 2TB for media files
          compression = "off";      # Don't compress already-compressed media
          recordsize = "1M";        # Optimize for large files
          atime = "off";            # Performance
        };
      };
  };
}
```

---

### Scenario 4: Development/Testing (Temporary Password)

**⚠️ WARNING:** Only use `initialPassword` for development/testing. Passwords are stored in plain text in the Nix store!

```nix
{
  keystone.users = {
      testuser = {
        uid = 1001;
        description = "Test User";
        initialPassword = "changeme";  # INSECURE - dev/test only!

        zfsProperties = {
          quota = "10G";           # Small quota for testing
        };
      };
  };
}
```

---

## User Workflows

### As a User: Managing Your Home Dataset

Once logged in, users can manage their ZFS datasets using standard ZFS commands:

#### Important: Linux Mount Limitation

**On Linux, only root can mount filesystems.** When you create child datasets, use `-o canmount=off` to avoid mount errors:

```bash
# Create datasets WITHOUT auto-mounting (recommended on Linux)
zfs create -o canmount=off rpool/crypt/home/alice/documents
zfs create -o canmount=off rpool/crypt/home/alice/projects

# To mount, ask your administrator or use sudo (if configured)
sudo zfs mount rpool/crypt/home/alice/documents
```

Alternatively, if you create without `canmount=off`, the dataset will be created but you'll see:
```
filesystem successfully created, but it may only be mounted by root
```

#### Create Child Datasets

Organize your home with separate datasets:

```bash
# Create datasets with canmount=off (Linux workaround)
zfs create -o canmount=off rpool/crypt/home/alice/documents
zfs create -o canmount=off rpool/crypt/home/alice/projects
zfs create -o canmount=off rpool/crypt/home/alice/photos

# Verify (datasets exist but may not be mounted)
zfs list | grep alice
```

#### Create Snapshots

Snapshot your home directory before major changes:

```bash
# Create a snapshot
zfs snapshot rpool/crypt/home/alice@before-upgrade

# List snapshots
zfs list -t snapshot | grep alice

# Rollback to snapshot (if needed)
zfs rollback rpool/crypt/home/alice@before-upgrade
```

#### Automated Daily Snapshots

```bash
# Create today's snapshot
zfs snapshot rpool/crypt/home/alice@$(date +%Y-%m-%d)

# Keep last 7 days (delete old snapshots)
zfs list -H -o name -t snapshot -S creation | grep "alice@" | tail -n +8 | xargs -n1 zfs destroy
```

Add to crontab:
```bash
crontab -e

# Add line:
0 2 * * * zfs snapshot rpool/crypt/home/alice@$(date +\%Y-\%m-\%d)
```

#### Backup to External Drive

```bash
# Create snapshot
zfs snapshot rpool/crypt/home/alice@backup-$(date +%Y-%m-%d)

# Send to external drive (first time - full backup)
zfs send rpool/crypt/home/alice@backup-2025-11-04 | \
  ssh backup-server "zfs receive backup-pool/alice"

# Subsequent backups (incremental)
zfs send -i rpool/crypt/home/alice@backup-2025-11-04 \
         rpool/crypt/home/alice@backup-2025-11-05 | \
  ssh backup-server "zfs receive backup-pool/alice"
```

#### Check Disk Usage

```bash
# See total usage (including snapshots)
zfs list rpool/crypt/home/alice

# See usage excluding snapshots
zfs list -o name,used,refer,avail rpool/crypt/home/alice

# See snapshot sizes
zfs list -t snapshot | grep alice
```

#### Set Compression on Child Dataset

```bash
# Create dataset with different compression
zfs create -o compression=zstd rpool/crypt/home/alice/archive

# Change compression on existing dataset
zfs set compression=zstd rpool/crypt/home/alice/photos
```

#### Set Quota on Child Dataset

```bash
# Limit projects directory to 50GB
zfs set quota=50G rpool/crypt/home/alice/projects

# Check quota
zfs get quota,used,available rpool/crypt/home/alice/projects
```

---

## Advanced Configuration

### Custom Parent Dataset

Use a different parent dataset location:

```nix
{
  keystone.zfsUsers = {
    enable = true;
    parentDataset = "tank/users";  # Custom location

    users = {
      alice = {
        uid = 1000;
        description = "Alice";
        hashedPassword = "$6$...";
      };
  };
}
```

Result: Dataset created at `tank/users/alice`

### Different ZFS Pool

```nix
{
  keystone.zfsUsers = {
    enable = true;
    poolName = "datapool";
    parentDataset = "datapool/home";

    users = {
      alice = {
        uid = 1000;
        description = "Alice";
        hashedPassword = "$6$...";
      };
  };
}
```

Result: Dataset created at `datapool/home/alice`

---

## Troubleshooting

### Check Module Status

```bash
# Check if zfs-user-datasets service ran successfully
systemctl status zfs-user-datasets.service

# View service logs
journalctl -u zfs-user-datasets.service

# View all ZFS-related logs
journalctl -u 'zfs*'
```

### Verify Dataset Exists

```bash
# Check if user dataset was created
zfs list rpool/crypt/home/alice

# Check if dataset is mounted
zfs get mounted rpool/crypt/home/alice

# Check mount point
df -h /home/alice
```

### Check User Permissions

```bash
# View delegated permissions
zfs allow rpool/crypt/home/alice

# Expected output:
# ---- Permissions on rpool/crypt/home/alice ----
# Local+Descendent permissions:
#     user alice bookmark,compression,create,diff,hold,quota,...
# Descendent permissions:
#     user alice destroy
```

### Test User Can Create Dataset

```bash
# As root, switch to user
su - alice

# Try creating a dataset
zfs create rpool/crypt/home/alice/test

# If successful, clean up
zfs destroy rpool/crypt/home/alice/test
```

### Common Issues

#### Issue: "dataset does not exist"

**Symptom:** User home directory doesn't exist after login

**Cause:** zfs-user-datasets service didn't run or failed

**Solution:**
```bash
# Check service status
systemctl status zfs-user-datasets.service

# Manually run service to see errors
systemctl start zfs-user-datasets.service

# Check if parent dataset exists
zfs list rpool/crypt/home
```

#### Issue: "permission denied" when creating dataset

**Symptom:** User can't run `zfs create` command

**Cause:** Delegated permissions not granted

**Solution:**
```bash
# Check permissions
zfs allow rpool/crypt/home/alice

# Manually grant permissions (as root)
zfs allow -u alice \
  create,snapshot,send,receive,compression,quota \
  rpool/crypt/home/alice
```

#### Issue: Can't delete parent home dataset

**Symptom:** `zfs destroy rpool/crypt/home/alice` fails with permission denied

**Cause:** This is expected! Users can only destroy descendants, not the parent.

**Solution:** This is by design for safety. To delete the parent, an administrator must do it:
```bash
# As root
zfs destroy -r rpool/crypt/home/alice
```

---

## Integration with Existing Keystone Modules

### With Client Module

```nix
{
  # Enable client desktop
  keystone.client = {
    enable = true;
    # ... client config
  };

  # Add ZFS users
  keystone.zfsUsers = {
    enable = true;
    users = {
      alice = {
        uid = 1000;
        description = "Alice";
        extraGroups = [ "wheel" "networkmanager" ];  # Works with client module
        hashedPassword = "$6$...";
        zfsProperties.quota = "500G";
      };
  };
}
```

### With Server Module

```nix
{
  # Enable server services
  keystone.server = {
    enable = true;
    # ... server config
  };

  # Add ZFS users
  keystone.zfsUsers = {
    enable = true;
    users = {
      admin = {
        uid = 1000;
        description = "Administrator";
        extraGroups = [ "wheel" ];
        hashedPassword = "$6$...";
      };
  };
}
```

---

## Migration Guide

### Adding Module to Existing System

If you have existing users and want to migrate to ZFS datasets:

1. **Backup existing home directories:**
   ```bash
   tar czf /root/home-backup.tar.gz /home
   ```

2. **Add module to configuration:**
   ```nix
   keystone.zfsUsers.enable = true;
   keystone.zfsUsers.users.alice = {
     uid = 1000;  # Use SAME UID as existing user!
     description = "Alice";
     hashedPassword = "$6$...";  # Use SAME password hash!
   };
   ```

3. **Before rebuilding, manually create dataset:**
   ```bash
   # Move existing home
   mv /home/alice /home/alice.old

   # Create ZFS dataset
   zfs create rpool/crypt/home/alice

   # Copy data
   rsync -av /home/alice.old/ /home/alice/

   # Fix permissions
   chown -R alice:users /home/alice
   ```

4. **Rebuild system:**
   ```bash
   nixos-rebuild switch
   ```

5. **Verify and cleanup:**
   ```bash
   # Test login as alice
   # If successful:
   rm -rf /home/alice.old
   ```

### Removing Module

To remove the module and revert to standard home directories:

1. **Backup datasets:**
   ```bash
   zfs snapshot -r rpool/crypt/home@before-removal
   zfs send -R rpool/crypt/home@before-removal > /root/zfs-home-backup.zfs
   ```

2. **Remove module from configuration:**
   ```nix
   # Comment out or remove:
   # keystone.zfsUsers.enable = true;

   # Re-enable standard user creation:
   users.users.alice = {
     isNormalUser = true;
     uid = 1000;
     createHome = true;  # Enable standard home creation
     home = "/home/alice";
   };
   ```

3. **Rebuild (will NOT delete datasets):**
   ```bash
   nixos-rebuild switch
   ```

4. **Optionally destroy datasets:**
   ```bash
   zfs destroy -r rpool/crypt/home/alice
   ```

---

## Best Practices

### Password Management

✅ **DO:** Use hashed passwords in production:
```bash
# Generate hashed password
mkpasswd -m sha-512

# Use in configuration
hashedPassword = "$6$rounds=656000$...";
```

❌ **DON'T:** Use initialPassword in production (stored in plain text in Nix store)

### Quota Settings

- **Workstations:** 200GB-500GB per user
- **Developers:** 200GB-1TB (code, build artifacts, containers)
- **Media Users:** 1TB-5TB (photos, videos)
- **Servers:** 50GB-100GB (minimal home directories)

### Compression

- **Default (lz4):** Good balance, use for most workloads
- **zstd:** Better compression for source code, documents
- **off:** Already-compressed data (videos, photos, archives)

### Snapshot Strategy

- **Daily:** Keep 7 days
- **Weekly:** Keep 4 weeks
- **Monthly:** Keep 12 months
- **Before Major Changes:** Manual snapshots

Example automation:
```bash
#!/bin/bash
# /etc/cron.daily/zfs-snapshot-homes

for user in alice bob charlie; do
  # Daily snapshot
  zfs snapshot rpool/crypt/home/$user@daily-$(date +%Y-%m-%d)

  # Clean old daily (keep 7)
  zfs list -H -o name -t snapshot -S creation | \
    grep "$user@daily-" | \
    tail -n +8 | \
    xargs -n1 zfs destroy
done
```

---

## Next Steps

After setting up ZFS users:

1. **Test User Login:** Verify users can log in and access their home directories
2. **Grant Additional Permissions:** Users can manage their datasets with `zfs` commands
3. **Set Up Backups:** Implement snapshot and send/receive workflows
4. **Monitor Usage:** Use `zfs list` to track disk usage and quotas
5. **Read Full Documentation:** See data-model.md for complete option reference

---

## Related Documentation

- **Option Reference:** [data-model.md](./data-model.md)
- **Implementation Details:** [research.md](./research.md)
- **Feature Specification:** [spec.md](./spec.md)
- **ZFS Documentation:** `man zfs`, `man zfs-allow`

---

## Support

For issues or questions:

1. Check service logs: `journalctl -u zfs-user-datasets.service`
2. Verify ZFS status: `zpool status`, `zfs list`
3. Review module assertions in build output
4. Consult [spec.md](./spec.md) for feature requirements
