# Keystone OS X86 Module
#
# X86_64-specific configuration:
# - ZFS/ext4 storage with credstore pattern
# - Secure Boot (Lanzaboote)
# - TPM enrollment and automatic unlock
# - Remote unlock (initrd SSH)
#
{
  imports = [
    ./storage.nix
    ./secure-boot.nix
    ./tpm.nix
    ./remote-unlock.nix
  ];
}
