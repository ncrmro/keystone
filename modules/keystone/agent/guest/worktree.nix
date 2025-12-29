{
  config,
  lib,
  pkgs,
  ...
}: {
  # Git Worktree Configuration
  # Manages worktrees at /workspace/.worktrees/<branch>/
  
  # This will be implemented in Phase 4 (User Story 2)
  # Features:
  # - Worktree directory structure at /workspace/.worktrees/
  # - Independent terminal sessions per worktree
  # - Worktree creation and cleanup helpers
  
  # Create worktree directory structure
  systemd.tmpfiles.rules = [
    "d /workspace/.worktrees 0755 sandbox sandbox -"
  ];
}
