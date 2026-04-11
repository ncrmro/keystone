# Keystone OS Ephemeral Datasets Module
#
# Provides declarative ephemeral ZFS datasets with auto-snapshot disabled.
# High-churn directories (caches, container storage, metrics) are backed by
# dedicated child datasets under the encrypted root, keeping snapshot overhead
# minimal.
#
# The module creates a systemd oneshot service that runs after the ZFS pool is
# unlocked and mounted. It idempotently creates datasets, sets
# com.sun:auto-snapshot=false, and auto-migrates existing data into new datasets.
# A ZFS snapshot is taken before any destructive migration step as a safety net.
# Individual dataset failures are logged but never block boot.
#
# This option is composable — consumer configs (nixos-config) can add their own
# ephemeral datasets by merging into keystone.os.ephemeralDatasets.datasets:
#
#   # In nixos-config host config:
#   keystone.os.ephemeralDatasets.datasets.steam = {
#     mountpoint = "/home/ncrmro/.local/share/Steam";
#     owner = "ncrmro";
#   };
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
          description = ''
            Systemd service unit name that depends on this dataset being ready.
            The named service will wait (After + Wants) for ensure-ephemeral-datasets
            to complete before starting.
          '';
          example = "prometheus.service";
        };

        migrate = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to auto-migrate existing data at the mountpoint into the new
            dataset. When true, the service will:
            1. Snapshot the parent dataset for safety before any destructive step
            2. Create the new dataset with mountpoint=none
            3. Move existing data aside (<mountpoint>.migrating)
            4. Set the ZFS mountpoint (triggers mount)
            5. rsync data from the staging directory into the new dataset
            6. Set ownership and clean up

            When false, existing data is left untouched and the dataset is only
            created if no directory exists at the mountpoint (or it is empty).
          '';
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
      description = ''
        Ephemeral datasets to create with auto-snapshot disabled.

        This option is composable — consumer configs can merge additional
        datasets alongside those declared in keystone modules:

          # In nixos-config host config:
          keystone.os.ephemeralDatasets.datasets.steam = {
            mountpoint = "/home/ncrmro/.local/share/Steam";
            owner = "ncrmro";
          };
      '';
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
      description = ''
        Computed regex pattern for backup exclusion integration (pipe-separated
        dataset suffixes). Consumer configs can use this to extend syncoid
        --exclude-datasets patterns:

          excludePattern = basePattern
            + lib.optionalString config.keystone.os.ephemeralDatasets.enable
              "|''${config.keystone.os.ephemeralDatasets._excludePattern}";
      '';
    };
  };

  config = mkIf (isZfs && cfg.enable && enabledDatasets != { }) {
    assertions = [
      {
        assertion = all (ds: hasPrefix "/" ds.mountpoint) (attrValues enabledDatasets);
        message = "All ephemeralDatasets mountpoints must be absolute paths (start with /)";
      }
    ];

    # Systemd oneshot service that idempotently creates ephemeral ZFS datasets
    # after the pool is unlocked and mounted, plus service ordering for datasets
    # with a `service` attr.
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

            path = [
              config.boot.zfs.package
              pkgs.rsync
              pkgs.util-linux
            ];

            script =
              let
                datasetCommands = concatStringsSep "\n" (
                  mapAttrsToList (
                    name: dsCfg:
                    let
                      ds = datasetName dsCfg;
                      ownerFlag = if dsCfg.owner != null then dsCfg.owner else "";
                      migrateFlag = if dsCfg.migrate then "1" else "0";
                    in
                    ''
                      ensure_dataset "${name}" "${ds}" "${dsCfg.mountpoint}" "${ownerFlag}" "${migrateFlag}"
                    ''
                  ) enabledDatasets
                );
              in
              ''
                set -uo pipefail

                failed=0

                # Find the ZFS dataset currently containing a given path.
                # Returns the dataset name or empty string if not on ZFS.
                containing_dataset() {
                  local path="$1"
                  # Walk up until we find an existing directory
                  while [ ! -d "$path" ]; do
                    path="$(dirname "$path")"
                  done
                  local src
                  src="$(df --output=source "$path" 2>/dev/null | tail -1)"
                  if [[ "$src" == ${cfg.pool}/* ]]; then
                    echo "$src"
                  fi
                }

                # Idempotently ensure a single ephemeral dataset exists, migrating
                # existing data if present. Errors are logged but do not abort boot.
                ensure_dataset() {
                  local name="$1" ds="$2" mountpoint="$3" owner="$4" do_migrate="$5"

                  echo "--- $name: $ds → $mountpoint"

                  # Already exists — just enforce properties
                  if zfs list -H -o name "$ds" > /dev/null 2>&1; then
                    echo "  already exists, enforcing properties"
                    zfs set "com.sun:auto-snapshot=false" "$ds" || true
                    if [ -n "$owner" ]; then
                      chown "$owner:$owner" "$mountpoint" 2>/dev/null || true
                    fi
                    return 0
                  fi

                  # Check for existing data that needs migration
                  local has_data=0
                  if [ -d "$mountpoint" ] && [ -n "$(ls -A "$mountpoint" 2>/dev/null)" ]; then
                    has_data=1
                  fi

                  if [ "$has_data" = "1" ] && [ "$do_migrate" = "1" ]; then
                    echo "  existing data detected, migrating into new dataset"

                    # Safety: snapshot the parent dataset before destructive steps
                    local parent_ds
                    parent_ds="$(containing_dataset "$mountpoint")"
                    if [ -n "$parent_ds" ]; then
                      local snap_name="''${parent_ds}@pre-ephemeral-''${name}-$(date +%Y%m%d-%H%M%S)"
                      echo "  snapshot: $snap_name"
                      zfs snapshot "$snap_name" || echo "  WARNING: snapshot failed, continuing"
                    fi

                    # Create with mountpoint=none to avoid conflict with existing dir
                    if ! zfs create -p -o mountpoint=none -o "com.sun:auto-snapshot=false" "$ds"; then
                      echo "  ERROR: failed to create dataset $ds" >&2
                      failed=1
                      return 1
                    fi

                    # Move existing data aside
                    if ! mv "$mountpoint" "''${mountpoint}.migrating"; then
                      echo "  ERROR: failed to move $mountpoint aside" >&2
                      # Roll back: destroy the empty dataset we just created
                      zfs destroy "$ds" 2>/dev/null || true
                      failed=1
                      return 1
                    fi

                    # Set mountpoint — ZFS auto-mounts the dataset
                    if ! zfs set mountpoint="$mountpoint" "$ds"; then
                      echo "  ERROR: failed to set mountpoint on $ds" >&2
                      # Roll back: restore original directory
                      zfs destroy "$ds" 2>/dev/null || true
                      mv "''${mountpoint}.migrating" "$mountpoint" 2>/dev/null || true
                      failed=1
                      return 1
                    fi

                    # rsync data into the new dataset
                    echo "  migrating data (rsync)..."
                    if rsync -a "''${mountpoint}.migrating/" "''${mountpoint}/"; then
                      echo "  migration complete, cleaning up staging dir"
                      rm -rf "''${mountpoint}.migrating"
                    else
                      echo "  WARNING: rsync failed — staging dir preserved at ''${mountpoint}.migrating"
                      echo "  Manual cleanup required after verifying data integrity."
                    fi

                    if [ -n "$owner" ]; then
                      chown -R "$owner:$owner" "$mountpoint"
                    fi
                  else
                    # No data to migrate (or migrate=false) — create directly
                    if [ "$has_data" = "1" ]; then
                      echo "  existing data detected but migrate=false, skipping"
                      return 0
                    fi

                    echo "  creating new dataset"
                    if ! zfs create -p -o mountpoint="$mountpoint" -o "com.sun:auto-snapshot=false" "$ds"; then
                      echo "  ERROR: failed to create dataset $ds" >&2
                      failed=1
                      return 1
                    fi

                    if [ -n "$owner" ]; then
                      chown "$owner:$owner" "$mountpoint"
                    fi
                  fi

                  echo "  done"
                }

                # Validate pool exists
                if ! zpool list ${cfg.pool} > /dev/null 2>&1; then
                  echo "ERROR: ZFS pool '${cfg.pool}' not found — skipping all ephemeral datasets" >&2
                  exit 0
                fi

                ${datasetCommands}

                if [ "$failed" != "0" ]; then
                  echo "WARNING: some ephemeral datasets failed (see above), boot continues"
                fi

                echo "Ephemeral datasets service complete."
              '';
          };
        }
      ]
      # Wire service ordering — datasets with a `service` attr wait for the
      # ephemeral dataset service. Uses Wants (soft dep) so dependent services
      # can still start if the dataset service fails unexpectedly.
      ++ mapAttrsToList (
        _: dsCfg:
        let
          svcName = removeSuffix ".service" dsCfg.service;
        in
        {
          ${svcName} = {
            after = [ "ensure-ephemeral-datasets.service" ];
            wants = [ "ensure-ephemeral-datasets.service" ];
          };
        }
      ) servicesWithDeps
    );
  };
}
