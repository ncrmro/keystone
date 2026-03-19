# Keystone OS Agents Observability Module
#
# Provisions Grafana dashboards and alerting rules for monitoring agent health,
# task completion rates, and blocked tasks.
#
{
  lib,
  config,
  ...
}:
let
  osCfg = config.keystone.os;
  cfg = osCfg.agents;
in
{
  config = lib.mkIf (osCfg.enable && cfg != { } && config.services.grafana.enable) {
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "Keystone Agents";
        options.path = ./dashboards;
      }
    ];

    # TODO: Add alerting rules for agent failures/stalls
    # services.grafana.provision.alerting.rules.settings = { ... };
  };
}
