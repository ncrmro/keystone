# Memory Pressure Management
#
# Fleet-wide default-on memory resilience layer for all Keystone OS hosts.
# Implements a three-tier response to memory pressure:
#
#   1. zram (zstd, 50% RAM, priority=100) — in-RAM compression, fastest
#   2. systemd-oomd — cgroup-aware OOM killer reacts on PSI alerts (before
#      the kernel oom-killer fires)
#   3. kernel oom-killer — last resort, fires only after oomd misses
#
# This module is enabled by default for all hosts where keystone.os.enable = true.
# Consumer flakes can disable it with keystone.os.memoryPressure.enable = false, or
# override individual sysctl values (all set with lib.mkDefault).
#
# Hibernation interaction:
#   zramSwap priority = 100 is higher than any disk swap (cryptswap at default
#   priority or the random-encryption swap at priority -1), so day-to-day paging
#   hits zram first. boot.resumeDevice always targets the LUKS-mapped swap
#   partition and is never pointed at a zram device — hibernation continues to
#   work on ext4 hosts.
#
# zswap/zram mutual exclusion:
#   zswap intercepts pages before they reach zram (kernel 6.6+). Enabling both
#   silently bypasses zram. An assertion enforces the exclusive choice.
#
# See docs/os/memory-pressure.md for full rationale and configuration examples.
#
{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.keystone.os.memoryPressure;
in
{
  options.keystone.os.memoryPressure = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable fleet-wide memory pressure management.

        When true (the default), configures:
        - zramSwap with zstd compression at 50% of RAM, priority 100
        - systemd-oomd on user, root, and system slices
        - kernel vm.* sysctls tuned for zram-first paging
      '';
    };
  };

  config = mkIf (config.keystone.os.enable && cfg.enable) {
    # zram swap — compressed in-RAM swap, first tier of memory pressure response.
    # priority = 100 ensures zram is preferred over any disk swap device.
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
      priority = 100;
    };

    # systemd-oomd — cgroup-level OOM killer, acts on PSI pressure signals
    # before the kernel oom-killer fires. Monitors user, root, and system slices.
    systemd.oomd = {
      enable = true;
      enableUserSlices = true;
      enableRootSlice = true;
      enableSystemSlice = true;
      extraConfig = {
        DefaultMemoryPressureDurationSec = "20s";
      };
    };

    # Kernel vm.* sysctls tuned for zram-backed swap.
    # All values use mkDefault so consumer flakes can override individual knobs
    # without disabling the whole module.
    boot.kernel.sysctl = {
      # High swappiness encourages the kernel to compress pages into zram early,
      # freeing physical RAM before pressure builds. Recommended for zram setups.
      "vm.swappiness" = mkDefault 180;
      # page-cluster=0 disables read-ahead for swap pages; zram has near-zero
      # seek cost so prefetching only wastes decompression time.
      "vm.page-cluster" = mkDefault 0;
      # Raise the watermark scaling factor so reclaim starts sooner, leaving
      # more headroom before the system stalls waiting for pages.
      "vm.watermark_scale_factor" = mkDefault 125;
      # Reserve 512 MiB of free RAM as a floor; prevents the allocator from
      # exhausting the last pages before oomd can act.
      "vm.min_free_kbytes" = mkDefault 524288;
      # Reduce tendency to drop page cache; prefer evicting anonymous pages
      # (which compress well into zram) over file-backed cache.
      "vm.vfs_cache_pressure" = mkDefault 50;
    };

    # zswap and zram are mutually exclusive: zswap intercepts pages before they
    # reach the zram device, silently bypassing it. Fail fast if both are on.
    # Note: this assertion only checks boot.zswap.enable; zswap can also be
    # activated via a "zswap.enabled=1" kernel parameter, which is not checked
    # here because scanning boot.kernelParams during assertion evaluation would
    # create circular evaluation dependencies with other modules.
    assertions = [
      {
        assertion = !(config.boot.zswap.enable or false);
        message = ''
          keystone.os.memoryPressure enables zram swap, but boot.zswap.enable is
          also true. zswap and zram are mutually exclusive — zswap intercepts pages
          before they reach zram. Either:
            • Remove boot.zswap.enable = true (and also ensure no "zswap.enabled=1"
              kernel parameter is present), or
            • Set keystone.os.memoryPressure.enable = false.
        '';
      }
    ];
  };
}
