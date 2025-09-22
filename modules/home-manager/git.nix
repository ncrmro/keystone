{
  pkgs,
  ...
}: {
  programs.git = {
    enable = true;
    
    userName = "Keystone User";
    userEmail = "user@keystone.local";
    
    extraConfig = {
      init.defaultBranch = "main";
      push.default = "simple";
      pull.rebase = false;
      core.editor = "nvim";
    };
    
    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        side-by-side = true;
      };
    };
  };
}