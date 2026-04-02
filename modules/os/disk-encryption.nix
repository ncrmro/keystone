# Keystone OS Disk Encryption Module
#
# Unified model for block-storage encryption unlock methods.
# Provides a first-class option surface that describes which unlock
# mechanisms are configured for the LUKS credstore (ZFS) or LUKS root
# (ext4), so that documentation, assertions, and status tooling all
# derive from one authoritative source.
#
# This module does NOT replace the enrollment scripts in tpm.nix —
# it complements them with a declarative description of the desired
# unlock configuration and adds safety assertions.
#
# See docs/os/disk-encryption.md for the full user-facing reference.
#
{
  lib,
  config,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.diskEncryption;
in
{
  config = mkIf (osCfg.enable && osCfg.storage.enable) {
    assertions = [
      # At least one human-usable fallback must remain available (Req 24).
      {
        assertion = cfg.unlockMethods.password.enable || cfg.unlockMethods.recoveryKey.enable;
        message = ''
          keystone.os.diskEncryption: At least one human-usable fallback
          (password or recoveryKey) must be enabled.  Configurations that
          remove all interactive recovery paths are not supported.
        '';
      }
      # FIDO2 requires the hardwareKey module for pcscd and tooling.
      {
        assertion = !cfg.unlockMethods.fido2.enable || config.keystone.hardwareKey.enable;
        message = ''
          keystone.os.diskEncryption: FIDO2 unlock requires
          keystone.hardwareKey.enable = true (provides pcscd, udev rules,
          and YubiKey tooling).
        '';
      }
    ];
  };
}
