{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  sshAutoLoadEnabled = config.keystone.terminal.sshAutoLoad.enable or false;
in
{
  config = mkIf cfg.enable (mkMerge [
    {
      # SSH agent as a systemd user service
      # Runs ssh-agent -D -a $SSH_AUTH_SOCK, sets SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent
      services.ssh-agent.enable = true;

      # SSH client configuration with automatic key loading
      programs.ssh = {
        enable = true;
        matchBlocks."*".addKeysToAgent = "1h";
      };
    }

    # Desktop askpass and notification for software-key hosts (ISSUE-REQ-13..21)
    (mkIf sshAutoLoadEnabled {
      # lxqt-openssh-askpass: Qt-based, Wayland-native askpass backend.
      # Chosen over ssh-askpass-fullscreen (X11-only) and ksshaskpass (KDE-heavy).
      # See docs/os/ssh-agent.md for rationale.
      home.packages = [ pkgs.lxqt.lxqt-openssh-askpass ];

      # Export SSH_ASKPASS so desktop unlock flows use the GUI prompt
      wayland.windowManager.hyprland.settings.env = mkAfter [
        "SSH_ASKPASS,lxqt-openssh-askpass"
        "SSH_ASKPASS_REQUIRE,prefer"
      ];

      # Notify on session startup when SSH key is locked (ISSUE-REQ-13..14)
      wayland.windowManager.hyprland.settings.exec-once = mkAfter [
        "bash -c 'sleep 3; if command -v keystone-ssh-health >/dev/null 2>&1; then state=$(keystone-ssh-health 2>/dev/null || true); if [ \"$state\" = locked ] || [ \"$state\" = agent-unreachable ]; then notify-send \"SSH key not loaded\" \"Run: keystone-ssh-unlock\" -u normal -t 10000; fi; fi'"
      ];
    })
  ]);
}
