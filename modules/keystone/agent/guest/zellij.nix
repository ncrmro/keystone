{
  config,
  lib,
  pkgs,
  ...
}: {
  # Zellij Configuration
  # Terminal multiplexer for session management in the sandbox
  
  # This will be implemented in Phase 4 (User Story 2)
  # Features:
  # - Zellij session persistence
  # - Web server for remote attachment
  # - Session naming convention (<sandbox>-<branch>)
  # - Multi-worktree session management
  
  programs.zellij = {
    enable = true;
  };
}
