{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  home-manager,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  result = nixosSystem {
    system = "x86_64-linux";
    modules = [
      {
        nixpkgs.overlays = [ self.overlays.default ];
      }
      home-manager.nixosModules.home-manager
      self.nixosModules.operating-system
      self.nixosModules.desktop
      {
        home-manager.sharedModules = [
          self.homeModules.desktop
          {
            # Keep the standard desktop config as the integration target while
            # disabling unrelated optional terminal features that are not part
            # of launcher wiring and can pull in brittle external packages.
            keystone.terminal.ai.enable = false;
            keystone.terminal.sandbox.enable = false;
          }
        ];
      }
      ../../vms/test-hyprland/configuration.nix
    ];
  };

  homeCfg = result.config.home-manager.users.testuser;
  homeFilesJson = builtins.toJSON (builtins.attrNames homeCfg.home.file);
  packageNamesJson = builtins.toJSON (map (p: p.name or "") homeCfg.home.packages);
  placeholdersJson = builtins.toJSON (builtins.attrNames homeCfg.programs.walker.config.placeholders);
  secretInput = homeCfg.programs.walker.config.placeholders."menus:keystone-secrets".input;
  secretActionsInput =
    homeCfg.programs.walker.config.placeholders."menus:keystone-secret-actions".input;
in
pkgs.runCommand "test-walker-standard-desktop" { } ''
  echo "Evaluating standard desktop launcher wiring..."

  if echo '${homeFilesJson}' | grep -q '".config/elephant/menus/keystone-secrets.lua"' \
    && echo '${homeFilesJson}' | grep -q '".config/elephant/menus/keystone-secret-list.lua"' \
    && echo '${homeFilesJson}' | grep -q '".config/elephant/menus/keystone-secret-actions.lua"'; then
    echo "  ✓ Standard desktop config emits secrets menu files"
  else
    echo "  ✗ Missing one or more secrets menu files in standard desktop config"
    echo "  Actual home files: ${homeFilesJson}"
    exit 1
  fi

  if echo '${placeholdersJson}' | grep -q '"menus:keystone-secrets"' \
    && echo '${placeholdersJson}' | grep -q '"menus:keystone-secret-list"' \
    && echo '${placeholdersJson}' | grep -q '"menus:keystone-secret-actions"'; then
    echo "  ✓ Walker placeholders include secrets menu ids"
  else
    echo "  ✗ Walker placeholders are missing secrets menu ids"
    echo "  Actual placeholders: ${placeholdersJson}"
    exit 1
  fi

  if [ "${secretInput}" = " Secrets" ] && [ "${secretActionsInput}" = " Secret actions" ]; then
    echo "  ✓ Walker placeholder text matches expected launcher prompts"
  else
    echo "  ✗ Walker placeholder text is wrong"
    echo "  menus:keystone-secrets input: ${secretInput}"
    echo "  menus:keystone-secret-actions input: ${secretActionsInput}"
    exit 1
  fi

  if echo '${packageNamesJson}' | grep -q '"keystone-launch-walker"' \
    && echo '${packageNamesJson}' | grep -q '"keystone-secrets-menu"'; then
    echo "  ✓ Standard desktop config packages launcher command surface"
  else
    echo "  ✗ Missing launcher commands in standard desktop config package set"
    echo "  Actual package names: ${packageNamesJson}"
    exit 1
  fi

  touch "$out"
''
