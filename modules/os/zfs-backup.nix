# ZFS Backup Module
#
# Auto-derives sanoid snapshot management, syncoid replication, receiver
# user/dataset setup, and Prometheus metrics from keystone.hosts ZFS
# backup topology.
#
# See conventions/os.zfs-backup.md (30 rules)
# Follows the journal-remote.nix pattern of auto-deriving from keystone.hosts.
#
# Per-host tuning options:
#   keystone.os.zfsBackup.poolImportServices   — gate on non-boot pool imports (gap 2)
#   keystone.os.zfsBackup.sshKeyFallbackUser   — SSH key fallback when hostPublicKey is null (gap 4)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  backupCfg = osCfg.zfsBackup;
  hostname = config.networking.hostName;
  hosts = config.keystone.hosts;

  # Find this host's entry in the registry
  currentHostEntry = findFirst (h: h.hostname == hostname) null (attrValues hosts);

  # Sender: does this host declare ZFS backups?
  hasBackups =
    currentHostEntry != null && currentHostEntry.zfs != null && currentHostEntry.zfs.backups != { };

  backupDecls = if hasBackups then currentHostEntry.zfs.backups else { };
  backedUpPools = attrNames backupDecls;

  # Parse "host:pool" target string (convention rule 9)
  parseTarget =
    targetStr:
    let
      parts = splitString ":" targetStr;
    in
    {
      hostKey = elemAt parts 0;
      pool = elemAt parts 1;
    };

  # Validate target string format (exactly "host:pool")
  isValidTarget =
    targetStr:
    let
      parts = splitString ":" targetStr;
    in
    length parts == 2 && elemAt parts 0 != "" && elemAt parts 1 != "";

  # All target strings across all pools (for assertions)
  allTargetStrings = concatMap (pc: pc.targets) (attrValues backupDecls);

  # Metrics: snapshot age/count exporter (convention rules 25-26)
  snapshotMetricsScript = pkgs.writeShellScript "zfs-snapshot-metrics" ''
    outfile="/var/lib/prometheus-node-exporter/zfs_snapshots.prom"
    tmpfile="''${outfile}.tmp.$$"

    {
    ${concatMapStringsSep "\n" (pool: ''
      count=$(${zfsBin} list -t snapshot -r ${escapeShellArg pool} -H -o name 2>/dev/null | wc -l || echo 0)
      newest=$(${zfsBin} list -t snapshot -r ${escapeShellArg pool} -H -o creation -s creation 2>/dev/null | tail -1)
      if [ -n "$newest" ]; then
        newest_epoch=$(${pkgs.coreutils}/bin/date -d "$newest" +%s 2>/dev/null || echo 0)
        now=$(${pkgs.coreutils}/bin/date +%s)
        age=$((now - newest_epoch))
      else
        age=-1
      fi
      echo "zfs_snapshot_count{pool=\"${pool}\"} $count"
      echo "zfs_snapshot_newest_age_seconds{pool=\"${pool}\"} $age"
    '') backedUpPools}
    } > "$tmpfile"

    mv "$tmpfile" "$outfile"
  '';

  # Metrics: per-target backup exit code/timestamp (convention rule 27, gap 3)
  # Generates a per-command script with richer label set matching legacy:
  # job, source_host, source_pool, target_host, target_pool
  mkBackupMetricsScript =
    {
      name,
      sourcePool,
      targetHostname,
      targetPool,
    }:
    pkgs.writeShellScript "zfs-backup-metrics-${name}" ''
      exit_status="''${EXIT_STATUS:-1}"
      outfile="/var/lib/prometheus-node-exporter/zfs_backup_${name}.prom"
      tmpfile="''${outfile}.tmp.$$"

      {
        echo "# HELP zfs_backup_last_exit_code Exit code of last backup run"
        echo "# TYPE zfs_backup_last_exit_code gauge"
        echo "# HELP zfs_backup_last_success_timestamp Unix timestamp of last successful backup"
        echo "# TYPE zfs_backup_last_success_timestamp gauge"
        if [ "$exit_status" = "0" ]; then
          echo "zfs_backup_last_success_timestamp{job=\"${name}\",source_host=\"${hostname}\",source_pool=\"${sourcePool}\",target_host=\"${targetHostname}\",target_pool=\"${targetPool}\"} $(${pkgs.coreutils}/bin/date +%s)"
        elif [ -f "$outfile" ]; then
          # Preserve last success timestamp on failure
          ${pkgs.gnugrep}/bin/grep -F "zfs_backup_last_success_timestamp" "$outfile" || true
        fi
        echo "zfs_backup_last_exit_code{job=\"${name}\",source_host=\"${hostname}\",source_pool=\"${sourcePool}\",target_host=\"${targetHostname}\",target_pool=\"${targetPool}\"} $exit_status"
      } > "$tmpfile"

      mv "$tmpfile" "$outfile"
    '';

  # Build flat list of syncoid command definitions (gaps 1, 2)
  # - Local targets (same host, different pool): direct dataset path, --identifier=<host>-local-backup
  # - Remote targets: SSH path, --identifier=<host>-offsite-<targetHostname>
  syncoidCmds =
    let
      mkCommands =
        sourcePool: poolCfg:
        concatMap (
          target:
          let
            parsed = parseTarget target;
            targetHost = hosts.${parsed.hostKey} or null;
            # gap 1: detect intra-host (local) targets — same machine, different pool
            isLocal = targetHost != null && targetHost.hostname == hostname;
            targetHostname = if targetHost != null then targetHost.hostname else parsed.hostKey;
            # gap 1: naming convention — local uses "local-<pool>", remote uses "to-<targetHostname>"
            name =
              if isLocal then
                "${sourcePool}-local-${parsed.pool}"
              else
                "${sourcePool}-to-${targetHostname}";
            keyDir = "/run/syncoid/${name}";
            targetDataset = "${parsed.pool}/backups/${hostname}/${sourcePool}";
            syncUser = "${hostname}-sync";
            sshTarget =
              if targetHost != null && targetHost.sshTarget != null then
                targetHost.sshTarget
              else
                targetHostname;
            metricsScript = mkBackupMetricsScript {
              inherit name sourcePool targetHostname;
              targetPool = parsed.pool;
            };
          in
          if targetHost != null then
            [
              (nameValuePair name (
                {
                  source = sourcePool;
                  # convention rules 13-17: raw send, no-sync-snap, skip-parent, exclude, compress
                  sendOptions = "w";
                  extraArgs =
                    [
                      "--no-sync-snap"
                      "--skip-parent"
                      "--exclude-datasets=nix|docker|containers|images|libvirt"
                      "--compress=none"
                    ]
                    ++ (
                      if isLocal then
                        # gap 1: identifier for local intra-host replication
                        [ "--identifier=${hostname}-local-backup" ]
                      else
                        # gap 1: identifier for remote replication; SSH key for authentication
                        [
                          "--identifier=${hostname}-offsite-${targetHostname}"
                          "--no-privilege-elevation"
                          "--sshkey"
                          "${keyDir}/ssh_key"
                        ]
                    );
                  service = {
                    serviceConfig =
                      {
                        ExecStopPost = [ "+${metricsScript}" ];
                      }
                      // (
                        if !isLocal then
                          # convention rules 18-21: SSH key handling with sandbox fix
                          {
                            ExecStartPre = [
                              "+${pkgs.coreutils}/bin/install -d -m 0700 ${keyDir}"
                              "+${pkgs.coreutils}/bin/install -m 0600 /etc/ssh/ssh_host_ed25519_key ${keyDir}/ssh_key"
                            ];
                            ReadWritePaths = [ keyDir ];
                          }
                        else
                          { }
                      );
                  };
                }
                // (
                  # gap 1: local = direct dataset path (no SSH), remote = SSH user@host:dataset
                  if isLocal then
                    { target = targetDataset; }
                  else
                    { target = "${syncUser}@${sshTarget}:${targetDataset}"; }
                )
              ))
            ]
          else
            [ ]
        ) poolCfg.targets;
    in
    flatten (mapAttrsToList mkCommands backupDecls);

  # Pool import service unit deps for a list of pool names (gap 2)
  importDepsFor =
    pools:
    concatMap (
      pool:
      if hasAttr pool backupCfg.poolImportServices then
        [ "${backupCfg.poolImportServices.${pool}}.service" ]
      else
        [ ]
    ) pools;

  # Receiver: find all incoming backup connections targeting this host
  incomingBackups =
    let
      perHost = mapAttrsToList (
        _name: hostCfg:
        if hostCfg.zfs != null then
          flatten (
            mapAttrsToList (
              sourcePool: poolCfg:
              map (
                target:
                let
                  parsed = parseTarget target;
                  targetHostEntry = hosts.${parsed.hostKey} or null;
                in
                if targetHostEntry != null && targetHostEntry.hostname == hostname then
                  {
                    senderHostname = hostCfg.hostname;
                    senderPublicKey = hostCfg.hostPublicKey;
                    inherit sourcePool;
                    targetPool = parsed.pool;
                  }
                else
                  null
              ) poolCfg.targets
            ) hostCfg.zfs.backups
          )
        else
          [ ]
      ) hosts;
    in
    filter (x: x != null) (flatten perHost);

  hasIncomingBackups = incomingBackups != [ ];
  uniqueSenderHostnames = unique (map (b: b.senderHostname) incomingBackups);

  # Unique target pools for incoming backups (for pool import service deps, gap 2)
  incomingTargetPools = unique (map (b: b.targetPool) incomingBackups);

  # SSH authorized_keys for a sync user on the receiver (gap 4)
  # Falls back to keystone.keys.<fallbackUser>.allKeys when senderPublicKey is null
  syncKeysFor =
    backup:
    if backup.senderPublicKey != null then
      [ backup.senderPublicKey ]
    else if backupCfg.sshKeyFallbackUser != null then
      config.keystone.keys.${backupCfg.sshKeyFallbackUser}.allKeys
    else
      [ ];

  # ZFS binary (matches kernel module version)
  zfsBin = "${config.boot.zfs.package}/bin/zfs";
in
{
  options.keystone.os.zfsBackup = {
    # gap 2: pool import service gating for non-boot pools
    poolImportServices = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Map of local ZFS pool name to systemd service name (without .service suffix)
        that imports that pool. Used to gate syncoid local-backup commands and
        zfs-backup-init on non-boot pool availability.

        Example: if pool "ocean" is imported by a service "import-ocean", set
          keystone.os.zfsBackup.poolImportServices.ocean = "import-ocean";

        This ensures syncoid and the dataset-init service only run after the pool
        is available, preventing failures when pools are not imported at boot.
      '';
      example = {
        ocean = "import-ocean";
        tank = "import-tank";
      };
    };

    # gap 4: SSH key fallback for receivers when sender has no hostPublicKey
    sshKeyFallbackUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        keystone.keys user whose allKeys (host + hardware) are used as
        authorized_keys for receiver sync users when a sender host has no
        hostPublicKey set in keystone.hosts. This allows receiver hosts to
        accept ZFS backup pushes from senders that have not yet published a
        host key to the keystone registry.
      '';
      example = "ncrmro";
    };
  };

  config = mkIf osCfg.enable (mkMerge [
    # --- Assertions ---
    {
      assertions =
        # Sender assertions: validate target format
        (optionals hasBackups (
          map (target: {
            assertion = isValidTarget target;
            message = "ZFS backup target '${target}' is malformed. Must be 'host:pool' format (e.g., 'ocean:ocean').";
          }) allTargetStrings
        ))
        ++
          # Sender assertions: all backup targets must reference valid hosts
          (optionals hasBackups (
            map (
              target:
              let
                parsed = parseTarget target;
              in
              {
                assertion = !isValidTarget target || hasAttr parsed.hostKey hosts;
                message = "ZFS backup target '${target}' references unknown host '${parsed.hostKey}'. It must exist in keystone.hosts.";
              }
            ) allTargetStrings
          ))
        ++ [
          # ZFS backups require ZFS storage on the sender
          {
            assertion = !hasBackups || osCfg.storage.type == "zfs";
            message = "ZFS backups are declared for this host but storage type is '${osCfg.storage.type}'. ZFS backups require storage.type = \"zfs\".";
          }
          # ZFS incoming backups require ZFS storage on the receiver
          {
            assertion = !hasIncomingBackups || osCfg.storage.type == "zfs";
            message = "ZFS incoming backups target this host but storage type is '${osCfg.storage.type}'. Receiving ZFS backups requires storage.type = \"zfs\".";
          }
        ]
        ++
          # Receiver assertions: senders must have hostPublicKey or a fallback user (gap 4)
          (optionals hasIncomingBackups (
            map (backup: {
              assertion = backup.senderPublicKey != null || backupCfg.sshKeyFallbackUser != null;
              message = "ZFS backup sender '${backup.senderHostname}' targets this host but has no hostPublicKey set in keystone.hosts. Either set hostPublicKey or configure keystone.os.zfsBackup.sshKeyFallbackUser as a fallback.";
            }) incomingBackups
          ));
    }

    # --- Sender: sanoid snapshot management (convention rules 4-7) ---
    (mkIf hasBackups {
      services.sanoid = {
        enable = true;
        datasets = mapAttrs (_pool: _poolCfg: {
          recursive = true;
          process_children_only = true;
          autoprune = true;
          autosnap = true;
          hourly = 24;
          daily = 7;
          weekly = 4;
          monthly = 6;
        }) backupDecls;
      };
    })

    # --- Sender: syncoid replication (convention rules 12-21, gaps 1-2) ---
    (mkIf hasBackups {
      services.syncoid = {
        enable = true;
        interval = "hourly";
        commands = builtins.listToAttrs syncoidCmds;
      };
    })

    # --- Sender: pool import service dependencies for local syncoid commands (gap 2) ---
    # Override the auto-generated syncoid-<name> services to add after/requires for
    # non-boot pools that need explicit import before replication can run.
    (mkIf hasBackups {
      systemd.services = builtins.listToAttrs (
        concatLists (
          mapAttrsToList (
            sourcePool: poolCfg:
            concatMap (
              target:
              let
                parsed = parseTarget target;
                targetHost = hosts.${parsed.hostKey} or null;
                isLocal = targetHost != null && targetHost.hostname == hostname;
                targetHostname = if targetHost != null then targetHost.hostname else parsed.hostKey;
                name =
                  if isLocal then
                    "${sourcePool}-local-${parsed.pool}"
                  else
                    "${sourcePool}-to-${targetHostname}";
                serviceName = "syncoid-${name}";
                poolDeps = if isLocal then importDepsFor [ parsed.pool ] else [ ];
              in
              optional (poolDeps != [ ]) (
                nameValuePair serviceName {
                  after = poolDeps;
                  requires = poolDeps;
                }
              )
            ) poolCfg.targets
          ) backupDecls
        )
      );
    })

    # --- Sender: snapshot metrics timer (convention rules 25-26) ---
    (mkIf hasBackups {
      systemd.services.zfs-snapshot-metrics = {
        description = "Export ZFS snapshot metrics for Prometheus";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = snapshotMetricsScript;
        };
      };

      systemd.timers.zfs-snapshot-metrics = {
        description = "ZFS snapshot metrics exporter (every 5 min)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:0/5";
          Persistent = true;
        };
      };
    })

    # --- Ensure metrics directory exists ---
    (mkIf (hasBackups || hasIncomingBackups) {
      systemd.tmpfiles.rules = [
        "d /var/lib/prometheus-node-exporter 0755 root root -"
      ];
    })

    # --- Receiver: sync users (convention rules 22, 19, gap 4) ---
    (mkIf hasIncomingBackups {
      users.users = builtins.listToAttrs (
        map (
          senderHostname:
          let
            backup = findFirst (b: b.senderHostname == senderHostname) null incomingBackups;
          in
          nameValuePair "${senderHostname}-sync" {
            isSystemUser = true;
            group = "${senderHostname}-sync";
            home = "/var/empty";
            shell = "${pkgs.bash}/bin/bash";
            # gap 4: use senderPublicKey or fall back to keystone.keys user
            openssh.authorizedKeys.keys = syncKeysFor backup;
          }
        ) uniqueSenderHostnames
      );

      users.groups = builtins.listToAttrs (
        map (senderHostname: nameValuePair "${senderHostname}-sync" { }) uniqueSenderHostnames
      );
    })

    # --- Receiver: ZFS dataset initialization and permission delegation (convention rules 23-24, gap 5) ---
    # Uses a proper systemd oneshot service (not activationScripts) so it can
    # declare after/requires ordering on pool import services (gaps 2, 5).
    (mkIf hasIncomingBackups {
      systemd.services.zfs-backup-init = {
        description = "Initialize ZFS backup datasets and delegations";
        wantedBy = [ "multi-user.target" ];
        # gap 2: wait for non-boot pools to be imported before initializing datasets
        after = [ "zfs.target" ] ++ importDepsFor incomingTargetPools;
        requires = importDepsFor incomingTargetPools;
        path = [ config.boot.zfs.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = concatStringsSep "\n" (
          map (
            backup:
            let
              dataset = "${backup.targetPool}/backups/${backup.senderHostname}/${backup.sourcePool}";
              parentDataset = "${backup.targetPool}/backups/${backup.senderHostname}";
              syncUser = "${backup.senderHostname}-sync";
            in
            ''
              # ${syncUser} → ${dataset}
              if ! zfs list ${escapeShellArg dataset} >/dev/null 2>&1; then
                zfs create -p ${escapeShellArg dataset} || true
              fi
              zfs allow ${syncUser} receive,create,mount,rollback,destroy ${escapeShellArg parentDataset}
            ''
          ) incomingBackups
        );
      };
    })
  ]);
}
