# Keystone OS Base Module
#
# Platform-agnostic configuration shared by all architectures.
# Imports user management, services, nix settings, and locale.
#
{
  imports = [
    ../users.nix # User management works on all platforms
    ../ssh.nix # SSH server works on all platforms
    ./services.nix
    ./nix.nix
    ./locale.nix
  ];
}
