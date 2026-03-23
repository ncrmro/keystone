# Keystone Terminal Perception
#
# Installs CLI tools for the perception layer:
# - pdf-extract: PDF to markdown with bounding box citations
# - whisper-transcribe: local audio transcription via whisper.cpp
# - Keystone Photos (`ks photos`, backed by `keystone-photos`)
# - immich-search: Immich REST API search (smart, person, recent)
# - voice-recorder: PipeWire microphone capture helper
#
# Implements REQ-023.36 (terminal perception.enable option).
# Implements REQ-023.40 (standalone CLI commands for agents and task loops).
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

    search.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install the Keystone Photos search CLI in the user's environment.";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.pdf-extract
      pkgs.keystone.whisper-transcribe
      pkgs.keystone.immich-search
      pkgs.keystone.voice-recorder
    ] ++ optional cfg.search.enable pkgs.keystone.keystone-photos;
  };
}
