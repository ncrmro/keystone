# k3s Server Configuration for Primer
#
# Configures k3s in server mode with embedded etcd (dqlite).
# This provides the Kubernetes control plane for the cluster.
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.cluster.primer.k3s;
  primerCfg = config.keystone.cluster.primer;
in
{
  options.keystone.cluster.primer.k3s = {
    enable = mkEnableOption "k3s server on primer";

    clusterCidr = mkOption {
      type = types.str;
      default = "10.42.0.0/16";
      description = "CIDR for pod network";
    };

    serviceCidr = mkOption {
      type = types.str;
      default = "10.43.0.0/16";
      description = "CIDR for service network";
    };

    disableComponents = mkOption {
      type = types.listOf types.str;
      default = [ "traefik" ];
      description = "k3s components to disable";
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra flags to pass to k3s server";
    };
  };

  config = mkIf cfg.enable {
    # k3s server configuration
    services.k3s = {
      enable = true;
      role = "server";

      # Disable traefik by default (we'll use Cloudflare Tunnel later)
      extraFlags = concatStringsSep " " (
        [
          "--cluster-cidr=${cfg.clusterCidr}"
          "--service-cidr=${cfg.serviceCidr}"
          "--write-kubeconfig-mode=644"
        ]
        ++ (map (c: "--disable=${c}") cfg.disableComponents)
        ++ cfg.extraFlags
      );
    };

    # Ensure kubeconfig is available for the root user
    environment.variables = {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    };

    # Wait for k3s to be ready before running other services
    systemd.services.k3s-ready = {
      description = "Wait for k3s API to be ready";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        echo "Waiting for k3s API server..."
        timeout=120
        until ${pkgs.kubectl}/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml cluster-info &>/dev/null; do
          sleep 2
          timeout=$((timeout - 2))
          if [ $timeout -le 0 ]; then
            echo "Timeout waiting for k3s API server"
            exit 1
          fi
        done
        echo "k3s API server is ready"
      '';
    };
  };
}
