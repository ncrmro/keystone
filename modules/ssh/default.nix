{
  lib,
  config,
  pkgs,
  ...
}:
with lib; {
  # SSH server configuration module
  # Provides secure SSH access for remote administration
  # Used by both server and client configurations

  options.keystone.ssh = {
    enable =
      mkEnableOption "SSH server for remote administration"
      // {
        default = true;
      };
  };

  config = mkIf config.keystone.ssh.enable {
    # Enable SSH server with secure defaults
    services.openssh = {
      enable = true;
      settings = {
        # Security hardening
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;

        # Additional security settings
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
      };
    };

    # Open SSH port in firewall
    networking.firewall.allowedTCPPorts = [22];

    # Add SSH to system packages for client utilities
    environment.systemPackages = with pkgs; [
      openssh
    ];
  };
}
