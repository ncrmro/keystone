# Keystone Mail Host Declaration
#
# Shared top-level option declaring which host runs the mail server.
# Follows the same pattern as domain.nix — set once per infrastructure,
# consumed by multiple modules:
#
#   - modules/os/mail.nix: auto-enables Stalwart when hostName matches
#   - modules/os/agents.nix: agentctl provision uses it to determine
#     mail-password secret recipients
#
# Usage:
#   keystone.mail.host = "ocean";
{ lib, ... }:
with lib; {
  options.keystone.mail.host = mkOption {
    type = types.nullOr types.str;
    default = null;
    example = "ocean";
    description = ''
      The networking.hostName of the mail server.
      Auto-enables Stalwart on that host. Used by agentctl provision
      to determine mail-password secret recipients.
    '';
  };
}
