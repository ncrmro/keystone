# Off-site/Remote Server Configuration
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../modules/server
    ../modules/disko-single-disk-root
  ];

  # Enable minimal Keystone server modules for off-site
  keystone.server = {
    enable = true;
    vpn = {
      enable = true;
      role = "client"; # Connect back to main site
    };
    backup = {
      enable = true;
      role = "remote"; # Receive backups from main site
    };
    monitoring = {
      enable = true;
      role = "remote"; # Send metrics to main site
    };
  };

  # Disko configuration for encrypted root
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/virtio-os-disk-off-site";
    enableEncryptedSwap = false; # Minimal swap for small VPS
  };

  # Network configuration
  networking = {
    hostName = "keystone-off-site";
    hostId = "e5f6a7b8"; # Random 8-char hex string

    # Use DHCP with static lease
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
  };

  # Minimal services for off-site server
  services = {
    # SSH with enhanced security
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
        AllowTcpForwarding = false;
        AllowAgentForwarding = false;
        AllowStreamLocalForwarding = false;
        AuthenticationMethods = "publickey";
      };
      ports = [22];
      openFirewall = true;
    };

    # Fail2ban for security
    fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "1h";
    };

    # Simple backup receiver
    rsync = {
      enable = true;
      # Will be configured by keystone.server.backup
    };
  };

  # Security hardening
  security = {
    # Disable sudo timeout
    sudo.execWheelOnly = true;

    # Lock down the kernel
    lockKernelModules = true;

    # Protect against common attacks
    protectKernelImage = true;
  };

  # Minimal package set
  environment.systemPackages = with pkgs; [
    htop
    vim
    git
    curl
    wget
    rsync
    tmux
  ];

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22]; # SSH only
    allowPing = true;

    # Default deny policy
    allowedUDPPorts = [];
  };

  # Automatic updates for security
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    dates = "04:00";
    randomizedDelaySec = "30min";
  };

  # System configuration
  system.stateVersion = "25.05";
}
