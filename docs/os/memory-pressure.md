# Memory Pressure Management

Keystone OS includes a default-on memory resilience layer that protects hosts
from runaway processes without requiring a hard reboot. It is controlled by
`keystone.os.memoryPressure.enable` (defaults to `true`).

## Layered memory-pressure response

```
  anonymous page eviction
           |
           v
  +------------------+         +--------------------+
  | zram (zstd)      |  PSI    | systemd-oomd       |
  | compressed swap  | ------> | kills cgroup at    |
  | in RAM, prio=100 | alert   | DefaultMemory-     |
  +------------------+         | PressureSec = 20s  |
           |                   +--------------------+
           v (overflow only)            |
  +------------------+                  v
  | disk swap        |          +--------------------+
  | prio = -1        |          | kernel oom-killer  |
  +------------------+          | (last resort)      |
                                +--------------------+
```

1. **zram** (zstd, 50% of RAM, priority 100) — pages are compressed in memory
   before any disk I/O occurs. Near-zero latency, no LUKS unlock required.
2. **systemd-oomd** — monitors PSI (Pressure Stall Information) on user, root,
   and system cgroups. Kills the offending cgroup within 20 seconds of sustained
   pressure, before the kernel oom-killer fires.
3. **kernel oom-killer** — last resort; fires only if oomd misses a runaway.

## Configuration

```nix
# Default (recommended)
keystone.os.memoryPressure.enable = true;  # zram + oomd + sysctls

# Override a single sysctl without disabling the module
boot.kernel.sysctl."vm.swappiness" = lib.mkForce 100;

# Disable entirely (e.g., for custom swap layout)
keystone.os.memoryPressure.enable = false;
```

### Options set when enabled

| Setting | Value | Purpose |
|---|---|---|
| `zramSwap.algorithm` | `zstd` | Best compression/speed ratio |
| `zramSwap.memoryPercent` | `50` | Device sized at 50% of physical RAM |
| `zramSwap.priority` | `100` | Preferred over all disk swap |
| `systemd.oomd.enableUserSlices` | `true` | Monitors user cgroups |
| `systemd.oomd.enableRootSlice` | `true` | Monitors root slice |
| `systemd.oomd.enableSystemSlice` | `true` | Monitors system slice |
| `DefaultMemoryPressureDurationSec` | `20s` | oomd reaction window |
| `vm.swappiness` | `180` | Aggressive zram use; valid >100 with zram |
| `vm.page-cluster` | `0` | No swap read-ahead (zram has no seek cost) |
| `vm.watermark_scale_factor` | `125` | Earlier reclaim, more headroom |
| `vm.min_free_kbytes` | `524288` | 512 MiB floor before oomd can act |
| `vm.vfs_cache_pressure` | `50` | Prefer evicting anon pages over page cache |

## ZFS hosts

All ZFS hosts use `boot.zfs.allowHibernation = false` (enforced by the storage
module). Disk swap on ZFS hosts uses random encryption at priority −1, ensuring
zram always absorbs page-outs first and disk swap is only hit on overflow.

## Laptop (ext4 + hibernate) hosts

On hosts where `keystone.os.storage.hibernate.enable = true`:

- `zram` runs at priority 100 — day-to-day paging hits zram first.
- `cryptswap` (the LUKS-mapped swap partition) is the resume device. It runs
  at the kernel's default swap priority (0), which is **lower** than zram's
  100, so hibernation writes go to the correct disk partition.
- `boot.resumeDevice` always points to `/dev/mapper/cryptswap`, never to a
  zram device. zram is a volatile in-RAM device and cannot store hibernation
  images.

Verification after deploy:

```sh
# Confirm zram0 is priority 100 and sits above disk swap
swapon --show

# Confirm resume device is the LUKS partition, not /dev/zram0
cat /proc/cmdline | grep -o 'resume=.*'
```

## zswap / zram mutual exclusion

`zswap` (a kernel front-end compression cache) intercepts swap pages before
they reach the zram block device. Enabling both silently disables zram's
benefit. The module asserts that `boot.zswap.enable` is `false` whenever
`keystone.os.memoryPressure.enable = true`. To use zswap instead, set
`keystone.os.memoryPressure.enable = false` and configure `boot.zswap` manually.

## ZFS ARC cap

When `keystone.os.storage.type = "zfs"`, the ZFS Adaptive Replacement Cache
maximum is controlled by `keystone.os.storage.zfs.arcMax`:

- **Explicit value** (e.g., `arcMax = "8G"`) — used verbatim.
- **Null** (the default) — computed as 25% of the host's physical RAM using
  `keystone.hosts.<name>.physicalMemoryGB`. Every ZFS host must declare this
  field:

  ```nix
  keystone.hosts.myhost = {
    hostname = "myhost";
    physicalMemoryGB = 64;  # 25% = 16 GiB ARC cap
    # …
  };
  ```

  Evaluation fails with a clear message if both `arcMax` and `physicalMemoryGB`
  are absent.
