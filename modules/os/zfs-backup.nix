# ZFS Backup Module
#
# Auto-derives sanoid snapshot management, syncoid replication, receiver
# user/dataset setup, and Prometheus metrics from keystone.hosts ZFS
# backup topology.
#
# Supports both remote targets (SSH to another host) and local same-host
# targets (pool-to-pool replication within one machine, no SSH).
#
# See conventions/os.zfs-backup.md
# Follows the journal-remote.nix pattern of auto-deriving from keystone.hosts.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  hostname = config.networking.hostName;
  hosts = config.keystone.hosts;

  poolImportServices = osCfg.storage.zfs.backup.poolImportServices;

  # Find this host's entry in the registry
  currentHostEntry = findFirst (h: h.hostname == hostname) null (attrValues hosts);
  # Find the *key* (not just the value) for this host — needed for local target matching,
  # where target strings reference keystone.hosts attribute names (e.g. "ocean:ocean").
  currentHostKey = findFirst (k: hosts.${k}.hostname == hostname) null (attrNames hosts);

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

  # Is this target a same-host (local) target?
  isLocalTarget = targetStr: (parseTarget targetStr).hostKey == currentHostKey;

  # All target strings across all pools (for assertions)
  allTargetStrings = concatMap (pc: pc.targets) (attrValues backupDecls);

  # Build a stable command name per (sourcePool, target) pair.
  cmdNameFor =
    sourcePool: targetStr:
    let
      parsed = parseTarget targetStr;
    in
    if isLocalTarget targetStr then
      "${sourcePool}-local-${parsed.pool}"
    else
      "${sourcePool}-to-${parsed.hostKey}";

  # Import service deps: for a list of pool names, return
  # [ "import-foo.service" ... ] for any pool that has an entry in
  # poolImportServices. Missing pools contribute nothing.
  importDepsFor =
    pools:
    concatMap (
      p: if hasAttr p poolImportServices then [ "${poolImportServices.${p}}.service" ] else [ ]
    ) pools;

  # Build flat list of syncoid command definitions
  syncoidCmds =
    let
      mkCommands =
        sourcePool: poolCfg:
        concatMap (
          target:
          let
            parsed = parseTarget target;
            local = isLocalTarget target;
            targetHost = hosts.${parsed.hostKey} or null;
            sshTarget =
              if targetHost != null && targetHost.sshTarget != null then
                targetHost.sshTarget
              else if targetHost != null then
                targetHost.hostname
              else
                null;
            name = cmdNameFor sourcePool target;
            keyDir = "/run/syncoid/${name}";
            targetDataset = "${parsed.pool}/backups/${hostname}/${sourcePool}";
            # Local: plain dataset path, no SSH.
            # Remote: user@host:dataset.
            finalTarget = if local then targetDataset else "${hostname}-sync@${sshTarget}:${targetDataset}";
            # Common syncoid flags (convention rules 13-17).
            commonExtraArgs = [
              "--no-sync-snap"
              "--skip-parent"
              "--exclude-datasets=nix|docker|containers|images|libvirt"
              "--compress=none"
            ];
            # Only remote transfers use the host SSH key via --sshkey.
            extraArgs =
              commonExtraArgs
              ++ (
                if local then
                  [ ]
                else
                  [
                    "--sshkey"
                    "${keyDir}/ssh_key"
                  ]
              );
            # Remote-only service overrides: provision the host SSH key
            # and allow syncoid's sandbox to read it.
            remoteServiceOverrides = {
              serviceConfig = {
                ExecStartPre = [
                  "+${pkgs.coreutils}/bin/install -d -m 0700 ${keyDir}"
                  "+${pkgs.coreutils}/bin/install -m 0600 /etc/ssh/ssh_host_ed25519_key ${keyDir}/ssh_key"
                ];
                ReadWritePaths = [ keyDir ];
                ExecStopPost = [ "${backupMetricsScript} ${name}" ];
              };
            };
            # Local-only service overrides: metrics only, no SSH key prep.
            localServiceOverrides = {
              serviceConfig = {
                ExecStopPost = [ "${backupMetricsScript} ${name}" ];
              };
            };
          in
          if targetHost != null then
            [
              (nameValuePair name {
                source = sourcePool;
                target = finalTarget;
                sendOptions = "w";
                inherit extraArgs;
                service = if local then localServiceOverrides else remoteServiceOverrides;
              })
            ]
          else
            [ ]
        ) poolCfg.targets;
    in
    flatten (mapAttrsToList mkCommands backupDecls);

  # Per-syncoid-service pool-import dependencies. For each syncoid command,
  # collect import deps for both the source pool and (for local targets) the
  # target pool.
  syncoidImportDeps =
    let
      mk =
        sourcePool: poolCfg:
        concatMap (
          target:
          let
            parsed = parseTarget target;
            local = isLocalTarget target;
            name = cmdNameFor sourcePool target;
            pools = [ sourcePool ] ++ (if local then [ parsed.pool ] else [ ]);
            deps = unique (importDepsFor pools);
          in
          if hosts.${parsed.hostKey} or null != null && deps != [ ] then
            [
              (nameValuePair "syncoid-${name}" {
                after = deps;
                requires = deps;
              })
            ]
          else
            [ ]
        ) poolCfg.targets;
    in
    builtins.listToAttrs (flatten (mapAttrsToList mk backupDecls));

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
                if
                  targetHostEntry != null
                  && targetHostEntry.hostname == hostname
                  # Exclude same-host (local) targets — those are handled by the
                  # sender-side syncoid command, not as incoming SSH backups.
                  && hostCfg.hostname != hostname
                then
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
  incomingTargetPools = unique (map (b: b.targetPool) incomingBackups);

  # Receiver: pool-import service deps for target pools that are NOT
  # imported at boot (e.g. ocean's `ocean` pool, maia's `lake` pool).
  # Applied to the dataset-init/delegation oneshot unit so `zfs create` /
  # `zfs allow` cannot run before the pool is imported.
  receiverImportDeps = unique (importDepsFor incomingTargetPools);

  # ZFS binary (matches kernel module version)
  zfsBin = "${config.boot.zfs.package}/bin/zfs";

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

  # Metrics: per-target backup exit code/timestamp (convention rule 27)
  backupMetricsScript = pkgs.writeShellScript "zfs-backup-metrics" ''
    name="$1"
    exit_status="''${EXIT_STATUS:-1}"
    outfile="/var/lib/prometheus-node-exporter/zfs_backup_''${name}.prom"
    tmpfile="''${outfile}.tmp.$$"

    {
      echo "zfs_backup_last_exit_code{target=\"$name\"} $exit_status"
      if [ "$exit_status" = "0" ]; then
        echo "zfs_backup_last_success_timestamp{target=\"$name\"} $(${pkgs.coreutils}/bin/date +%s)"
      elif [ -f "$outfile" ]; then
        # Preserve last success timestamp on failure
        ${pkgs.gnugrep}/bin/grep -F "zfs_backup_last_success_timestamp" "$outfile" || true
      fi
    } > "$tmpfile"

    mv "$tmpfile" "$outfile"
  '';
in
{
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
          # Receiver assertions: senders must have hostPublicKey for SSH auth
          (optionals hasIncomingBackups (
            map (backup: {
              assertion = backup.senderPublicKey != null;
              message = "ZFS backup sender '${backup.senderHostname}' targets this host but has no hostPublicKey set in keystone.hosts. SSH authentication requires hostPublicKey.";
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

    # --- Sender: syncoid replication (convention rules 12-21) ---
    (mkIf hasBackups {
      services.syncoid = {
        enable = true;
        interval = "hourly";
        commands = builtins.listToAttrs syncoidCmds;
      };
    })

    # --- Sender: pool-import service dependencies for syncoid services ---
    # Wire after/requires onto syncoid services whose source or (for local
    # targets) target pool has an entry in poolImportServices.
    (mkIf (hasBackups && syncoidImportDeps != { }) {
      systemd.services = syncoidImportDeps;
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

    # --- Receiver: sync users (convention rules 22, 19) ---
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
            openssh.authorizedKeys.keys = optional (
              backup != null && backup.senderPublicKey != null
            ) backup.senderPublicKey;
          }
        ) uniqueSenderHostnames
      );

      users.groups = builtins.listToAttrs (
        map (senderHostname: nameValuePair "${senderHostname}-sync" { }) uniqueSenderHostnames
      );
    })

    # --- Receiver: ZFS dataset initialization and permission delegation (convention rules 23-24) ---
    # Implemented as a systemd oneshot so we can order it after non-boot
    # pool imports (convention rule 17g). Running as an activation script
    # would execute before late-imported pools are available.
    (mkIf hasIncomingBackups {
      systemd.services.zfs-backup-receiver-init = {
        description = "Initialize ZFS backup datasets and delegate permissions";
        wantedBy = [ "multi-user.target" ];
        after = [
          "zfs.target"
          "zfs-import.target"
          "local-fs.target"
        ]
        ++ receiverImportDeps;
        requires = receiverImportDeps;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = concatStringsSep "\n" (
          map (backup: ''
            # Create backup dataset hierarchy if it doesn't exist
            if ! ${zfsBin} list ${escapeShellArg "${backup.targetPool}/backups/${backup.senderHostname}/${backup.sourcePool}"} >/dev/null 2>&1; then
              ${zfsBin} create -p ${escapeShellArg "${backup.targetPool}/backups/${backup.senderHostname}/${backup.sourcePool}"} || true
            fi
            # Delegate ZFS permissions to sync user
            ${zfsBin} allow -u ${escapeShellArg "${backup.senderHostname}-sync"} receive,create,mount,rollback,destroy ${escapeShellArg "${backup.targetPool}/backups/${backup.senderHostname}"} || true
          '') incomingBackups
        );
      };
    })
  ]);
}
