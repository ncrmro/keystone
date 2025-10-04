{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
{
  # Server configuration module
  # Provides always-on infrastructure services

  imports = [
    ../disko-single-disk-root
  ];

  options.keystone.server = {
    enable = mkEnableOption "Keystone server configuration" // {
      default = true;
    };
  };

  config = mkIf config.keystone.server.enable {
    # Enable SSH for remote administration
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
      };
    };

    # Enable mDNS for easy discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
    };

    # Basic firewall configuration
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ]; # SSH
    };

    # Enable systemd-resolved for DNS
    services.resolved.enable = true;

    # Server-specific packages
    environment.systemPackages = with pkgs; [
      htop
      iotop
      lsof
      tcpdump
      tmux
      vim
      git
    ];

    # Optimize for server workloads
    boot.kernel.sysctl = {
      "vm.swappiness" = 10;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 65536 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    };

    # Enable automatic garbage collection
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Server timezone and locale
    time.timeZone = "UTC";
    i18n.defaultLocale = "en_US.UTF-8";
  };
}
