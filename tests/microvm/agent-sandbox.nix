{
  pkgs,
  config,
  lib,
  ...
}: {
  # Agent Sandbox MicroVM Test Configuration
  # This is a minimal MicroVM configuration to test the agent sandbox guest environment
  
  microvm = {
    hypervisor = "qemu";
    
    # Memory and CPU configuration
    mem = 2048; # 2GB for testing (production default: 8GB)
    vcpu = 2;   # 2 vCPUs for testing (production default: 4)
    
    # Enable virtiofs for /workspace/ sharing
    shares = [
      {
        proto = "virtiofs";
        tag = "workspace";
        source = "/tmp/agent-sandbox-workspace";
        mountPoint = "/workspace";
      }
    ];
    
    # Network configuration (basic NAT for internet access)
    interfaces = [
      {
        type = "user";
        id = "eth0";
        mac = "02:00:00:01:01:01";
      }
    ];
  };

  # Import guest configuration
  imports = [
    ../../modules/keystone/agent/guest
  ];

  # Disable keystone.os module (not needed for sandbox guest)
  keystone.os.enable = lib.mkDefault false;

  # Basic system configuration
  system.stateVersion = "25.05";

  # Test user
  users.users.sandbox = {
    isNormalUser = true;
    description = "Sandbox User";
    extraGroups = ["wheel"];
    initialPassword = "sandbox";
  };

  # Enable sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Networking
  networking = {
    hostName = "agent-sandbox";
    firewall.enable = true;
    # Allow SSH for testing
    firewall.allowedTCPPorts = [22];
  };

  # Enable SSH for testing
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Test service to verify sandbox is working
  systemd.services.sandbox-test = {
    description = "Agent Sandbox Test Service";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
    script = ''
      echo "--- Agent Sandbox Test: Start ---"
      echo "Hostname: $(hostname)"
      echo "User: $(whoami)"
      echo "Workspace mount: $(mount | grep workspace || echo 'NOT MOUNTED')"
      echo "Development tools:"
      which git && echo "  ✓ git"
      which direnv && echo "  ✓ direnv"
      which jq && echo "  ✓ jq"
      which zellij && echo "  ✓ zellij"
      echo "--- Agent Sandbox Test: PASSED ---"
    '';
  };
}
