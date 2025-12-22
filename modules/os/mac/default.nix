# Keystone OS Mac Module
#
# Apple Silicon-specific configuration:
# - ext4 with LUKS encryption (no ZFS)
# - systemd-boot (no Secure Boot/lanzaboote)
# - No TPM support (Apple Silicon uses Secure Enclave)
# - Optional remote unlock (initrd SSH)
#
{
  imports = [
    ./apple-silicon.nix
    ./boot.nix
    ./storage.nix
    ./remote-unlock.nix
  ];
}
