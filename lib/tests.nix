# Test harness helpers exposed via `self.lib.tests.*`.
#
# evalNixos / evalDarwin start from `self.{nixos,darwin}Modules.operating-system`
# so the entire keystone option surface is in scope. `admin` is the shared
# fixture from tests/fixtures/admin.nix.
{
  self,
  nixpkgs,
  nix-darwin ? null,
  home-manager ? null,
}:
let
  lib = nixpkgs.lib;
  admin = import ../tests/fixtures/admin.nix;
in
{
  inherit admin;

  evalNixos =
    {
      modules ? [ ],
      system ? "x86_64-linux",
    }:
    (import "${nixpkgs}/nixos/lib/eval-config.nix") {
      inherit system;
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          boot.loader.systemd-boot.enable = true;
        }
      ]
      ++ modules;
    };

  # Module-level Darwin eval. Does not build closures — assertions on
  # `.config.*` run on x86_64-linux. The macos-14 workflow handles
  # `system.build.toplevel` instantiation.
  evalDarwin =
    {
      modules ? [ ],
      system ? "aarch64-darwin",
    }:
    assert nix-darwin != null;
    nix-darwin.lib.darwinSystem {
      inherit system;
      modules = [
        self.darwinModules.operating-system
        {
          networking.hostName = "test-darwin";
          system.stateVersion = 6;
          users.users.${admin.username}.home = "/Users/${admin.username}";
          nixpkgs.overlays = [ self.overlays.default ];
        }
      ]
      ++ lib.optional (home-manager != null) home-manager.darwinModules.home-manager
      ++ modules;
    };
}
