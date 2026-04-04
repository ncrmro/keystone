{
  pkgs,
  ...
}:
{
  # Optional server-specific overrides.
  #
  # This file is the right place for per-server firewall rules, backup agents,
  # monitoring, or service-specific tuning that should not affect other hosts.

  environment.systemPackages = with pkgs; [
    git
    helix
  ];

  # Example:
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
