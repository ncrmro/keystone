{
  services.mako = {
    enable = true;
    backgroundColor = "#1e1e2e";
    textColor = "#cdd6f4";
    borderColor = "#89b4fa";
    borderRadius = 8;
    borderSize = 2;
    defaultTimeout = 5000;
    width = 400;
    height = 150;
    margin = "10";
    padding = "15";
    font = "JetBrains Mono Nerd Font 11";
    
    extraConfig = ''
      [urgency=low]
      border-color=#f9e2af
      
      [urgency=normal]
      border-color=#89b4fa
      
      [urgency=high]
      border-color=#f38ba8
    '';
  };
}