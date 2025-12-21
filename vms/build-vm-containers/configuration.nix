{
  config,
  pkgs,
  lib,
  ...
}: {
  # Keystone configuration for testing container development (Docker rootless + Kind)
  # Uses nixos-rebuild build-vm for fast iteration without encryption/secure boot
  #
  # Build with: nixos-rebuild build-vm --flake .#build-vm-containers
  # Run with: ./result/bin/run-build-vm-containers-vm
  #
  # The VM:
  # - Includes rootless Docker and Kind
  # - Mounts host Nix store via 9P (read-only)
  # - Creates persistent qcow2 disk at ./build-vm-containers.qcow2
  # - Much faster than full deployment for testing configs

  # NixOS state version
  system.stateVersion = "25.05";

  # System identity
  networking.hostName = "keystone-buildvm-containers";

  # Simple boot configuration for VM
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem (required for NixOS)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Basic networking with DHCP
  networking.useDHCP = lib.mkDefault true;

  # VM-specific configuration for build-vm
  # These options only apply when building with nixos-rebuild build-vm
  virtualisation.vmVariant = {
    # Forward SSH port for easy host access: ssh -p 2222 testuser@localhost
    virtualisation.forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
    
    # Increase memory and CPUs for container workloads
    virtualisation.memorySize = 4096; # 4GB
    virtualisation.cores = 4;
    
    # Larger disk for container images
    virtualisation.diskSize = 20480; # 20GB
  };

  # Enable serial console for VM
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable mutable users for easy testing
  users.mutableUsers = true;

  # Enable Docker rootless
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
    autoPrune = {
      enable = true;
      dates = "daily";
    };
  };

  # Enable necessary kernel modules for containers
  boot.kernelModules = [
    "ip_tables"
    "ip6_tables"
    "iptable_filter"
    "iptable_nat"
    "overlay"
    "br_netfilter"
  ];

  # Sysctl settings for containers
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    # Increase inotify limits for container development
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };

  # Test user with container dev environment
  users.users.testuser = {
    isNormalUser = true;
    description = "Container Dev Test User";
    initialPassword = "testpass"; # Test only - insecure
    extraGroups = ["wheel" "networkmanager" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
    ];
  };

  # Root password for easy access
  users.users.root.initialPassword = "root";

  # Container development packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    docker
    docker-compose
    kind
    kubectl
    kubernetes-helm
    jq
    yq-go
  ];

  # Allow sudo without password (testing only)
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "testuser"];
  };

  # Configure home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # Import home-manager modules
    sharedModules = [
      ../../home-manager/modules/terminal-dev-environment
      ../../modules/keystone/terminal
    ];
  };

  # Configure home-manager for test user
  home-manager.users.testuser = {
    home.stateVersion = "25.05";

    # Enable terminal dev environment
    programs.terminal-dev-environment = {
      enable = true;

      tools = {
        git = true;
        editor = true;
        shell = true;
        multiplexer = true;
        terminal = true;
      };
    };

    # Git configuration
    programs.git = {
      userName = "Container Test User";
      userEmail = "testuser@keystone-buildvm-containers";
    };

    # Enable container development tools
    keystone.terminal.containers = {
      enable = true;
      docker.enable = true;
      kind.enable = true;
      kubectl.enable = true;
    };
  };
}
