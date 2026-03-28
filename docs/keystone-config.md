---
title: Keystone Config
description: Minimal keystone-config flake showing a realistic multi-host Keystone layout
---

# Keystone Config

Most Keystone setups start with a `keystone-config` repository. It uses [Nix flakes](https://nixos.wiki/wiki/Flakes) for reproducible builds and [Home Manager](https://nix-community.github.io/home-manager/) for user environments.

Create one from the template:

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

The repo usually starts with a structure like this:

```text
keystone-config/
├── flake.nix
├── hosts/
│   ├── workstation/
│   │   ├── default.nix
│   │   └── hardware.nix
│   ├── laptop/
│   │   ├── default.nix
│   │   └── hardware.nix
│   └── nas/
│       ├── default.nix
│       └── hardware.nix
├── home/
│   ├── macbook.nix
│   └── linux-devbox.nix
├── modules/
│   ├── shared.nix
│   └── keystone-os.nix
└── repos.nix
```

The generated template already gives you a working structure. In practice, a
useful `keystone-config` usually has:

- shared repo and user defaults,
- OS-only Keystone defaults,
- a small repo registry,
- shared service placement, and
- multiple Keystone OS hosts such as a workstation, laptop, and NAS, and
- optional terminal-only hosts managed through Home Manager.

This is a minimal but realistic flake shape:

```nix
{
  description = "My Keystone Infrastructure";

  inputs = {
    # Base package set for all hosts.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keystone itself. Keep this on the public GitHub flake input.
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager for user environments.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      keystone,
      home-manager,
      ...
    }:
    {
      nixosConfigurations = {
        # Primary desktop or workstation.
        workstation = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./hosts/workstation ];
          specialArgs = {
            inherit inputs self;
            outputs = self;
          };
        };

        # Portable machine with the same user environment.
        laptop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./hosts/laptop ];
          specialArgs = {
            inherit inputs self;
            outputs = self;
          };
        };

        # NAS or service host with large storage pools.
        nas = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./hosts/nas ];
          specialArgs = {
            inherit inputs self;
            outputs = self;
          };
        };
      };

      homeConfigurations = {
        # macOS host using only the Keystone terminal environment.
        "alice@macbook" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "aarch64-darwin";
          };
          extraSpecialArgs = {
            inherit self keystone;
          };
          modules = [
            ./home/macbook.nix
          ];
        };

        # Non-NixOS Linux host using only the Keystone terminal environment.
        "alice@ubuntu-devbox" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
          };
          extraSpecialArgs = {
            inherit self keystone;
          };
          modules = [
            ./home/linux-devbox.nix
          ];
        };
      };
    };
}
```

That top-level flake stays small because the common config is usually split into
a fully shared layer and an OS-only layer.

```nix
# modules/shared.nix
{ ... }:
{
  # Repo definitions used by Keystone project tooling across all hosts.
  keystone.repos = {
    "example/keystone-config" = {
      url = "git@github.com:example/keystone-config.git";
    };

    "example/keystone" = {
      url = "git@github.com:example/keystone.git";
      flakeInput = "keystone";
    };
  };

  # Terminal-first user defaults can also be shared across OS and non-OS hosts.
  keystone.users.alice = {
    fullName = "Alice Example";
    email = "alice@example.com";
  };

  # Shared service placement can stay global even when some hosts only use the
  # terminal module.
  keystone.services = {
    mail.host = "nas";
    git.host = "nas";
    immich.host = "nas";
    immich.workers = [ "workstation" ];
  };
}
```

```nix
# modules/keystone-os.nix
{ inputs, lib, ... }:
{
  imports = [
    ./shared.nix

    # Core Keystone OS support.
    inputs.keystone.nixosModules.operating-system

    # Hardware-backed SSH, age, and GPG workflows.
    inputs.keystone.nixosModules.hardwareKey
  ];

  # OS defaults only for Keystone OS machines.
  keystone.os = {
    enable = lib.mkDefault true;
    storage.enable = lib.mkDefault false; # Use disko per host.
    ssh.enable = lib.mkDefault false; # Configure SSH explicitly.
    hypervisor.enable = lib.mkDefault true;

    users.alice = {
      terminal.enable = lib.mkDefault true;
      sshAutoLoad.enable = lib.mkDefault true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "audio"
        "video"
      ];
    };
  };
}
```

Each host then stays focused on its actual role:

```nix
# hosts/workstation/default.nix
{ ... }:
{
  imports = [
    ../../modules/keystone-os.nix
    ./hardware.nix
  ];

  networking.hostName = "workstation";

  # Workstation-specific capabilities.
  keystone.os.hypervisor.enable = true;
  keystone.os.services.ollama.enable = true;
}
```

```nix
# hosts/laptop/default.nix
{ ... }:
{
  imports = [
    ../../modules/keystone-os.nix
    ./hardware.nix
  ];

  networking.hostName = "laptop";

  # Keep the laptop lean, but preserve the same terminal workflow.
  keystone.os.hypervisor.enable = false;
  keystone.os.iphoneTether.enable = true;
}
```

```nix
# hosts/nas/default.nix
{ ... }:
{
  imports = [
    ../../modules/keystone-os.nix
    ./hardware.nix
  ];

  networking.hostName = "nas";

  # Service host with storage and shared infrastructure roles.
  keystone.os.storage.enable = true;
  keystone.os.mail.enable = true;
  keystone.os.gitServer.enable = true;
}
```

Terminal-only hosts use Home Manager instead of `nixosConfigurations`:

```nix
# home/macbook.nix
{ inputs, ... }:
{
  imports = [
    ../modules/shared.nix
    inputs.keystone.homeModules.terminal
  ];

  home.username = "alice";
  home.homeDirectory = "/Users/alice";
  home.stateVersion = "25.05";

  # macOS host that only wants the shared terminal environment.
  keystone.terminal.enable = true;
}
```

```nix
# home/linux-devbox.nix
{ inputs, ... }:
{
  imports = [
    ../modules/shared.nix
    inputs.keystone.homeModules.terminal
  ];

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "25.05";

  # Existing Linux machine that should not become Keystone OS.
  keystone.terminal.enable = true;
}
```

This is the pattern to copy:

- keep `flake.nix` as host wiring,
- keep the most shared config in `modules/shared.nix`,
- keep Keystone OS-only defaults in `modules/keystone-os.nix`,
- keep host-specific hardware in `hosts/<name>/hardware.nix`,
- keep host-specific storage and service toggles in `hosts/<name>/default.nix`,
- keep terminal-only macOS or Linux machines in `home/*.nix`,
- use `keystone.services` to declare where shared infrastructure should run.

Next steps:

1. Create `hosts/workstation`, `hosts/laptop`, and `hosts/nas`
2. Add a shared `modules/keystone.nix` with your users, repos, and service placement
3. Add Disko or hardware config per machine
4. Build an installer with [ISO Generation](os/iso-generation.md), or deploy with [Keystone OS install](os/installation.md)
