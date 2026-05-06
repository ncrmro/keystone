# Immich Photo Management System
#
# Automatically configured based on keystone.services.immich:
# - host: The primary server (DB + Web)
# - workers: Remote GPU/ML workers
#
# Roles are auto-detected by hostname.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  services = config.keystone.services;
  hostName = config.networking.hostName;

  # Role detection
  isServer = services.immich.host == hostName;
  isWorker = elem hostName services.immich.workers;

  # Worker URL discovery
  getWorkerUrl =
    hName:
    let
      hostEntry = findFirst (h: h.hostname == hName) null (attrValues config.keystone.hosts);
      target =
        if hostEntry != null then
          (if hostEntry.sshTarget != null then hostEntry.sshTarget else hostEntry.fallbackIP)
        else
          hName;
    in
    "http://${target}:3003";

  # Server connects to the first worker if available, otherwise localhost
  mlUrl =
    if length services.immich.workers > 0 then
      getWorkerUrl (head services.immich.workers)
    else
      "http://localhost:3003";

  cfg = config.keystone.os.services.immich;
in
{
  options.keystone.os.services.immich = {
    enable = mkOption {
      type = types.bool;
      default = isServer || isWorker;
      description = "Auto-enabled if host matches keystone.services.immich host or workers.";
    };

    role = mkOption {
      type = types.enum [
        "server"
        "worker"
      ];
      default = if isServer then "server" else "worker";
      description = "Auto-detected role.";
    };

    acceleration = mkOption {
      type = types.nullOr (
        types.enum [
          "rocm"
          "cuda"
        ]
      );
      default = if isWorker then "rocm" else null;
      description = "GPU acceleration for workers. Defaults to rocm if host is a worker.";
    };

    hsaGfxVersion = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "11.0.0";
      description = ''
        HSA_OVERRIDE_GFX_VERSION override for ROCm GPU compatibility.

        Set this only when the ROCm build in nixpkgs does not support your
        AMD GPU's native gfx target. ROCm 6.x supports gfx1100 (RX 7900
        XTX / XT) natively, so leave this unset for those cards unless you
        observe runtime failures.

        Common override values:
        - RX 7900 XTX (RDNA 3 / gfx1100): "11.0.0" (usually unnecessary)
        - RX 9070 series (RDNA 4 / gfx1201): "12.0.1"
      '';
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
    assertions = [
      {
        assertion = cfg.hsaGfxVersion == null || cfg.acceleration == "rocm";
        message = ''
          keystone.os.services.immich.hsaGfxVersion only applies when
          keystone.os.services.immich.acceleration = "rocm".
        '';
      }
    ];

    services.immich = mkMerge [
      # Common config
      {
        enable = true;
        machine-learning.environment = {
          MPLCONFIGDIR = "/var/cache/immich/matplotlib";
        };
      }
      # ROCm-enabled onnxruntime, scoped to the immich package only.
      # Avoids a system-wide nixpkgs.overlays that would rebuild onnxruntime
      # for every unrelated consumer.
      #
      # The python `onnxruntime` is a thin wrapper around the C++
      # `pkgs.onnxruntime`; `rocmSupport` is an argument of the *C++* build,
      # so we override the C++ input *of* the python wrapper, not the
      # wrapper itself.
      (mkIf (cfg.acceleration == "rocm") {
        package =
          let
            onnxruntimeRocm = pkgs.onnxruntime.override { rocmSupport = true; };
          in
          (pkgs.immich.override {
            immich-machine-learning = pkgs.immich-machine-learning.override {
              python3 = pkgs.python3.override {
                self = pkgs.python3;
                packageOverrides = pyfinal: pyprev: {
                  onnxruntime = pyprev.onnxruntime.override {
                    onnxruntime = onnxruntimeRocm;
                  };
                };
              };
            };
          }).overrideAttrs
            (old: {
              passthru = (old.passthru or { }) // {
                keystoneRocmEnabled = true;
                keystoneOnnxruntimeRocm = onnxruntimeRocm;
              };
            });
      })
      # Server-specific
      (mkIf (cfg.role == "server") {
        host = cfg.host;
        port = cfg.port;
        mediaLocation = cfg.mediaLocation;
        machine-learning.enable = length services.immich.workers == 0;
        settings.machineLearning.url = mlUrl;
        environment.IMMICH_MACHINE_LEARNING_URL = lib.mkForce mlUrl;
      })
      # Worker-specific
      (mkIf (cfg.role == "worker") {
        # Disable non-ML components
        database.enable = false;
        redis.enable = false;
        # Satisfy module defaults and assertions
        redis.host = "localhost";
        database.host = "localhost";
        # Dummy secrets file path to satisfy assertion when database is disabled but host is set
        secretsFile = "${pkgs.writeText "immich-dummy-secrets" "DB_PASSWORD=unused"}";
        # Bind ML server to all interfaces so it's reachable over Tailscale
        machine-learning.environment.IMMICH_HOST = lib.mkForce "0.0.0.0";
      })
      # Acceleration: any GPU backend needs the upstream module's
      # PrivateDevices sandbox lifted, otherwise /dev/kfd and /dev/dri/* are
      # invisible to the unit and ROCm/CUDA cannot initialize. `null` means
      # "allow all devices"; downstreams that want a tighter list can set
      # services.immich.accelerationDevices explicitly to override this.
      (mkIf (cfg.acceleration != null) {
        accelerationDevices = lib.mkDefault null;
      })
      (mkIf (cfg.acceleration == "rocm") {
        # MIOpen and HIP cache paths: ROCm writes kernel/JIT caches under
        # $HOME by default, but the immich-machine-learning unit runs with a
        # restricted HOME. Pin them to the service's CacheDirectory so first
        # inference doesn't fail with "could not open user db" on clean
        # state directories.
        machine-learning.environment = {
          DEVICE = "rocm";
          MIOPEN_USER_DB_PATH = "/var/cache/immich/miopen";
          MIOPEN_CUSTOM_CACHE_DIR = "/var/cache/immich/miopen";
        }
        // lib.optionalAttrs (cfg.hsaGfxVersion != null) {
          HSA_OVERRIDE_GFX_VERSION = cfg.hsaGfxVersion;
        };
      })
    ];

    # Pre-create writable cache subdirs for matplotlib and MIOpen kernel
    # caches. Their parents already exist via the unit's CacheDirectory but
    # creating the leaves up-front avoids first-run races where systemd's
    # ProtectHome/PrivateTmp sandbox surprises the libraries.
    systemd.tmpfiles.rules = mkIf (cfg.acceleration != null) (
      [ "d /var/cache/immich/matplotlib 0700 immich immich -" ]
      ++ optionals (cfg.acceleration == "rocm") [
        "d /var/cache/immich/miopen 0700 immich immich -"
      ]
    );

    # Manually disable server units on worker
    systemd.services.immich-server.enable = mkIf (cfg.role == "worker") false;
    systemd.services.immich-microservices.enable = mkIf (cfg.role == "worker") false;

    # Auto-register service tags for ACL generation.
    # Only server/agent roles get tags — client roles stay user-owned in
    # Headscale (adding tags would strip user identity and break admin ACLs).
    keystone.os.tailscale.tags =
      if cfg.role == "server" then
        [ "tag:svc-immich" ]
      else if
        isWorker
        && (findFirst (h: h.hostname == hostName) null (attrValues config.keystone.hosts)).role != "client"
      then
        [ "tag:svc-immich-ml" ]
      else
        [ ];

    # GPU Acceleration configuration (groups)
    users.users.immich.extraGroups = mkIf (cfg.acceleration != null) [
      "video"
      "render"
    ];

    # Open ML port only on tailscale interface for worker access
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = mkIf (cfg.role == "worker") [ 3003 ];
  };
}
