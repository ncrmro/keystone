{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.containers;
in {
  options.keystone.terminal.containers = {
    enable = mkEnableOption "Container development tools (rootless Docker + Kind)";

    docker = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable rootless Docker for container operations";
      };
    };

    kind = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Kind (Kubernetes in Docker) for local K8s development";
      };
    };

    kubectl = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable kubectl for Kubernetes cluster management";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install container tools in user environment
    home.packages = with pkgs; [
      # Docker client for rootless Docker
      (mkIf cfg.docker.enable docker-client)
      # Kind for local Kubernetes clusters
      (mkIf cfg.kind.enable kind)
      # kubectl for Kubernetes management
      (mkIf cfg.kubectl.enable kubectl)
      # Additional helpful tools
      (mkIf cfg.kubectl.enable kubernetes-helm)
      (mkIf cfg.docker.enable docker-compose)
    ];

    # Configure Docker rootless
    home.sessionVariables = mkIf cfg.docker.enable {
      # Point Docker client to user's rootless Docker socket
      DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";
    };

    # Add shell aliases for common tasks
    programs.zsh.shellAliases = mkMerge [
      (mkIf cfg.kind.enable {
        "kind-create" = "kind create cluster --name keystone";
        "kind-delete" = "kind delete cluster --name keystone";
        "kind-load" = "kind load docker-image";
      })
      (mkIf cfg.kubectl.enable {
        "k" = "kubectl";
        "kgp" = "kubectl get pods";
        "kgs" = "kubectl get svc";
        "kgn" = "kubectl get nodes";
        "kctx" = "kubectl config use-context";
      })
    ];

    # Add completion for kubectl and docker
    programs.zsh.initExtra = mkIf cfg.kubectl.enable ''
      # kubectl completion
      if command -v kubectl &> /dev/null; then
        source <(kubectl completion zsh)
      fi
    '';

    # Create helper scripts
    home.file.".local/bin/kind-setup" = mkIf cfg.kind.enable {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Setup Kind cluster with rootless Docker
        set -euo pipefail

        CLUSTER_NAME="''${1:-keystone}"

        echo "Setting up Kind cluster: $CLUSTER_NAME"

        # Check if Docker is running
        if ! docker info &>/dev/null; then
          echo "Error: Docker is not running or not accessible"
          echo "Make sure rootless Docker service is running:"
          echo "  systemctl --user status docker"
          exit 1
        fi

        # Create Kind cluster
        kind create cluster \
          --name "$CLUSTER_NAME" \
          --config /dev/stdin <<EOF
        kind: Cluster
        apiVersion: kind.x-k8s.io/v1alpha4
        nodes:
        - role: control-plane
          extraPortMappings:
          - containerPort: 30000
            hostPort: 30000
            protocol: TCP
        EOF

        echo ""
        echo "✅ Kind cluster '$CLUSTER_NAME' created successfully!"
        echo ""
        echo "To use this cluster:"
        echo "  kubectl cluster-info --context kind-$CLUSTER_NAME"
        echo ""
        echo "To delete this cluster:"
        echo "  kind delete cluster --name $CLUSTER_NAME"
      '';
    };

    home.file.".local/bin/kind-test-operator" = mkIf (cfg.kind.enable && cfg.kubectl.enable) {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Test the Keystone operator in Kind
        set -euo pipefail

        CLUSTER_NAME="''${1:-keystone}"

        echo "Testing Keystone operator in Kind cluster: $CLUSTER_NAME"

        # Check if cluster exists
        if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
          echo "Error: Cluster '$CLUSTER_NAME' does not exist"
          echo "Run: kind-setup $CLUSTER_NAME"
          exit 1
        fi

        # Set kubectl context
        kubectl config use-context "kind-$CLUSTER_NAME"

        # Check cluster status
        echo ""
        echo "📋 Cluster info:"
        kubectl cluster-info
        echo ""
        kubectl get nodes

        echo ""
        echo "✅ Cluster is ready for operator testing!"
        echo ""
        echo "Next steps:"
        echo "1. Build operator: cd packages/keystone-ha/operator && cargo build"
        echo "2. Build image: docker build -t keystone-ha-operator:dev ."
        echo "3. Load into Kind: kind load docker-image keystone-ha-operator:dev --name $CLUSTER_NAME"
        echo "4. Deploy CRDs and operator manifests"
      '';
    };
  };
}
