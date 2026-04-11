# Keystone OS Ephemeral Datasets Module
#
# Provides declarative ephemeral ZFS datasets with auto-snapshot disabled.
# High-churn directories (caches, container storage, metrics) are backed by
# dedicated child datasets under the encrypted root, keeping snapshot overhead
# minimal.
#
# The module creates a systemd oneshot service that idempotently creates ZFS
# datasets at boot and sets com.sun:auto-snapshot=false. It is a no-op on
# non-ZFS hosts.
#
# See conventions/os.zfs-backup.md rule 7: datasets with only reproducible data
# SHOULD set com.sun:auto-snapshot=false.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.ephemeralDatasets;
  osCfg = config.keystone.os;
  isZfs = osCfg.enable && osCfg.storage.type == "zfs";

  # Submodule type for a single ephemeral dataset
  datasetSubmodule = types.submodule (
    { ... }:
    {
      options = {
        mountpoint = mkOption {
          type = types.str;
          description = "Absolute filesystem path where the dataset will be mounted.";
          example = "/var/lib/prometheus2";
        };

        owner = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Username to chown the mountpoint to after creation. Null means root ownership.";
          example = "ncrmro";
        };

        service = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Systemd service unit name that depends on this dataset being ready.";
          example = "prometheus.service";
        };
      };
    }
  );

  # Convert a mountpoint path to a ZFS dataset name under the parent.
  # e.g. /var/lib/prometheus2 → var/lib/prometheus2
  #      /home/ncrmro/.cache  → home/ncrmro/cache
  # Strips leading dots from path components for valid ZFS names.
  mountpointToDatasetSuffix =
    mountpoint:
    let
      # Remove leading slash, split into components
      stripped = removePrefix "/" mountpoint;
      components = splitString "/" stripped;
      # Strip leading dots from each component for valid ZFS dataset names
      cleanComponent = c: if hasPrefix "." c then removePrefix "." c else c;
      cleaned = map cleanComponent components;
    in
    concatStringsSep "/" cleaned;

  # Build the full dataset name for a given dataset config
  datasetName =
    dsCfg: "${cfg.pool}/${cfg.parentDataset}/${mountpointToDatasetSuffix dsCfg.mountpoint}";

  # All enabled datasets (only when ZFS is active)
  enabledDatasets = if isZfs && cfg.enable then cfg.datasets else { };

  # Services that need to wait for ephemeral datasets
  servicesWithDeps = filterAttrs (_: ds: ds.service != null) enabledDatasets;

  # Build the exclude pattern for backup integration — pipe-separated dataset
  # suffixes matching the tail component of each ephemeral mountpoint.
  excludeSuffixes = map (
    ds:
    let
      parts = splitString "/" (removePrefix "/" ds.mountpoint);
    in
    last parts
  ) (attrValues enabledDatasets);

  excludePattern = concatStringsSep "|" (map (s: escapeRegex s) excludeSuffixes);
in
{
  options.keystone.os.ephemeralDatasets = {
    enable = mkEnableOption "ephemeral ZFS datasets with auto-snapshot disabled";

    pool = mkOption {
      type = types.str;
      default = "rpool";
      description = "ZFS pool name.";
    };

    parentDataset = mkOption {
      type = types.str;
      default = "crypt/system";
      description = "Parent dataset path under the pool (without pool name prefix).";
    };

    datasets = mkOption {
      type = types.attrsOf datasetSubmodule;
      default = { };
      description = "Ephemeral datasets to create with auto-snapshot disabled.";
      example = literalExpression ''
        {
          prometheus = {
            mountpoint = "/var/lib/prometheus2";
            service = "prometheus.service";
          };
          user-cache = {
            mountpoint = "/home/ncrmro/.cache";
            owner = "ncrmro";
          };
        }
      '';
    };

    _excludePattern = mkOption {
      type = types.str;
      default = excludePattern;
      readOnly = true;
      description = "Computed regex pattern for backup exclusion integration (pipe-separated dataset suffixes).";
    };
  };

  config = mkIf (isZfs && cfg.enable && enabledDatasets != { }) {
    assertions = [
      {
        assertion = all (ds: hasPrefix "/" ds.mountpoint) (attrValues enabledDatasets);
        message = "All ephemeralDatasets mountpoints must be absolute paths (start with /)";
      }
    ];

    # Systemd oneshot service that idempotently creates ephemeral ZFS datasets at boot,
    # plus service ordering for datasets with a `service` attr.
    systemd.services = mkMerge (
      [
        {
          ensure-ephemeral-datasets = {
            description = "Create ephemeral ZFS datasets with auto-snapshot disabled";

            wantedBy = [ "multi-user.target" ];
            after = [ "zfs-mount.service" ];
            requires = [ "zfs-mount.service" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };

            path = [ config.boot.zfs.package ];

            script =
              let
                createCommands = concatStringsSep "\n" (
                  mapAttrsToList (
                    name: dsCfg:
                    let
                      ds = datasetName dsCfg;
                      ownerCmd =
                        if dsCfg.owner != null then
                          ''
                            chown ${dsCfg.owner}:${dsCfg.owner} ${dsCfg.mountpoint}
                            echo "  ownership: ${dsCfg.owner}"
                          ''
                        else
                          "";
                    in
                    ''
                      # Dataset: ${name} → ${dsCfg.mountpoint}
                      if ! zfs list -H -o name ${ds} > /dev/null 2>&1; then
                        echo "Creating ephemeral dataset: ${ds}"
                        zfs create -p \
                          -o mountpoint=${dsCfg.mountpoint} \
                          -o "com.sun:auto-snapshot=false" \
                          ${ds}
                        ${ownerCmd}
                      else
                        echo "Ephemeral dataset already exists: ${ds}"
                        # Ensure properties are correct even on existing datasets
                        zfs set "com.sun:auto-snapshot=false" ${ds}
                      fi
                    ''
                  ) enabledDatasets
                );
              in
              ''
                set -euo pipefail

                # Validate pool exists
                if ! zpool list ${cfg.pool} > /dev/null 2>&1; then
                  echo "ERROR: ZFS pool '${cfg.pool}' not found" >&2
                  exit 1
                fi

                ${createCommands}

                echo "Ephemeral datasets ready."
              '';
          };
        }
      ]
      # Wire service ordering — datasets with a `service` attr block that service
      # until the dataset is ready.
      ++ mapAttrsToList (
        _: dsCfg:
        let
          svcName = removeSuffix ".service" dsCfg.service;
        in
        {
          ${svcName} = {
            after = [ "ensure-ephemeral-datasets.service" ];
            requires = [ "ensure-ephemeral-datasets.service" ];
          };
        }
      ) servicesWithDeps
    );
  };
}
