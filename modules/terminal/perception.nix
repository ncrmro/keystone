# Keystone Terminal Perception
#
# Installs CLI tools for the perception layer:
# - ks audio-transcribe: local audio transcription via whisper.cpp
# - ks doc-extractor: PDF-to-markdown with citations (Docling)
# - ks photos: Immich-backed photo search
#
# Implements REQ-024.36 (terminal perception.enable option).
# Implements REQ-024.40 (standalone CLI commands for agents and task loops).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.perception;
  immichHost = config.keystone.services.immich.host;
in
{
  options.keystone.terminal.perception = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable perception CLI tools via ks.";
    };

    search.enable = mkOption {
      type = types.bool;
      default = immichHost != null;
      defaultText = literalExpression "config.keystone.services.immich.host != null";
      description = "Install the Keystone Photos search CLI in the user's environment.";
    };

    audioTranscribe = {
      language = mkOption {
        type = types.str;
        default = "en";
        description = "Default language for audio-transcribe.";
      };

      model = mkOption {
        type = types.str;
        default = "large-v3";
        description = "Default model for audio-transcribe.";
      };
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      (pkgs.keystone.ks.override {
        defaultLanguage = cfg.audioTranscribe.language;
        defaultModel = cfg.audioTranscribe.model;
      })
    ]
    ++ optional cfg.search.enable pkgs.keystone.keystone-photos;
  };
}
