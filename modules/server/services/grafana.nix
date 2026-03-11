# Keystone Grafana Service Module
#
# Grafana is an observability platform for metrics visualization.
# Default subdomain: grafana
# Default port: 3002
# Default access: tailscale
#
# When alerts.defaultEnabled is true (default), provisions standard
# infrastructure alert rules (e.g., nix store low disk space).
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.grafana;
in
{
  options.keystone.server.services.grafana = serverLib.mkServiceOptions {
    description = "Grafana observability platform";
    subdomain = "grafana";
    port = 3002;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  } // {
    alerts = {
      defaultEnabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Provision standard infrastructure alert rules (nix store disk space, etc.)";
      };
    };

    services.grafana = {
      enable = true;
      settings.server = {
        http_port = cfg.port;
        http_addr = "127.0.0.1";
        domain = "${cfg.subdomain}.${config.keystone.domain}";
        root_url = "https://${cfg.subdomain}.${config.keystone.domain}/";
      };
      provision.enable = true;
    };

    services.grafana.provision.alerting.rules.settings = {
      apiVersion = 1;
      groups = [
        {
          name = "nix-store";
          folder = "Keystone Alerts";
          interval = "1m";
          orgId = 1;
          rules = [
            {
              uid = "nix-store-full";
              title = "Nix store disk space low";
              condition = "C";
              for = "5m";
              noDataState = "NoData";
              execErrState = "Alerting";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus";
                  relativeTimeRange = {
                    from = 600;
                    to = 0;
                  };
                  model = {
                    expr = ''(node_filesystem_avail_bytes{mountpoint="/nix"} / node_filesystem_size_bytes{mountpoint="/nix"}) * 100'';
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "-100";
                  relativeTimeRange = {
                    from = 600;
                    to = 0;
                  };
                  model = {
                    type = "reduce";
                    expression = "A";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "-100";
                  relativeTimeRange = {
                    from = 600;
                    to = 0;
                  };
                  model = {
                    type = "threshold";
                    expression = "B";
                    conditions = [
                      {
                        evaluator = {
                          type = "lt";
                          params = [10];
                        };
                      }
                    ];
                    refId = "C";
                  };
                }
              ];
              annotations = {
                summary = "Nix store on {{ $labels.instance }} is {{ $values.B.Value | printf \"%.1f\" }}% full";
              };
              labels = {
                severity = "warning";
              };
            }
          ];
        }
      ];
    };
  };

  config = lib.mkMerge [
    # Nginx/DNS registration — only when keystone grafana service is enabled
    (lib.mkIf (serverCfg.enable && cfg.enable) {
      keystone.server._enabledServices.grafana = {
        inherit (cfg)
          subdomain
          port
          access
          maxBodySize
          websockets
          registerDNS
          ;
      };
    })

    # Alert provisioning — fires when Grafana is running, regardless of nginx registration
    (lib.mkIf (serverCfg.enable && config.services.grafana.enable && cfg.alerts.defaultEnabled) {
      services.grafana.provision.alerting.rules.settings = {
        groups = [
          {
            orgId = 1;
            name = "disk-alerts";
            folder = "Infrastructure";
            interval = "1m";
            rules = [
              {
                uid = "nix-store-low-disk-space";
                title = "Nix Store Low Disk Space";
                condition = "C";
                for = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Nix store on {{ $labels.host }} has less than 15% free space";
                };
                data = [
                  {
                    refId = "A";
                    datasourceUid = serverLib.datasourceUids.prometheus;
                    relativeTimeRange = {
                      from = 600;
                      to = 0;
                    };
                    model = {
                      refId = "A";
                      expr = ''max by (host) ((node_filesystem_avail_bytes{mountpoint="/nix/store"} / node_filesystem_size_bytes{mountpoint="/nix/store"}) * 100)'';
                      intervalMs = 1000;
                      maxDataPoints = 43200;
                    };
                  }
                  {
                    refId = "C";
                    datasourceUid = "__expr__";
                    relativeTimeRange = {
                      from = 600;
                      to = 0;
                    };
                    model = {
                      refId = "C";
                      type = "threshold";
                      conditions = [
                        {
                          evaluator = {
                            params = [ 15 ];
                            type = "lt";
                          };
                          operator = {
                            type = "and";
                          };
                          query = {
                            params = [ "C" ];
                          };
                          reducer = {
                            params = [ ];
                            type = "last";
                          };
                          type = "query";
                        }
                      ];
                      expression = "A";
                    };
                  }
                ];
                noDataState = "NoData";
                execErrState = "Error";
              }
            ];
          }
        ];
      };
    })
  ];
}
