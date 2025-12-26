{
  config,
  lib,
  pkgs,
  ...
}: {
  # Development Tools Configuration
  # Common development tools and utilities for the sandbox environment
  
  environment.systemPackages = with pkgs; [
    # Version control
    git
    gh
    
    # Development tools
    direnv
    jq
    yq
    
    # Build tools (will be expanded based on project needs)
    gnumake
    
    # Network tools
    netcat
    socat
    
    # Text editors
    vim
    nano
  ];

  # Configure direnv to auto-load .env files
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Git configuration
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };
}
