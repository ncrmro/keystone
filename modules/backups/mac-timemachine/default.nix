{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.backups.macTimeMachine;
  datasetPath = "${cfg.pool}/${cfg.dataset}";
  mountPoint = "/timemachine";
in
{
  options.keystone.backups.macTimeMachine = {
    enable = mkEnableOption "Mac Time Machine backup support via Samba and ZFS";

    pool = mkOption {
      type = types.str;
      default = "rpool";
      description = "ZFS pool name where the Time Machine dataset will be created";
      example = "tank";
    };

    dataset = mkOption {
      type = types.str;
      default = "timemachine";
      description = "ZFS dataset name for Time Machine backups";
      example = "backups/timemachine";
    };

    quota = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional ZFS quota for the Time Machine dataset (e.g., '500G', '1T')";
      example = "1T";
    };

    allowedUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of users allowed to access the Time Machine share. Empty list means all users.";
      example = [ "alice" "bob" ];
    };

    compression = mkOption {
      type = types.str;
      default = "zstd";
      description = "ZFS compression algorithm for the Time Machine dataset";
      example = "lz4";
    };
  };

  config = mkIf cfg.enable {
    # Ensure Samba is enabled
    services.samba = {
      enable = true;
      openFirewall = true;

      # Samba configuration for Time Machine
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "Keystone Time Machine Server";
          "security" = "user";
          "map to guest" = "Bad User";

          # Time Machine specific settings
          "vfs objects" = "catia fruit streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "fruit:posix_rename" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";
        };

        timemachine = {
          "path" = mountPoint;
          "browseable" = "yes";
          "writable" = "yes";
          "valid users" = if cfg.allowedUsers == [ ] then "@users" else concatStringsSep " " cfg.allowedUsers;
          "create mask" = "0600";
          "directory mask" = "0700";
          "fruit:time machine" = "yes";
          "fruit:time machine max size" = if cfg.quota != null then cfg.quota else "0";
        };
      };
    };

    # Enable Avahi for Time Machine discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        userServices = true;
      };
    };

    # Systemd service to create and manage the ZFS dataset
    systemd.services.timemachine-zfs-setup = {
      description = "Create ZFS dataset for Time Machine backups";
      wantedBy = [ "multi-user.target" ];
      before = [ "samba.service" ];
      path = [ pkgs.zfs ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        # Check if the dataset already exists
        if ! zfs list ${datasetPath} &>/dev/null; then
          echo "Creating ZFS dataset: ${datasetPath}"
          zfs create ${datasetPath}

          # Set compression
          zfs set compression=${cfg.compression} ${datasetPath}

          # Set mountpoint
          zfs set mountpoint=${mountPoint} ${datasetPath}

          ${optionalString (cfg.quota != null) ''
            # Set quota if specified
            echo "Setting quota: ${cfg.quota}"
            zfs set quota=${cfg.quota} ${datasetPath}
          ''}

          echo "ZFS dataset ${datasetPath} created successfully"
        else
          echo "ZFS dataset ${datasetPath} already exists"

          # Ensure mountpoint is correct even if dataset exists
          current_mountpoint=$(zfs get -H -o value mountpoint ${datasetPath})
          if [ "$current_mountpoint" != "${mountPoint}" ]; then
            echo "Updating mountpoint to ${mountPoint}"
            zfs set mountpoint=${mountPoint} ${datasetPath}
          fi
        fi

        # Ensure the mount point directory exists and has correct permissions
        mkdir -p ${mountPoint}
        chmod 0755 ${mountPoint}
      '';
    };

    # Ensure firewall allows Samba traffic
    networking.firewall.allowedTCPPorts = [ 139 445 ];
    networking.firewall.allowedUDPPorts = [ 137 138 ];

    # Add helpful packages
    environment.systemPackages = with pkgs; [
      samba
    ];
  };
}
