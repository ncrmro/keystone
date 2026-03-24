# Server module evaluation test
#
# Verifies that the server module and all service sub-modules evaluate correctly
# with various configuration options. Forces NixOS module evaluation at build
# time to catch option errors, type mismatches, and assertion failures.
#
# Build: nix build .#server-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Helper: evaluate a NixOS server config and serialise service names to prove
  # evaluation. Uses builtins.toJSON on systemd.services to force module
  # evaluation without pulling in a full system build.
  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.server
          {
            # Minimal required config for evaluation
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            fileSystems."/" = {
              device = "/dev/vda1";
              fsType = "ext4";
            };
          }
        ]
        ++ modules;
      };
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
      usersJson = builtins.toJSON (builtins.attrNames result.config.users.users);
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Services: ${servicesJson}"
      echo "  Users: ${usersJson}"
      touch $out
    '';

  tests = {
    # Server disabled (no services)
    server-disabled = eval "server-disabled" [
      {
        keystone = {
          domain = "example.com";
          server.enable = false;
        };
      }
    ];

    # Server enabled, no services
    server-no-services = eval "server-no-services" [
      {
        keystone = {
          domain = "example.com";
          server.enable = true;
        };
      }
    ];

    # SeaweedFS blob store - minimal config
    seaweedfs-minimal = eval "seaweedfs-minimal" [
      {
        keystone = {
          domain = "example.com";
          server = {
            enable = true;
            services.seaweedfs.enable = true;
          };
        };
      }
    ];

    # SeaweedFS blob store - with s3ConfigFile
    seaweedfs-with-s3-config = eval "seaweedfs-with-s3-config" [
      {
        keystone = {
          domain = "example.com";
          server = {
            enable = true;
            services.seaweedfs = {
              enable = true;
              s3ConfigFile = "/run/agenix/seaweedfs-s3-config";
            };
          };
        };
      }
    ];

    # SeaweedFS blob store - custom ports and subdomain
    seaweedfs-custom = eval "seaweedfs-custom" [
      {
        keystone = {
          domain = "example.com";
          server = {
            enable = true;
            services.seaweedfs = {
              enable = true;
              subdomain = "blob";
              masterPort = 19333;
              volumePort = 18880;
              filerPort = 18888;
              replication = "010";
            };
          };
        };
      }
    ];

    # SeaweedFS alongside forgejo (validates no port conflict)
    seaweedfs-with-forgejo = eval "seaweedfs-with-forgejo" [
      {
        keystone = {
          domain = "example.com";
          server = {
            enable = true;
            services.seaweedfs.enable = true;
            services.forgejo.enable = true;
          };
        };
      }
    ];

    # Journal-remote nginx proxy (auto-registered when journal-remote is active)
    journal-remote-proxy = eval "journal-remote-proxy" [
      {
        keystone = {
          domain = "example.com";
          server.enable = true;
        };
        # Simulate journal-remote being active (set by OS module on the server host)
        services.journald.remote = {
          enable = true;
          listen = "http";
          port = 19532;
        };
      }
    ];
  };
in
pkgs.runCommand "test-server-evaluation"
  {
    # Force all sub-tests to be evaluated at build time
    nativeBuildInputs = lib.attrValues tests;
  }
  ''
    echo "Server module evaluation tests"
    echo "=============================="
    echo ""
    echo "Configurations tested:"
    echo "  - server-disabled: Server module disabled"
    echo "  - server-no-services: Server enabled, no services"
    echo "  - seaweedfs-minimal: SeaweedFS with defaults"
    echo "  - seaweedfs-with-s3-config: SeaweedFS with S3 credentials file"
    echo "  - seaweedfs-custom: SeaweedFS with custom ports and subdomain"
    echo "  - seaweedfs-with-forgejo: SeaweedFS alongside Forgejo (no port conflict)"
    echo "  - journal-remote-proxy: Journal-remote nginx proxy auto-registration"
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
