{
  pkgs,
  ...
}:
{
  # Optional host-specific overrides.
  #
  # A thin client remotes into a workstation for heavy computation and
  # development. Keep the core machine shape in flake.nix so readers can see
  # the archetype, admin, shared users, Keystone modules, and service enables
  # in one place.

  environment.systemPackages = with pkgs; [
    git
    helix
  ];

  # Add extra host-only settings here when they do not belong in the top-level
  # machine declaration. Examples:
  #
  # services.printing.enable = true;
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
