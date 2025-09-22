inputs: {
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.keystone;
in {
  imports = [
    (import ./hyprland.nix inputs)
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./mako.nix
    ./waybar.nix
    ./walker.nix
    ./fonts.nix
    ./git.nix
    ./starship.nix
    ./zsh.nix
  ];

  # Enable home-manager for the user
  home.stateVersion = "23.11";

  # Basic desktop packages
  home.packages = with pkgs; [
    # Terminal and shell utilities
    alacritty
    
    # Desktop environment
    waybar
    mako
    walker
    
    # File management
    nautilus
    
    # Media
    pavucontrol
    
    # Development
    git
    neovim
    
    # System utilities
    htop
    btop
    
    # Wayland utilities
    wl-clipboard
    cliphist
    grim
    slurp
    brightnessctl
    
    # Authentication
    polkit_gnome
  ];

  # GTK theme configuration
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita:dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  # Enable programs
  programs.neovim.enable = true;
  programs.git.enable = true;
  programs.zsh.enable = true;
  programs.starship.enable = true;
}