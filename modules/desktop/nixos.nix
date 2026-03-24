# Keystone Desktop — NixOS-level system configuration.
# Implements REQ-002 (Keystone Desktop)
# See conventions/process.enable-by-default.md
{
  config,
  lib,
  pkgs,
  keystoneInputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  # nix-flatpak is imported via flake.nix nixosModules.desktop (hoisted to avoid
  # _module.args infinite recursion when keystoneInputs is used in imports)
  options.keystone.desktop = {
    enable = mkEnableOption "Keystone Desktop - Core desktop packages and utilities";

    obs = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable OBS Studio for screen recording and streaming";
      };
      gpuType = mkOption {
        type = types.nullOr (
          types.enum [
            "amd"
            "intel"
            "nvidia"
          ]
        );
        default = null;
        description = ''
          GPU type for hardware-accelerated encoding in OBS.
          - amd: enables VA-API and Vulkan capture plugins
          - intel: enables VA-API plugin
          - nvidia: enables Vulkan capture plugin (NVENC is built into OBS core)
          When null, only PipeWire audio capture is included (no GPU-specific plugins).
        '';
      };
    };

    user = mkOption {
      type = types.str;
      description = "User for auto-login to Hyprland session";
    };

    hyprland = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Hyprland window manager";
      };
    };

    greetd = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Greetd display manager";
      };
    };

    audio = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Pipewire audio stack";
      };
    };

    bluetooth = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Bluetooth support";
      };
    };

    networking = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NetworkManager and systemd-resolved for laptops, portables, and thin clients";
      };
    };
  };

  config = mkIf cfg.enable {
    # Flatpak support (declarative via nix-flatpak)
    services.flatpak.enable = mkDefault true;

    # Hyprland with UWSM (using official flake for latest features)
    programs.hyprland = mkIf cfg.hyprland.enable {
      enable = mkDefault true;
      withUWSM = mkDefault true;
      package = mkDefault keystoneInputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage = mkDefault pkgs.xdg-desktop-portal-hyprland; # Use stable nixpkgs version to fix Qt version mismatch
    };

    # Greetd display manager with auto-login to Hyprland
    # CRITICAL: XDG_SESSION_CLASS=user must be in the command environment so pam_systemd.so
    # sees it before registering the logind session. The PAM class= argument alone is not
    # sufficient — pam_systemd gives XDG_SESSION_CLASS env var highest precedence.
    # Without this, the session registers as Class=greeter on seat0, causing polkit's
    # allow_active=yes policy to deny access — breaking pcscd, YubiKey PIV, and power management.
    services.greetd = mkIf cfg.greetd.enable {
      enable = mkDefault true;
      settings.default_session = {
        command = mkDefault "env XDG_SESSION_CLASS=user uwsm start -F Hyprland";
        user = cfg.user;
      };
    };

    # Configure PAM to register greetd session as wayland type
    # This enables loginctl lock-session to work properly
    security.pam.services.greetd.rules.session.systemd.settings = mkIf cfg.greetd.enable {
      type = "wayland";
      # Belt-and-suspenders: also set class=user in PAM for any code path that doesn't
      # inherit the env var. The env var takes precedence per pam_systemd docs.
      class = "user";
    };

    # Pipewire audio stack
    security.rtkit.enable = mkIf cfg.audio.enable (mkDefault true);
    services.pulseaudio.enable = mkIf cfg.audio.enable (mkDefault false);
    services.pipewire = mkIf cfg.audio.enable {
      enable = mkDefault true;
      alsa.enable = mkDefault true;
      pulse.enable = mkDefault true;
      jack.enable = mkDefault true;
    };

    # Bluetooth
    hardware.bluetooth.enable = mkIf cfg.bluetooth.enable (mkDefault true);
    services.blueman.enable = mkIf cfg.bluetooth.enable (mkDefault true);

    # Printing (CUPS + Avahi/mDNS discovery)
    services.printing.enable = mkDefault true;
    services.avahi = {
      enable = mkDefault true;
      nssmdns4 = mkDefault true;
      openFirewall = mkDefault true;
    };

    # Networking (for laptops, portables, and thin clients)
    networking.networkmanager.enable = mkIf cfg.networking.enable (mkDefault true);
    services.resolved.enable = mkIf cfg.networking.enable (mkDefault true);
    # Required for Tailscale MagicDNS to work with systemd-resolved
    # https://github.com/NixOS/nixpkgs/issues/231191#issuecomment-1664053176
    environment.etc."resolv.conf".mode = mkIf cfg.networking.enable "direct-symlink";

    # Fonts
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
    ];

    # System packages for desktop environment
    environment.systemPackages =
      with pkgs;
      [
        # Screen recording
        gpu-screen-recorder

        # Media
        ## Video Editor
        ## kdenlive disabled: broken in nixpkgs unstable (missing shaderc link in ffmpeg-full)
        # kdePackages.kdenlive
        ## Video Player
        mpv

        # File management
        nautilus
        file-roller

        # System utilities
        pavucontrol
        networkmanagerapplet
        blueberry

        # XDG portals and desktop integration
        xdg-utils
        xdg-user-dirs

        # Polkit agent
        hyprpolkitagent

        # Cursor themes
        adwaita-icon-theme

        # Additional Hyprland tools
        hyprsunset
        hyprlock
        hypridle
        hyprpaper
      ]
      ++ optionals cfg.obs.enable [
        (wrapOBS {
          plugins =
            with obs-studio-plugins;
            [
              obs-pipewire-audio-capture
            ]
            ++ optionals (cfg.obs.gpuType == "amd") [
              obs-vaapi
              obs-vkcapture
            ]
            ++ optionals (cfg.obs.gpuType == "intel") [
              obs-vaapi
            ]
            ++ optionals (cfg.obs.gpuType == "nvidia") [
              obs-vkcapture
            ];
        })
      ];

    # Enable polkit
    security.polkit.enable = mkDefault true;

    # XDG portal configuration
    xdg.portal = {
      enable = mkDefault true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };

    # This allows shell scripts to resolve /bin/bash
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    ];

    # OOM Killer configuration
    # Prioritize killing docker/podman rootless processes over Hyprland.
    # Hyprland (via UWSM wayland-wm@ template) uses the systemd default of 0.
    # Setting docker/podman to +1000 ensures they are killed first in OOM scenarios.
    #
    # NOTE: We cannot set OOMScoreAdjust for wayland-wm@Hyprland directly because
    # NixOS creates a replacement unit instead of a drop-in override, which removes
    # ExecStart and breaks the UWSM template-based service entirely.
    systemd.user.services = {
      docker.serviceConfig.OOMScoreAdjust = 1000;
      podman.serviceConfig.OOMScoreAdjust = 1000;
    };
  };
}
