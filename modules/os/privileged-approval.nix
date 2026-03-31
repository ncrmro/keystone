{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.security.privilegedApproval;

  makeExecutableScript =
    name: src: substitutions:
    pkgs.runCommand name { } ''
      cp ${pkgs.replaceVars src substitutions} $out
      chmod +x $out
    '';

  commandSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Stable identifier for the allowlisted command.";
      };

      displayName = mkOption {
        type = types.str;
        description = "Human-readable command name shown in approval UX.";
      };

      reason = mkOption {
        type = types.str;
        description = "Default policy reason for this command.";
      };

      runAs = mkOption {
        type = types.str;
        default = "root";
        description = "Target user for execution.";
      };

      approvalMethods = mkOption {
        type = types.listOf (
          types.enum [
            "password"
            "hardware-key"
          ]
        );
        default = [ "password" ];
        description = "Supported approval methods for this command.";
      };

      match = mkOption {
        type = types.enum [
          "exact"
          "prefix"
        ];
        default = "exact";
        description = "How argv matching is applied to the command.";
      };

      argv = mkOption {
        type = types.listOf types.str;
        description = "Exact argv or argv prefix that may be executed.";
      };
    };
  };

  approvalConfig = {
    backend = cfg.backend;
    commands = map (command: {
      inherit (command)
        name
        displayName
        reason
        runAs
        approvalMethods
        match
        argv
        ;
    }) cfg.commands;
  };

  approvalHelperScript = makeExecutableScript "approve-exec.sh" ./scripts/approve-exec.sh {
    configFile = "/etc/keystone/privileged-approval.json";
    jq = "${pkgs.jq}/bin/jq";
  };

  approvalHelper = pkgs.writeShellApplication {
    name = "keystone-approve-exec";
    runtimeInputs = [
      pkgs.jq
    ];
    text = builtins.readFile approvalHelperScript;
  };

  polkitPolicy = pkgs.runCommand "keystone-privileged-approval-policy" { } ''
        mkdir -p "$out/share/polkit-1/actions"
        cat >"$out/share/polkit-1/actions/com.ncrmro.keystone.approve.policy" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE policyconfig PUBLIC
     "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
     "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
    <policyconfig>
      <vendor>Keystone</vendor>
      <vendor_url>https://github.com/ncrmro/keystone</vendor_url>
      <action id="com.ncrmro.keystone.approve">
        <description>Run an approved Keystone privileged command</description>
        <message>Authentication is required to run an approved Keystone privileged command.</message>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>auth_admin_keep</allow_active>
        </defaults>
        <annotate key="org.freedesktop.policykit.exec.path">/run/current-system/sw/bin/keystone-approve-exec</annotate>
        <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
      </action>
    </policyconfig>
    EOF
  '';
in
{
  options.keystone.security.privilegedApproval = {
    enable = mkEnableOption "Keystone privileged approval broker and allowlist";

    backend = mkOption {
      type = types.enum [ "desktop-polkit" ];
      default = "desktop-polkit";
      description = "Approval backend used by `ks approve`.";
    };

    commands = mkOption {
      type = types.listOf commandSubmodule;
      default = [
        {
          name = "keystone-enroll-fido2-auto";
          displayName = "Enroll hardware key for disk unlock";
          reason = "Enroll a FIDO2 hardware key for disk unlock.";
          match = "exact";
          argv = [
            "keystone-enroll-fido2"
            "--auto"
          ];
        }
        {
          name = "ks-switch";
          displayName = "Deploy current Keystone state";
          reason = "Deploy the current local Keystone state to this host.";
          match = "prefix";
          argv = [
            "ks"
            "switch"
          ];
        }
        {
          name = "ks-update";
          displayName = "Run Keystone update";
          reason = "Run the Keystone update workflow for this host.";
          match = "prefix";
          argv = [
            "ks"
            "update"
          ];
        }
      ];
      description = "Allowlisted privileged commands that `ks approve` may execute.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = all (command: command.runAs == "root") cfg.commands;
        message = "keystone.security.privilegedApproval currently supports only runAs = \"root\".";
      }
      {
        assertion =
          let
            names = map (command: command.name) cfg.commands;
          in
          length names == length (unique names);
        message = "keystone.security.privilegedApproval.commands must use unique names.";
      }
    ];

    security.polkit.enable = mkDefault true;

    environment.etc."keystone/privileged-approval.json".text = builtins.toJSON approvalConfig;

    environment.systemPackages = [
      approvalHelper
      polkitPolicy
      pkgs.keystone.ks
      pkgs.polkit
    ];
  };
}
