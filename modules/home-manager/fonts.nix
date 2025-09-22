{
  pkgs,
  ...
}: {
  fonts.fontconfig.enable = true;
  
  home.packages = with pkgs; [
    # Nerd Fonts
    (nerdfonts.override { fonts = [ "JetBrainsMono" "FiraCode" "Hack" ]; })
    
    # System fonts
    dejavu_fonts
    liberation_ttf
    source-code-pro
    
    # Emoji support
    noto-fonts-emoji
    
    # Icon fonts
    font-awesome
  ];
}