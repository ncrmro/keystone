# systemd-oomd — modern userspace OOM killer
#
# Wires systemd-oomd to act on user, root, and system cgroup slices using PSI
# (Pressure Stall Information) signals. systemd-oomd is the modern complement
# to the in-kernel oom-killer: it kills cgroups based on sustained memory
# pressure, before the kernel oom-killer fires too late and the system has
# already wedged.
#
# Default-on per process.enable-by-default. This module deliberately covers
# only systemd-oomd — zram, vm.* sysctls, and the ZFS ARC cap are tracked
# separately (see issue #484 / PR #485). It is the lowest-risk, no-dependency
# slice of that work and can land independently.
#
# Behavior when enabled:
#   - systemd.oomd.enable = true (explicit, not relying on NixOS default)
#   - Monitors user, root, and system slices
#   - Kills the offending cgroup after 20 s of sustained memory pressure
#
{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.keystone.os.oomd;
in
{
  options.keystone.os.oomd = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable systemd-oomd cgroup-aware OOM killing on user, root, and
        system slices.

        When true (the default), systemd-oomd reacts to PSI memory-pressure
        signals and kills the offending cgroup before the kernel oom-killer
        fires. The reaction window is 20 seconds of sustained pressure.

        Set to false on hosts where you want only the in-kernel oom-killer
        (e.g., minimal containers or when debugging cgroup hierarchies).
      '';
    };
  };

  config = mkIf (config.keystone.os.enable && cfg.enable) {
    systemd.oomd = {
      enable = true;
      enableUserSlices = true;
      enableRootSlice = true;
      enableSystemSlice = true;
      extraConfig = {
        DefaultMemoryPressureDurationSec = "20s";
      };
    };
  };
}
