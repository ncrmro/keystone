# Whisper.cpp speech-to-text server with GPU acceleration.
#
# Auto-enables when keystone.services.whisper.host matches this machine.
# Binds 0.0.0.0 by default so other tailnet machines can reach the API.
#
# Usage (in services registry):
#   keystone.services.whisper = {
#     host = "ncrmro-workstation";
#     acceleration = "rocm";
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  svcCfg = config.keystone.services.whisper;
  isWhisperHost = svcCfg.host != null && svcCfg.host == config.networking.hostName;

  whisperPackage =
    if svcCfg.acceleration == "rocm" then
      pkgs.whisper-cpp.override { rocmSupport = true; }
    else if svcCfg.acceleration == "cuda" then
      pkgs.whisper-cpp.override { cudaSupport = true; }
    else if svcCfg.acceleration == "vulkan" then
      pkgs.whisper-cpp.override { vulkanSupport = true; }
    else
      pkgs.whisper-cpp;

  modelFile = "ggml-${svcCfg.model}.bin";
  modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${modelFile}";
in
{
  config = mkIf isWhisperHost {
    systemd.services.whisper-server = {
      description = "Whisper.cpp speech-to-text server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "whisper";
        ExecStart = "${whisperPackage}/bin/whisper-server --model /var/lib/whisper/${modelFile} --host 0.0.0.0 --port ${toString svcCfg.port} --convert";
        Restart = "on-failure";
        RestartSec = 5;
      };

      path = [
        pkgs.curl
        pkgs.ffmpeg
      ];

      preStart = ''
        if [ ! -f /var/lib/whisper/${modelFile} ]; then
          echo "whisper-server: downloading model '${svcCfg.model}'"
          curl -fSL --progress-bar -o /var/lib/whisper/${modelFile}.tmp ${modelUrl}
          mv /var/lib/whisper/${modelFile}.tmp /var/lib/whisper/${modelFile}
        fi
      '';
    };

    networking.firewall.allowedTCPPorts = [ svcCfg.port ];
  };
}
