# Headscale Kubernetes Deployment for Primer
#
# Deploys Headscale as a Kubernetes workload in k3s.
# Uses the headscale container image with a ConfigMap for configuration.
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.cluster.primer.headscaleDeployment;
  primerCfg = config.keystone.cluster.primer;
in {
  options.keystone.cluster.primer.headscaleDeployment = {
    enable = mkEnableOption "Headscale deployment in k3s";

    image = mkOption {
      type = types.str;
      default = "headscale/headscale:0.23.0";
      description = "Headscale container image";
    };

    replicas = mkOption {
      type = types.int;
      default = 1;
      description = "Number of Headscale replicas";
    };

    resources = {
      requests = {
        cpu = mkOption {
          type = types.str;
          default = "100m";
          description = "CPU request for Headscale pods";
        };
        memory = mkOption {
          type = types.str;
          default = "128Mi";
          description = "Memory request for Headscale pods";
        };
      };
      limits = {
        cpu = mkOption {
          type = types.str;
          default = "500m";
          description = "CPU limit for Headscale pods";
        };
        memory = mkOption {
          type = types.str;
          default = "512Mi";
          description = "Memory limit for Headscale pods";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Create systemd service to deploy Headscale manifests after k3s is ready
    systemd.services.headscale-deploy = {
      description = "Deploy Headscale to k3s";
      wantedBy = ["multi-user.target"];
      after = ["k3s-ready.service"];
      requires = ["k3s-ready.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
      };

      script = let
        namespace = primerCfg.headscale.namespace;

        # Write manifest with properly indented inline config
        # Note: ConfigMap data uses literal block scalar (|) which preserves indentation
        headscaleManifests = pkgs.writeText "headscale-manifests.yaml" ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: ${namespace}
          ---
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: headscale-config
            namespace: ${namespace}
          data:
            config.yaml: |
              server_url: ${primerCfg.headscale.serverUrl}
              listen_addr: 0.0.0.0:8080
              metrics_listen_addr: 0.0.0.0:9090
              grpc_listen_addr: 0.0.0.0:50443
              grpc_allow_insecure: false
              private_key_path: /var/lib/headscale/private.key
              noise:
                private_key_path: /var/lib/headscale/noise_private.key
              prefixes:
                v4: 100.64.0.0/10
                v6: fd7a:115c:a1e0::/48
              derp:
                server:
                  enabled: true
                  private_key_path: /var/lib/headscale/derp_private.key
                  region_id: 999
                  region_code: "headscale"
                  region_name: "Headscale Embedded"
                  stun_listen_addr: "0.0.0.0:3478"
                urls:
                  - https://controlplane.tailscale.com/derpmap/default
                auto_update_enabled: true
                update_frequency: 24h
              disable_check_updates: false
              ephemeral_node_inactivity_timeout: 30m
              database:
                type: sqlite
                sqlite:
                  path: /var/lib/headscale/db.sqlite
              dns:
                magic_dns: true
                base_domain: ${primerCfg.headscale.baseDomain}
                nameservers:
                  global:
                    - 1.1.1.1
                    - 8.8.8.8
              log:
                format: text
                level: info
          ---
          apiVersion: v1
          kind: PersistentVolumeClaim
          metadata:
            name: headscale-data
            namespace: ${namespace}
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
          ---
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: headscale
            namespace: ${namespace}
            labels:
              app: headscale
          spec:
            replicas: ${toString cfg.replicas}
            selector:
              matchLabels:
                app: headscale
            template:
              metadata:
                labels:
                  app: headscale
              spec:
                containers:
                  - name: headscale
                    image: ${cfg.image}
                    command:
                      - headscale
                      - serve
                    ports:
                      - name: http
                        containerPort: 8080
                        protocol: TCP
                      - name: grpc
                        containerPort: 50443
                        protocol: TCP
                      - name: metrics
                        containerPort: 9090
                        protocol: TCP
                      - name: stun
                        containerPort: 3478
                        protocol: UDP
                    volumeMounts:
                      - name: config
                        mountPath: /etc/headscale
                        readOnly: true
                      - name: data
                        mountPath: /var/lib/headscale
                    resources:
                      requests:
                        cpu: ${cfg.resources.requests.cpu}
                        memory: ${cfg.resources.requests.memory}
                      limits:
                        cpu: ${cfg.resources.limits.cpu}
                        memory: ${cfg.resources.limits.memory}
                    livenessProbe:
                      httpGet:
                        path: /health
                        port: http
                      initialDelaySeconds: 10
                      periodSeconds: 10
                    readinessProbe:
                      httpGet:
                        path: /health
                        port: http
                      initialDelaySeconds: 5
                      periodSeconds: 5
                volumes:
                  - name: config
                    configMap:
                      name: headscale-config
                  - name: data
                    persistentVolumeClaim:
                      claimName: headscale-data
          ---
          apiVersion: v1
          kind: Service
          metadata:
            name: headscale
            namespace: ${namespace}
          spec:
            type: NodePort
            selector:
              app: headscale
            ports:
              - name: http
                port: 8080
                targetPort: http
                nodePort: 30080
              - name: grpc
                port: 50443
                targetPort: grpc
              - name: stun
                port: 3478
                targetPort: stun
                protocol: UDP
        '';
      in ''
        set -euo pipefail

        echo "Deploying Headscale to k3s..."

        # Apply manifests
        ${pkgs.kubectl}/bin/kubectl apply -f ${headscaleManifests}

        # Wait for deployment to be ready
        echo "Waiting for Headscale deployment..."
        ${pkgs.kubectl}/bin/kubectl wait --for=condition=available \
          --timeout=300s deployment/headscale -n ${namespace}

        # Create default user if it doesn't exist
        echo "Creating default user..."
        ${pkgs.kubectl}/bin/kubectl exec -n ${namespace} deploy/headscale -- \
          headscale users create default 2>/dev/null || true

        echo "Headscale deployed successfully!"
      '';
    };
  };
}
