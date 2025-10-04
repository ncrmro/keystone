{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.client.desktop.audio;
in
{
  options.keystone.client.desktop.audio = {
    enable = mkEnableOption "PipeWire audio system";
  };

  config = mkIf cfg.enable {
    # Enable real-time audio priority
    security.rtkit.enable = true;

    # Disable PulseAudio (conflicts with PipeWire)
    services.pulseaudio.enable = false;

    # Enable PipeWire audio system
    services.pipewire = {
      enable = true;

      # Enable compatibility layers
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # Audio control packages
    environment.systemPackages = with pkgs; [
      # Volume and audio controls
      pamixer
      pavucontrol
      playerctl

      # Audio utilities
      alsa-utils
    ];
  };
}
