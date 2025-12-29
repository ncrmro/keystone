{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.keystone.agent;
in {
  # Backend abstraction layer
  # This module defines the interface for different sandbox backends
  
  imports = [
    ./microvm.nix
    ./kubernetes.nix
  ];

  config = lib.mkIf cfg.enable {
    # Backend-specific configuration will be applied based on cfg.backend.type
  };
}
