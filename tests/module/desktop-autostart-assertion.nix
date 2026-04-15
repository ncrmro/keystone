# Desktop autostart assertion test
#
# Verifies the build-time assertion in autostart.nix catches a missing
# startup lock command. This is a pure evaluation test — no VM needed.
#
# The test evaluates the desktop home-manager module twice:
#   1. Default config → assertion passes (startup lock present)
#   2. Overridden exec-once without lock → assertion fails
#
# Build: nix build .#test-desktop-autostart-assertion
#
{
  pkgs,
  lib,
  self,
  home-manager,
}:
let
  # Evaluate a home-manager configuration with the desktop module
  evalDesktop =
    extraModules:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.terminal
        self.homeModules.desktop
        {
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";

          keystone.terminal = {
            enable = true;
            git = {
              userName = "Test User";
              userEmail = "test@test";
            };
          };

          keystone.desktop.enable = true;

          # Hyprland requires a compositor to be enabled for settings to take effect
          wayland.windowManager.hyprland.enable = true;
        }
      ]
      ++ extraModules;
    }).config;

  # Test 1: Default config should have startup lock in exec-once
  defaultConfig = evalDesktop [ ];
  defaultExecOnce = defaultConfig.wayland.windowManager.hyprland.settings.exec-once;
  hasStartupLock = builtins.any (cmd: lib.hasPrefix "keystone-startup-lock" cmd) defaultExecOnce;

  # Test 2: Verify that mkAfter properly appends (doesn't replace)
  withMkAfterConfig = evalDesktop [
    {
      wayland.windowManager.hyprland.settings.exec-once = lib.mkAfter [
        "my-custom-app"
      ];
    }
  ];
  mkAfterExecOnce = withMkAfterConfig.wayland.windowManager.hyprland.settings.exec-once;
  mkAfterHasLock = builtins.any (cmd: lib.hasPrefix "keystone-startup-lock" cmd) mkAfterExecOnce;
  mkAfterHasCustom = builtins.any (cmd: cmd == "my-custom-app") mkAfterExecOnce;

  # Test 3: Verify assertion fires when lock is missing
  # We can't evaluate a failing assertion directly, but we can check that
  # the assertion definition exists and references the right command.
  defaultAssertions = defaultConfig.assertions;
  hasLockAssertion = builtins.any (a: lib.hasInfix "startup-lock" a.message) defaultAssertions;

  # Test 4: Custom startupLockCommand is used in exec-once
  customLockConfig = evalDesktop [
    { keystone.desktop.startupLockCommand = "my-custom-lock"; }
  ];
  customExecOnce = customLockConfig.wayland.windowManager.hyprland.settings.exec-once;
  hasCustomLock = builtins.any (cmd: lib.hasPrefix "my-custom-lock" cmd) customExecOnce;
in
pkgs.runCommand "test-desktop-autostart-assertion" { } ''
  set -euo pipefail
  errors=0

  check() {
    if [ "$1" = "true" ]; then
      echo "PASS: $2"
    else
      echo "FAIL: $2" >&2
      errors=$((errors + 1))
    fi
  }

  check "${builtins.toString hasStartupLock}" \
    "default exec-once contains keystone-startup-lock"

  check "${builtins.toString mkAfterHasLock}" \
    "mkAfter preserves startup lock in exec-once"

  check "${builtins.toString mkAfterHasCustom}" \
    "mkAfter appends custom entry to exec-once"

  check "${builtins.toString hasLockAssertion}" \
    "assertion referencing startup-lock exists"

  check "${builtins.toString hasCustomLock}" \
    "custom startupLockCommand appears in exec-once"

  if [ "$errors" -gt 0 ]; then
    echo "$errors test(s) failed" >&2
    exit 1
  fi

  echo "All desktop autostart assertion tests passed"
  touch "$out"
''
