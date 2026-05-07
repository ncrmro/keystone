# Keystone OS Network Egress Module
#
# Opt-in outbound firewall: drops traffic to RFC1918 / link-local /
# ULA destinations except for an explicit allow-list. WAN remains
# unrestricted. Designed for sandbox VMs that should reach the public
# internet (and the Tailscale mesh) but MUST NOT touch the home LAN.
#
# Usage (typically inside a dev-VM nixosConfiguration):
#   keystone.os.networkEgress = {
#     enable = true;
#     allowedSubnets = [
#       "100.64.0.0/10"     # Tailscale CGNAT
#       "127.0.0.0/8"       # loopback
#       "192.168.200.0/24"  # libvirt dev-net (gateway 192.168.200.1)
#     ];
#   };
#
# Implemented via networking.firewall.extraCommands, which the iptables
# backend (NixOS default) and the iptables-nft compatibility shim both
# honour. If a host enables `networking.nftables.enable = true` natively,
# extraCommands becomes a no-op and these rules will not apply — surface
# this with an assertion.
#
{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.keystone.os.networkEgress;

  # IPv4 private/CGNAT/link-local ranges we drop unless explicitly allowed.
  blockedV4 = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "169.254.0.0/16"
  ];
  blockedV6 = [
    "fc00::/7" # Unique Local Addresses
    "fe80::/10" # Link-local
  ];

  isV6 = s: hasInfix ":" s;
  v4Allowed = filter (s: !isV6 s) cfg.allowedSubnets;
  v6Allowed = filter isV6 cfg.allowedSubnets;

  buildExtra = ''
    # keystone-network-egress: allow loopback unconditionally
    iptables  -I OUTPUT 1 -o lo -j ACCEPT
    ip6tables -I OUTPUT 1 -o lo -j ACCEPT

    # allow established/related (return traffic for accepted flows)
    iptables  -I OUTPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -I OUTPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # allow-list (inserted first so they short-circuit the rejects)
    ${concatMapStringsSep "\n" (s: "iptables  -I OUTPUT 1 -d ${s} -j ACCEPT") v4Allowed}
    ${concatMapStringsSep "\n" (s: "ip6tables -I OUTPUT 1 -d ${s} -j ACCEPT") v6Allowed}

    # reject the rest of RFC1918 / link-local / ULA
    ${concatMapStringsSep "\n" (s: "iptables  -A OUTPUT -d ${s} -j REJECT --reject-with icmp-net-unreachable") blockedV4}
    ${concatMapStringsSep "\n" (s: "ip6tables -A OUTPUT -d ${s} -j REJECT --reject-with icmp6-adm-prohibited") blockedV6}
  '';

  buildExtraStop = ''
    # keystone-network-egress: best-effort cleanup. Mirror buildExtra in
    # reverse so reload doesn't accumulate duplicate rules.
    ${concatMapStringsSep "\n" (s: "iptables  -D OUTPUT -d ${s} -j REJECT --reject-with icmp-net-unreachable || true") blockedV4}
    ${concatMapStringsSep "\n" (s: "ip6tables -D OUTPUT -d ${s} -j REJECT --reject-with icmp6-adm-prohibited || true") blockedV6}
    ${concatMapStringsSep "\n" (s: "iptables  -D OUTPUT -d ${s} -j ACCEPT || true") v4Allowed}
    ${concatMapStringsSep "\n" (s: "ip6tables -D OUTPUT -d ${s} -j ACCEPT || true") v6Allowed}
    iptables  -D OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
    ip6tables -D OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
    iptables  -D OUTPUT -o lo -j ACCEPT || true
    ip6tables -D OUTPUT -o lo -j ACCEPT || true
  '';
in
{
  options.keystone.os.networkEgress = {
    enable = mkEnableOption ''
      outbound firewall that rejects RFC1918 / link-local / ULA
      destinations except those listed in allowedSubnets. Public WAN
      remains unrestricted'';

    allowedSubnets = mkOption {
      type = types.listOf types.str;
      default = [
        "100.64.0.0/10" # Tailscale CGNAT
        "127.0.0.0/8" # loopback (defence in depth; loopback is also -o lo allowed)
      ];
      example = [
        "100.64.0.0/10"
        "192.168.200.0/24"
      ];
      description = ''
        Private / CGNAT / link-local subnets that bypass the egress
        block. Add the libvirt dev-net subnet here so the VM can reach
        its NAT gateway, and the Tailscale CGNAT range so mesh peers
        remain reachable.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.networking.nftables.enable or false);
        message = ''
          keystone.os.networkEgress relies on networking.firewall.extraCommands,
          which is ignored when networking.nftables.enable = true. Either turn
          off native nftables on this host, or extend this module with a
          networking.nftables.tables entry.
        '';
      }
      {
        assertion = config.networking.firewall.enable;
        message = "keystone.os.networkEgress requires networking.firewall.enable = true";
      }
    ];

    networking.firewall.extraCommands = buildExtra;
    networking.firewall.extraStopCommands = buildExtraStop;
  };
}
