# Demo host for the install realization: a real disko-built LUKS disk image
# booted under QEMU with an emulated TPM2 attached (see targets in
# flake.nix). The boot test exercises the passphrase fallback path — the
# same prompt a user hits when TPM/FIDO2 unlock is unavailable.
{ lib, ... }:
{
  disko.tests = {
    efi = true;
    # The image is created with disko's test passphrase; the boot test waits
    # for the initrd prompt and types it, proving LUKS unlock end to end.
    bootCommands = ''
      machine.wait_for_console_text("Please enter passphrase for")
      machine.send_chars("secretsecret\n")
    '';
  };

  disko.devices = {
    disk.disk1 = {
      type = "disk";
      device = lib.mkDefault "/dev/vda";
      # Image builds run disko in a VM where no one has provided the LUKS
      # key; write the disko test passphrase unless a real install already
      # placed one. Hosts using passwordFile adopt this same guarded hook.
      preCreateHook = "[ -f /tmp/secret.key ] || echo -n secretsecret > /tmp/secret.key";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          crypted = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypted";
              passwordFile = "/tmp/secret.key";
              settings = {
                allowDiscards = true;
                crypttabExtraOpts = [ "tpm2-device=auto" ];
              };
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

  services.openssh.enable = true;
  users.users.root.initialPassword = "demo";
  system.stateVersion = "25.05";
}
