# Keystone OS Agents Module
#
# Creates agent users with:
# - NixOS user accounts in the agents group (no sudo, no wheel)
# - UIDs from the 4000+ reserved range
# - Home directories at /home/agent-{name} (ZFS dataset or ext4)
# - chmod 700 isolation between agents
#
# Usage:
#   keystone.os.agents.researcher = {
#     fullName = "Research Agent";
#     email = "researcher@example.com";
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
  cfg = osCfg.agents;

  useZfs = osCfg.storage.type == "zfs";

  # Base UID for agent users
  agentUidBase = 4000;

  # Agent submodule type definition
  agentSubmodule = types.submodule ({name, ...}: {
    options = {
      uid = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "User ID. If null, auto-assigned from the 4000+ range.";
      };

      fullName = mkOption {
        type = types.str;
        description = "Display name for the agent";
        example = "Research Agent";
      };

      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Email address for the agent (used for git config and mail provisioning)";
        example = "researcher@ks.systems";
      };

      terminal = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable terminal development environment (zsh, helix, zellij, git)";
        };
      };
    };
  });

  # Sorted agent names for deterministic UID assignment
  sortedAgentNames = sort lessThan (attrNames cfg);

  # Auto-assign UIDs to agents that don't have explicit ones
  agentWithUid = name: agentCfg: let
    idx = findFirst (i: elemAt sortedAgentNames i == name) 0 (genList (x: x) (length sortedAgentNames));
    autoUid = agentUidBase + 1 + idx;
  in
    agentCfg
    // {
      uid =
        if agentCfg.uid != null
        then agentCfg.uid
        else autoUid;
    };

  agentsWithUids = mapAttrs agentWithUid cfg;
in {
  options.keystone.os.agents = mkOption {
    type = types.attrsOf agentSubmodule;
    default = {};
    description = ''
      Agent users with automatic NixOS user creation and home directory isolation.
      Agents are non-interactive users (no password login, no sudo) designed for
      LLM-driven autonomous operation.
    '';
    example = literalExpression ''
      {
        researcher = {
          fullName = "Research Agent";
          email = "researcher@ks.systems";
        };
      }
    '';
  };

  config = mkIf (osCfg.enable && cfg != {}) {
    assertions = [
      # All agent UIDs must be unique
      {
        assertion = let
          uids = mapAttrsToList (_: a: a.uid) agentsWithUids;
          uniqueUids = unique uids;
        in
          length uids == length uniqueUids;
        message = "All agent UIDs must be unique";
      }
      # Agent UIDs must not collide with human user UIDs
      {
        assertion = let
          agentUids = mapAttrsToList (_: a: a.uid) agentsWithUids;
          humanUids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) osCfg.users);
        in
          all (aUid: !elem aUid humanUids) agentUids;
        message = "Agent UIDs must not collide with human user UIDs";
      }
    ];

    # Create the agents group
    users.groups.agents = {};

    # Enable zsh if any agent has terminal enabled
    programs.zsh.enable = mkIf (any (a: a.terminal.enable) (attrValues cfg)) true;

    # Generate NixOS users for agents
    users.users =
      mapAttrs' (name: agentCfg: let
        username = "agent-${name}";
        resolved = agentsWithUids.${name};
      in
        nameValuePair username {
          isNormalUser = true;
          uid = resolved.uid;
          description = agentCfg.fullName;
          home = "/home/${username}";
          createHome = !useZfs;
          group = "agents";
          extraGroups = optionals useZfs ["zfs"];
          shell = mkIf agentCfg.terminal.enable pkgs.zsh;
          # No password — agents are non-interactive
        })
      cfg;

    # Home directory creation for ext4
    systemd.services.create-agent-homes = mkIf (!useZfs) {
      description = "Create and configure agent home directories";

      wantedBy = ["multi-user.target"];
      before = ["systemd-user-sessions.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${concatStringsSep "\n" (mapAttrsToList (name: agentCfg: let
            username = "agent-${name}";
          in ''
            if [ ! -d /home/${username} ]; then
              mkdir -p /home/${username}
            fi
            chown ${username}:agents /home/${username}
            chmod 700 /home/${username}
          '')
          cfg)}
      '';
    };

    # ZFS dataset creation for agent homes
    systemd.services.zfs-agent-datasets = mkIf useZfs {
      description = "Create ZFS datasets for agent home directories";

      wantedBy = ["multi-user.target"];
      after = ["zfs-mount.service"];
      before = ["systemd-user-sessions.service"];
      requires = ["zfs-mount.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [config.boot.zfs.package];

      script = ''
        set -euo pipefail

        # Create parent home dataset if needed
        if ! zfs list -H -o name rpool/crypt/home > /dev/null 2>&1; then
          zfs create -o mountpoint=/home rpool/crypt/home
        fi

        ${concatStringsSep "\n" (mapAttrsToList (name: agentCfg: let
            username = "agent-${name}";
          in ''
            zfs create -p -o mountpoint=/home/${username} rpool/crypt/home/${username} 2>/dev/null || true
            zfs set compression=lz4 rpool/crypt/home/${username}
            chown ${username}:agents /home/${username}
            chmod 700 /home/${username}
          '')
          cfg)}
      '';
    };
  };
}
