# Development mode evaluation test
#
# Verifies that keystone.development correctly switches path resolution
# between Nix store copies (locked / non-development) and local repo
# checkouts (development mode).
#
# Three scenarios:
#   1. non-development (default)  — all paths are Nix store copies
#   2. development-with-repos     — paths resolve to local checkouts
#   3. development-without-repos  — graceful fallback to store paths
#
# Build: nix build .#development-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  agenix,
  home-manager,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Helper: evaluate a NixOS config and serialise session variables to prove
  # development vs non-development path resolution.
  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.overlays = [ self.overlays.default ];
          }
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            networking.hostName = "test-host";

            home-manager.sharedModules = [
              self.homeModules.terminal
              {
                keystone.terminal.sandbox.enable = false;
              }
            ];
          }
        ]
        ++ modules;
      };

      sessionVarsJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON result.config.home-manager.users.testuser.home.sessionVariables
        else
          "{}";

      developmentJson = builtins.toJSON result.config.keystone.development;
      reposJson = builtins.toJSON (builtins.attrNames result.config.keystone.repos);
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  keystone.development: ${developmentJson}"
      echo "  keystone.repos keys: ${reposJson}"
      echo "  Session Vars: ${sessionVarsJson}"

      # --- non-development: all DEEPWORK paths must be Nix store copies ---
      if [ "${name}" = "non-development" ]; then
        echo "Verifying non-development mode..."
        if echo '${sessionVarsJson}' | grep -q '\.keystone/repos/'; then
          echo "  ✗ Found local repo path in non-development mode"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        else
          echo "  ✓ No local repo paths (store paths used)"
        fi
        if echo '${sessionVarsJson}' | grep -q '/nix/store/'; then
          echo "  ✓ Nix store paths present"
        else
          echo "  ✗ Expected Nix store paths in DEEPWORK_ADDITIONAL_JOBS_FOLDERS"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
      fi

      # --- development-with-repos: DEEPWORK paths must be local checkouts ---
      if [ "${name}" = "development-with-repos" ]; then
        echo "Verifying development mode with repos..."
        if echo '${sessionVarsJson}' | grep -q "/home/testuser/.keystone/repos/Unsupervisedcom/deepwork/library/jobs"; then
          echo "  ✓ Found local deepwork jobs path"
        else
          echo "  ✗ Missing local deepwork jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
        if echo '${sessionVarsJson}' | grep -q "/home/testuser/.keystone/repos/ncrmro/keystone/.deepwork/jobs"; then
          echo "  ✓ Found local keystone jobs path"
        else
          echo "  ✗ Missing local keystone jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
      fi

      # --- development-without-repos: graceful fallback to store paths ---
      if [ "${name}" = "development-without-repos" ]; then
        echo "Verifying development mode without repos (fallback)..."
        if echo '${sessionVarsJson}' | grep -q '\.keystone/repos/'; then
          echo "  ✗ Found local repo path despite no repos declared"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        else
          echo "  ✓ No local repo paths (graceful fallback)"
        fi
        if echo '${sessionVarsJson}' | grep -q '/nix/store/'; then
          echo "  ✓ Nix store paths present (fallback)"
        else
          echo "  ✗ Expected Nix store paths in DEEPWORK_ADDITIONAL_JOBS_FOLDERS"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
      fi

      touch $out
    '';

  # Shared base config module for all tests
  baseUserConfig = {
    keystone.os = {
      enable = true;
      storage = {
        type = "ext4";
        devices = [ "/dev/vda" ];
      };
      users.testuser = {
        fullName = "Test User";
        initialPassword = "testpass";
        terminal.enable = true;
        email = "testuser@example.com";
      };
    };
    fileSystems."/" = {
      device = lib.mkForce "/dev/vda2";
      fsType = lib.mkForce "ext4";
    };
  };

  tests = {
    # Default: development mode off — store paths only
    non-development = eval "non-development" [
      baseUserConfig
    ];

    # Development mode on with repos declared — local checkout paths
    development-with-repos = eval "development-with-repos" [
      baseUserConfig
      { keystone.development = true; }
    ];

    # Development mode on but no matching repos — fallback to store paths
    development-without-repos = eval "development-without-repos" [
      baseUserConfig
      {
        keystone.development = true;
        keystone._repoInputs = lib.mkForce { };
        keystone.repos = lib.mkForce { };
        # Also clear home-manager-level repo auto-population from keystoneInputs
        home-manager.sharedModules = [
          {
            keystone._repoInputs = lib.mkForce { };
            keystone.repos = lib.mkForce { };
          }
        ];
      }
    ];
  };
in
pkgs.runCommand "test-development-evaluation"
  {
    buildInputs = builtins.attrValues tests;
  }
  ''
    echo "Development mode evaluation tests"
    echo "=================================="
    echo ""
    echo "Configurations tested:"
    echo "  - non-development: Default mode, all paths use Nix store"
    echo "  - development-with-repos: Dev mode ON, paths use local checkouts"
    echo "  - development-without-repos: Dev mode ON but no repos, graceful fallback"
    echo ""
    echo "All development mode configurations evaluated successfully!"
    touch $out
  ''
