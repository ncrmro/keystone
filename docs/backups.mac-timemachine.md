# Mac Time Machine Backups

Network-based Time Machine backup support using Samba and ZFS.

## Basic Setup

```nix
keystone.backups.macTimeMachine = {
  enable = true;
  pool = "rpool";
  dataset = "timemachine";
  quota = "1T";
};
```

Creates:
- ZFS dataset at `rpool/timemachine` with compression enabled
- Samba share accessible at `smb://<server>/timemachine`
- Automatic service discovery via Avahi/mDNS
- Time Machine compatible share with proper Apple extensions

## Configuration Options

### Pool and Dataset

```nix
keystone.backups.macTimeMachine = {
  enable = true;
  pool = "tank";              # ZFS pool name (default: "rpool")
  dataset = "backups/timemachine";  # Dataset path (default: "timemachine")
};
```

The dataset will be mounted at `/timemachine` regardless of the pool or dataset name.

### Storage Quota

```nix
keystone.backups.macTimeMachine = {
  enable = true;
  quota = "500G";  # Limit Time Machine backups to 500GB
};
```

Quota sizes:
- `500G` - 500 gigabytes
- `1T` - 1 terabyte
- `2T` - 2 terabytes
- `null` - No quota (default)

### User Access Control

```nix
keystone.backups.macTimeMachine = {
  enable = true;
  allowedUsers = [ "alice" "bob" ];  # Only these users can access
};
```

- Empty list (default): All users in the `users` group can access
- Specified users: Only listed users can create Time Machine backups

### Compression

```nix
keystone.backups.macTimeMachine = {
  enable = true;
  compression = "zstd";  # Default compression algorithm
};
```

Compression options:
- `zstd` - Best compression ratio (default)
- `lz4` - Faster but less compression
- `gzip` - Standard compression
- `off` - No compression

## Connecting from macOS

### Automatic Discovery

1. Open **System Settings** > **General** > **Time Machine**
2. Click **Add Backup Disk**
3. Your server should appear automatically (via Avahi/mDNS)
4. Select the `timemachine` share
5. Enter your username and password

### Manual Connection

If automatic discovery doesn't work:

1. In Finder, press `Cmd+K`
2. Enter: `smb://<server-ip>/timemachine`
3. Authenticate with your username and password
4. Open **System Settings** > **General** > **Time Machine**
5. Click **Add Backup Disk** and select the mounted share

### First Backup

The initial Time Machine backup may take several hours depending on:
- Amount of data on your Mac
- Network speed
- Server disk performance

Subsequent backups are incremental and much faster.

## Network Requirements

The module automatically configures firewall rules:
- TCP ports: 139, 445 (Samba)
- UDP ports: 137, 138 (NetBIOS)
- mDNS/Avahi for service discovery

Ensure your network allows these ports between the Mac and server.

## ZFS Integration

### Dataset Properties

The module automatically sets:
- Compression: Enabled by default (zstd)
- Mountpoint: `/timemachine`
- Quota: Optional storage limit

### Manual Dataset Management

```bash
# View dataset info
zfs list rpool/timemachine

# Check current usage
zfs get used,quota rpool/timemachine

# Create a snapshot
sudo zfs snapshot rpool/timemachine@backup-$(date +%Y%m%d)

# List snapshots
zfs list -t snapshot rpool/timemachine

# Restore from snapshot
sudo zfs rollback rpool/timemachine@backup-20250109
```

### Replication

Replicate Time Machine backups to another server:

```bash
# Send snapshot to remote server
sudo zfs send rpool/timemachine@backup-20250109 | \
  ssh backup-server sudo zfs receive tank/timemachine-replica@backup-20250109
```

## Troubleshooting

### Mac Cannot Find Server

1. Verify Avahi is running:
   ```bash
   systemctl status avahi-daemon
   ```

2. Test network connectivity:
   ```bash
   # From Mac
   ping <server-ip>
   ```

3. Manually connect using IP address instead of hostname

### Authentication Fails

1. Verify user exists on server:
   ```bash
   id <username>
   ```

2. Check Samba user database:
   ```bash
   sudo pdbedit -L
   ```

3. Add user to Samba if needed:
   ```bash
   sudo smbpasswd -a <username>
   ```

### Quota Exceeded

1. Check current usage:
   ```bash
   zfs get used,quota rpool/timemachine
   ```

2. Increase quota:
   ```bash
   sudo zfs set quota=2T rpool/timemachine
   ```

3. Or update NixOS configuration and rebuild:
   ```nix
   keystone.backups.macTimeMachine.quota = "2T";
   ```

### Performance Issues

Time Machine backups over network are slower than local. To improve:

1. Use wired Ethernet instead of WiFi
2. Enable compression (reduces network transfer):
   ```nix
   keystone.backups.macTimeMachine.compression = "lz4";
   ```
3. Consider faster compression (lz4) if CPU is limited
4. Ensure adequate server resources (RAM, CPU, disk I/O)

## Security Considerations

### Network Security

- Time Machine traffic is **not encrypted** by default over Samba
- Use on trusted networks only (home LAN, VPN)
- Consider using Tailscale/WireGuard for remote access

### Access Control

- Each user's Time Machine backup is isolated by Unix permissions
- Set `allowedUsers` to restrict who can create backups
- Regular users cannot access other users' backups

### Backup Encryption

macOS Time Machine supports local encryption but not over network shares. For encrypted backups:

1. Use ZFS native encryption for the dataset (advanced)
2. Or encrypt the entire pool with LUKS (Keystone default)
3. Or use FileVault on the Mac and store backups locally

## Integration with Keystone

### With Server Module

```nix
{
  imports = [
    keystone.nixosModules.server
    keystone.nixosModules.macTimeMachine
  ];

  keystone.server.enable = true;
  keystone.backups.macTimeMachine = {
    enable = true;
    quota = "1T";
  };
}
```

### Multiple Users

```nix
{
  keystone.users = {
    alice.uid = 1000;
    bob.uid = 1001;
  };

  keystone.backups.macTimeMachine = {
    enable = true;
    allowedUsers = [ "alice" "bob" ];
    quota = "2T";  # Shared quota for all users
  };
}
```

### Custom Pool

If using a separate pool for backups:

```nix
{
  keystone.backups.macTimeMachine = {
    enable = true;
    pool = "backup-pool";
    dataset = "timemachine";
    quota = "5T";
  };
}
```

## References

- Module implementation: `modules/backups/mac-timemachine/default.nix`
- Samba Time Machine: https://wiki.samba.org/index.php/Configure_Samba_to_Work_Better_with_Mac_OS_X
- ZFS documentation: https://openzfs.github.io/openzfs-docs/
- Apple Time Machine: https://support.apple.com/en-us/HT201250
