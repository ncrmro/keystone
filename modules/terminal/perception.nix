# Keystone Terminal Perception
#
# This module provides CLI tools for the perception layer:
# - PDF parsing (docling) — added in Phase 2
# - Voice transcription (whisper.cpp) — added in Phase 2
# - Photo/screenshot search (immich-search) — added in Phase 2
# - Voice recording helper — added in Phase 2
#
# This is the configuration scaffolding. When `enable = true`, the option
# tree is available but no packages are installed yet — they are added as
# individual packages land in subsequent PRs.
#
# Implements REQ-023.36 (terminal perception.enable option).
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
    # Packages will be added here as they are implemented in Phase 2:
    # - pkgs.whisper-cpp (voice transcription)
    # - pkgs.keystone.immich-search (photo/screenshot search)
    # - docling package (PDF parsing)
    # - pkgs.keystone.voice-recorder (PipeWire recording helper)
    home.packages = [
      # Placeholder — packages added in feat/perception-cli-tools
    ];
  };
}
