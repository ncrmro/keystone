# Mail client configuration: himalaya CLI + agenix assertions.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib)
    osCfg
    cfg
    topDomain
    mailAgents
    hasMailAgents
    ;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasMailAgents) {
    assertions = [
      {
        assertion = topDomain != null;
        message = "keystone.domain must be set when agents are defined (mail derives from it)";
      }
    ]
    ++ (mapAttrsToList (
      name: agentCfg:
      let
        mailAddr =
          if agentCfg.mail.address != null then agentCfg.mail.address else "agent-${name}@${topDomain}";
        # Match the host-prefixed naming used by auto-secrets so the
        # same logical secret can coexist across the fleet.
        secretName =
          if agentCfg.host != null then
            "${agentCfg.host}-agent-${name}-mail-password"
          else
            "agent-${name}-mail-password";
      in
      {
        assertion = config.age.secrets ? "${secretName}";
        message = ''
          Agent '${name}' requires agenix secret "${secretName}".

          1. Create the Stalwart mail account (run on ocean):
             curl -s -u admin:"$(cat /run/agenix/stalwart-admin-password)" \
               http://127.0.0.1:8082/api/principal \
               -H "Content-Type: application/json" \
               -d '{"type":"individual","name":"agent-${name}","secrets":["PASSWORD"],"emails":["${mailAddr}"]}'
             curl -s -u admin:"$(cat /run/agenix/stalwart-admin-password)" \
               http://127.0.0.1:8082/api/principal/agent-${name} -X PATCH \
               -H "Content-Type: application/json" \
               -d '[{"action":"set","field":"roles","value":["user"]}]'

          2. Add to agenix-secrets/secrets.nix:
             "secrets/${secretName}.age".publicKeys = adminKeys ++ [ systems.${agentCfg.host} ];

          3. Create the secret (use the SAME password as step 1):
             cd agenix-secrets && agenix -e secrets/${secretName}.age

          4. Declare in host config (or rely on auto-secrets):
             age.secrets.${secretName} = {
               file = "${"$"}{inputs.agenix-secrets}/secrets/${secretName}.age";
               owner = "agent-${name}";
               mode = "0400";
             };
        '';
      }
    ) mailAgents);

    # Install himalaya CLI system-wide for mail-enabled agents
    environment.systemPackages = [
      pkgs.keystone.himalaya
    ];
  };
}
