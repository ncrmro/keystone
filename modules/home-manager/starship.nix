{
  programs.starship = {
    enable = true;
    
    settings = {
      format = "$all$character";
      
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
      
      git_branch = {
        format = "[$symbol$branch]($style) ";
        symbol = " ";
      };
      
      git_status = {
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
      };
      
      directory = {
        truncation_length = 3;
        truncation_symbol = "…/";
      };
      
      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
      };
      
      time = {
        disabled = false;
        format = "[$time]($style) ";
        style = "bright-blue";
      };
    };
  };
}