# Keystone OS Containers Module
#
# Enables rootless Docker for users with containers.enable = true
# Configures system to support Kind (Kubernetes in Docker) for local development
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
  cfg = osCfg.users;

  # Filter users who have containers enabled
  containerUsers = filterAttrs (_: u: u.containers.enable) cfg;
  hasContainerUsers = containerUsers != {};
in {
  config = mkIf (osCfg.enable && hasContainerUsers) {
    # Enable rootless Docker support at system level
    virtualisation.docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
      # Enable auto-prune to clean up unused resources
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    # Add container users to docker group for rootless access
    users.users = mapAttrs (username: userCfg:
      mkIf userCfg.containers.enable {
        extraGroups = ["docker"];
      })
    containerUsers;

    # Install system packages for container development
    environment.systemPackages = with pkgs; [
      docker-client
      kind
      kubectl
      kubernetes-helm
      docker-compose
    ];

    # Enable necessary kernel modules for containers
    boot.kernelModules = [
      "ip_tables"
      "ip6_tables"
      "iptable_filter"
      "iptable_nat"
      "overlay"
      "br_netfilter"
    ];

    # Sysctl settings for containers
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      # Increase inotify limits for container development
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 512;
    };

    # Create systemd service to start Docker rootless for container users
    # This ensures Docker is running when user logs in
    systemd.user.services = listToAttrs (map (username: {
      name = "docker-rootless-${username}";
      value = {
        description = "Docker Rootless for ${username}";
        wantedBy = ["default.target"];
        after = ["network.target"];
        
        serviceConfig = {
          Type = "notify";
          ExecStart = "${pkgs.docker}/bin/dockerd-rootless --config-file=%h/.config/docker/daemon.json";
          ExecReload = "${pkgs.coreutils}/bin/kill -s HUP $MAINPID";
          TimeoutStartSec = "0";
          RestartSec = "2";
          Restart = "always";
          StartLimitBurst = "3";
          StartLimitInterval = "60s";
          LimitNOFILE = "infinity";
          LimitNPROC = "infinity";
          LimitCORE = "infinity";
          Delegate = "yes";
          KillMode = "mixed";
        };

        environment = {
          PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
          DOCKERD_ROOTLESS_ROOTLESSKIT_STATE_DIR = "%t/docker-rootless";
          DOCKERD_ROOTLESS_ROOTLESSKIT_NET = "slirp4netns";
          DOCKERD_ROOTLESS_ROOTLESSKIT_MTU = "1500";
        };
      };
    }) (attrNames containerUsers));
  };
}
