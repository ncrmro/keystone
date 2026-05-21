# Cross-platform `keystone.os.*` option declarations.
#
# Imported by both `modules/os/default.nix` (NixOS) and
# `modules/os/darwin.nix` (Darwin) so option names, types, and defaults
# are a single source of truth. Platform-specific config bodies live in
# their respective entry files; this file declares the schema only.
#
# See `conventions/os.cross-platform-modules.md` for when to use this
# file vs runtime platform detection vs strictly per-platform modules.
{ lib, ... }:
{
  options.keystone.os = {
    enable = lib.mkEnableOption "Keystone OS";

    adminUsername = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      defaultText = lib.literalExpression ''
        Derived on NixOS from the user flagged
        `keystone.os.users.<name>.admin = true` (see the config block
        in `modules/os/default.nix` and the assertion in
        `modules/os/users.nix`). On Darwin the default is the literal
        `"admin"` until `keystone.os.users` gains a Darwin counterpart
        with the same admin-flag derivation.
      '';
      description = ''
        Unix username for the administrator account. Single source of
        truth across NixOS and Darwin host configurations — adopters
        set this once via `admin.username` in `mkSystemFlake` and the
        value flows to both platforms.
      '';
      example = "noah";
    };
  };
}
