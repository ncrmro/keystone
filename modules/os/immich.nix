# Immich Photo Management System
#
# Automatically configured based on keystone.services.immich:
# - host: The primary server (DB + Web)
# - backends: Remote GPU/ML workers
#
# Roles are auto-detected by hostname.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  services = config.keystone.services;
  hostName = config.networking.hostName;

  # Role detection
  isServer = services.immich.host == hostName;
  isBackend = elem hostName services.immich.backends;

  # Backend URL discovery
  getBackendUrl = hName: let
    hostEntry = findFirst (h: h.hostname == hName) null (attrValues config.keystone.hosts);
    target = if hostEntry != null then 
      (if hostEntry.sshTarget != null then hostEntry.sshTarget else hostEntry.fallbackIP) 
      else hName;
  in "http://${target}:3003";

  # Server connects to the first backend if available, otherwise localhost
  mlUrl = if length services.immich.backends > 0 
          then getBackendUrl (head services.immich.backends)
          else "http://localhost:3003";

  cfg = config.keystone.os.services.immich;
in {
  options.keystone.os.services.immich = {
    enable = mkOption {
      type = types.bool;
      default = isServer || isBackend;
      description = "Auto-enabled if host matches keystone.services.immich host or backends.";
    };

    role = mkOption {
      type = types.enum ["server" "worker"];
      default = if isServer then "server" else "worker";
      description = "Auto-detected role.";
    };

    acceleration = mkOption {
      type = types.nullOr (types.enum ["rocm" "cuda"]);
      default = if isBackend then "rocm" else null;
      description = "GPU acceleration for backends. Defaults to rocm if host is a backend.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 2283;
    };

    mediaLocation = mkOption {
      type = types.path;
      default = "/var/lib/immich";
    };
  };

  config = mkIf cfg.enable {
    services.immich = {
      enable = true;
      host = cfg.host;
      port = cfg.port;
      mediaLocation = cfg.mediaLocation;

      # Enable ML by default, but server offloads it to backends
      machine-learning.enable = true;

      # Server-specific: Connect to remote ML
      settings.machineLearning.url = mkIf (cfg.role == "server") mlUrl;

      # Worker-specific: Disable non-ML components
      database.enable = mkIf (cfg.role == "worker") (lib.mkForce false);
      redis.enable = mkIf (cfg.role == "worker") (lib.mkForce false);
    };

    # GPU Acceleration configuration
    users.users.immich.extraGroups = mkIf (cfg.acceleration != null) ["video" "render"];

    services.immich.machine-learning.environment = mkIf (cfg.acceleration == "rocm") {
      DEVICE = "rocm";
      HSA_OVERRIDE_GFX_VERSION = "10.3.0"; # Consumer GPU support
    };

    # Open port for worker access
    networking.firewall.allowedTCPPorts = mkIf (cfg.role == "worker") [3003];
  };
}
