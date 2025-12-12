{
  lib,
  config,
  pkgs,
  ...
}:
with lib; {
  # Keystone Cluster Module
  # Provides Kubernetes control plane with cloud operator integration
  # See SPEC.md for full specification

  imports = [
    ../ssh
  ];

  options.keystone.cluster = {
    enable = mkEnableOption "Keystone cluster (Kubernetes control plane)";

    distribution = mkOption {
      type = types.enum ["k3s" "kubeadm"];
      default = "k3s";
      description = "Kubernetes distribution to use";
    };

    role = mkOption {
      type = types.enum ["control-plane" "worker" "control-plane+worker"];
      default = "control-plane";
      description = "Role of this node in the cluster";
    };
  };

  config = mkIf config.keystone.cluster.enable {
    # Placeholder - implementation coming in phases
    # See SPEC.md for implementation roadmap

    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      k9s
    ];
  };
}
