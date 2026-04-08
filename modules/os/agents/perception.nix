# Agent perception layer: screenshot sync and activity processor as systemd user services.
#
# Implements REQ-023 (Perception Layer) — screenshot sync replaces the former
# Immich-upload approach with rsync-over-SSH to the Immich host filesystem.
# The Immich host is expected to have an external library path mounted at
# screenshotRoot (configured in modules/os/immich.nix).
#
# Services created per agent (when perception.enable = true):
# - agent-{name}-screenshot-sync: rsyncs screenshots to the Immich host over SSH
# - agent-{name}-perception-processor: collects PDFs, transcripts, photos → notes
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg localAgents;
  immichServiceCfg = config.keystone.services.immich;

  hostname = config.networking.hostName;
  immichHost = config.keystone.services.immich.host;

  # Filter to agents with perception enabled
  perceptionAgents = filterAttrs (_: agentCfg: agentCfg.perception.enable) localAgents;

  # Filter to agents with perception + desktop + screenshots enabled
  screenshotAgents = filterAttrs (
    _: agentCfg: agentCfg.desktop.enable && agentCfg.perception.screenshots.enable
  ) perceptionAgents;

  # Resolve rsync destination for a given agent
  rsyncDestFor =
    name: agentCfg:
    let
      username = "agent-${name}";
    in
    if agentCfg.perception.screenshots.rsyncDestPath != null then
      agentCfg.perception.screenshots.rsyncDestPath
    else
      "/srv/screenshots/${username}/hosts/${hostname}/Pictures/";

  # Resolve rsync target host for a given agent
  rsyncTargetFor =
    _name: agentCfg:
    if agentCfg.perception.screenshots.rsyncTarget != null then
      agentCfg.perception.screenshots.rsyncTarget
    else
      immichHost;
in
{
  config = mkIf (osCfg.enable && perceptionAgents != { }) {
    assertions = optionals (screenshotAgents != { }) [
      {
        assertion = immichServiceCfg.host != null;
        message = "Agent screenshot sync requires keystone.services.immich.host to be set.";
      }
    ];

    systemd.user.services = mkMerge (
      # Screenshot sync services (only for agents with desktop + screenshots enabled)
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          agentHome = "/home/${username}";
          rsyncTarget = rsyncTargetFor name agentCfg;
          rsyncDest = rsyncDestFor name agentCfg;
        in
        mkIf agentCfg.perception.screenshots.enable {
          "agent-${name}-screenshot-sync" = {
            description = "Sync screenshots to ${rsyncTarget} for ${username}";
            unitConfig.ConditionUser = username;
            serviceConfig = {
              Type = "oneshot";
              SyslogIdentifier = "agent-${name}-screenshot-sync";
            };
            path = [
              pkgs.rsync
              pkgs.openssh
            ];
            # Rsync screenshots over SSH using the agent's managed key.
            # No Immich API key required — files land in the Immich external library path.
            script = ''
              [[ -f ${agentHome}/.config/user-dirs.dirs ]] && source ${agentHome}/.config/user-dirs.dirs
              SCREENSHOT_DIR="''${KEYSTONE_SCREENSHOT_DIR:-''${XDG_PICTURES_DIR:-${agentHome}/Pictures}}"

              if [[ ! -d "$SCREENSHOT_DIR" ]]; then
                echo "screenshot-sync: source directory does not exist: $SCREENSHOT_DIR" >&2
                exit 0
              fi

              rsync \
                --archive \
                --compress \
                --checksum \
                --mkpath \
                --rsh "ssh -i ${agentHome}/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
                "$SCREENSHOT_DIR/" \
                "${rsyncTarget}:${rsyncDest}"
            '';
          };
        }
      ) screenshotAgents)
      ++
        # Perception processor services (for all perception agents)
        (mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          mkIf agentCfg.perception.processor.enable {
            "agent-${name}-perception-processor" = {
              description = "Perception processor for ${username}";
              unitConfig.ConditionUser = username;
              environment = {
                PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
              };
              serviceConfig = {
                Type = "oneshot";
                TimeoutStartSec = "30m";
                SyslogIdentifier = "agent-${name}-perception-processor";
              };
              # Placeholder — actual script added in feat/perception-processor
              script = ''
                echo "perception-processor: not yet implemented for ${username}"
              '';
            };
          }
        ) perceptionAgents)
    );

    systemd.user.timers = mkMerge (
      # Screenshot sync timers
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        mkIf (agentCfg.perception.screenshots.enable && agentCfg.desktop.enable) {
          "agent-${name}-screenshot-sync" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.perception.screenshots.syncOnCalendar;
              Persistent = true;
            };
          };
        }
      ) screenshotAgents)
      ++
        # Perception processor timers
        (mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          mkIf agentCfg.perception.processor.enable {
            "agent-${name}-perception-processor" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.perception.processor.onCalendar;
                Persistent = true;
              };
            };
          }
        ) perceptionAgents)
    );
  };
}
