# Keystone Terminal Perception
#
# Installs CLI tools for the perception layer:
# - pdf-extract: PDF to markdown with bounding box citations (poppler + tesseract)
# - whisper-transcribe: local audio transcription via whisper.cpp
# - immich-search: Immich REST API search (smart, person, recent)
# - voice-recorder: PipeWire microphone capture helper
#
# Implements REQ-024.36 (terminal perception.enable option).
# Implements REQ-024.40 (standalone CLI commands for agents and task loops).
#
# ## Example
#
# ```nix
# keystone.terminal.perception = {
#   enable = true;
# };
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.perception;
in
{
  options.keystone.terminal.perception = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable perception CLI tools (PDF parsing, voice transcription, photo search).";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.pdf-extract
      pkgs.keystone.whisper-transcribe
      pkgs.keystone.immich-search
      pkgs.keystone.voice-recorder
    ];
  };
}
