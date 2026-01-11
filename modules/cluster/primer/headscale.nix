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
with lib;
let
  cfg = config.keystone.cluster.primer.headscaleDeployment;
  primerCfg = config.keystone.cluster.primer;
in
{
  options.keystone.cluster.primer.headscaleDeployment = {
    enable = mkEnableOption "Headscale deployment in k3s";

    useAgenixSecrets = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Use agenix-managed secrets for Headscale keys.
        When enabled, expects secrets at /run/agenix/headscale-{private,noise,derp}
        and creates a Kubernetes Secret from them before deployment.
      '';
    };

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

  options.keystone.cluster.primer.headscale = {
    storage = {
      type = mkOption {
        type = types.enum [
          "pvc"
          "ephemeral"
        ];
        default = "pvc";
        description = "Storage type for Headscale data (pvc or ephemeral/emptyDir)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Create K8s Secret from agenix-decrypted files (when agenix secrets enabled)
    systemd.services.headscale-secrets = mkIf cfg.useAgenixSecrets {
      description = "Create Kubernetes secrets for Headscale from agenix";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s-ready.service" ];
      before = [ "headscale-deploy.service" ];
      requires = [ "k3s-ready.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
      };

      script =
        let
          namespace = primerCfg.headscale.namespace;
        in
        ''
          set -euo pipefail

          echo "Creating Headscale K8s secrets from agenix..."

          # Ensure namespace exists
          ${pkgs.kubectl}/bin/kubectl create namespace ${namespace} --dry-run=client -o yaml | \
            ${pkgs.kubectl}/bin/kubectl apply -f -

          # Create Secret from agenix-decrypted files
          ${pkgs.kubectl}/bin/kubectl create secret generic headscale-keys \
            --namespace=${namespace} \
            --from-file=private.key=/run/agenix/headscale-private \
            --from-file=noise_private.key=/run/agenix/headscale-noise \
            --from-file=derp_private.key=/run/agenix/headscale-derp \
            --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -

          echo "Headscale K8s secrets created successfully!"
        '';
    };

    # Create systemd service to deploy Headscale manifests after k3s is ready
    systemd.services.headscale-deploy = {
      description = "Deploy Headscale to k3s";
      wantedBy = [ "multi-user.target" ];
      after = [
        "k3s-ready.service"
      ]
      ++ (if cfg.useAgenixSecrets then [ "headscale-secrets.service" ] else [ ]);
      requires = [
        "k3s-ready.service"
      ]
      ++ (if cfg.useAgenixSecrets then [ "headscale-secrets.service" ] else [ ]);

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
      };

      script =
        let
          namespace = primerCfg.headscale.namespace;

          # Storage configuration
          pvcResource =
            if primerCfg.headscale.storage.type == "pvc" then
              ''
                apiVersion: v1
                kind: PersistentVolumeClaim
                metadata:
                  name: headscale-data
                  namespace: @@namespace@@
                spec:
                  accessModes:
                    - ReadWriteOnce
                  resources:
                    requests:
                      storage: 1Gi
              ''
            else
              "";

          dataVolume =
            if primerCfg.headscale.storage.type == "pvc" then
              ''
                - name: data
                  persistentVolumeClaim:
                    claimName: headscale-data
              ''
            else
              ''
                - name: data
                  emptyDir: {}
              '';

          # Volume mounts for keys (if using agenix secrets)
          # Note: YAML must have exact indentation for the template position (12 spaces for volumeMounts)
          keysVolumeMounts =
            if cfg.useAgenixSecrets then
              "            - name: keys\n              mountPath: /var/lib/headscale/private.key\n              subPath: private.key\n              readOnly: true\n            - name: keys\n              mountPath: /var/lib/headscale/noise_private.key\n              subPath: noise_private.key\n              readOnly: true\n            - name: keys\n              mountPath: /var/lib/headscale/derp_private.key\n              subPath: derp_private.key\n              readOnly: true"
            else
              "";

          # Keys volume definition (if using agenix secrets)
          # Note: YAML must have exact indentation for the template position (8 spaces for volumes)
          keysVolume =
            if cfg.useAgenixSecrets then
              "        - name: keys\n          secret:\n            secretName: headscale-keys\n            defaultMode: 256"
            else
              "";

          # Generate manifest from external YAML template
          # The YAML file uses @@placeholder@@ syntax for substitution
          # Using builtins.replaceStrings handles multiline values correctly
          manifestTemplate = builtins.readFile ./headscale-manifests.yaml;
          manifestContent =
            builtins.replaceStrings
              [
                "@@namespace@@"
                "@@serverUrl@@"
                "@@baseDomain@@"
                "@@replicas@@"
                "@@image@@"
                "@@requestsCpu@@"
                "@@requestsMemory@@"
                "@@limitsCpu@@"
                "@@limitsMemory@@"
                "@@pvcResource@@"
                "@@dataVolume@@"
                "@@keysVolumeMounts@@"
                "@@keysVolume@@"
              ]
              [
                namespace
                primerCfg.headscale.serverUrl
                primerCfg.headscale.baseDomain
                (toString cfg.replicas)
                cfg.image
                cfg.resources.requests.cpu
                cfg.resources.requests.memory
                cfg.resources.limits.cpu
                cfg.resources.limits.memory
                pvcResource
                dataVolume
                keysVolumeMounts
                keysVolume
              ]
              manifestTemplate;
          headscaleManifests = pkgs.writeText "headscale-manifests.yaml" manifestContent;
        in
        ''
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
