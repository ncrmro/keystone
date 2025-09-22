{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    
    settings = [{
      layer = "top";
      position = "top";
      height = 34;
      spacing = 4;
      
      modules-left = [ "hyprland/workspaces" "hyprland/mode" ];
      modules-center = [ "clock" ];
      modules-right = [ "pulseaudio" "network" "battery" "tray" ];
      
      "hyprland/workspaces" = {
        disable-scroll = true;
        all-outputs = true;
        format = "{icon}";
        format-icons = {
          "1" = "1";
          "2" = "2";
          "3" = "3";
          "4" = "4";
          "5" = "5";
          "6" = "6";
          "7" = "7";
          "8" = "8";
          "9" = "9";
          "10" = "10";
        };
      };
      
      clock = {
        format = "{:%H:%M}";
        format-alt = "{:%Y-%m-%d}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };
      
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        format-charging = "{capacity}% 󰂄";
        format-plugged = "{capacity}% ";
        format-alt = "{time} {icon}";
        format-icons = ["󰂃" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
      };
      
      network = {
        format-wifi = "{essid} ({signalStrength}%) ";
        format-ethernet = "{ipaddr}/{cidr} 󰊗";
        tooltip-format = "{ifname} via {gwaddr} 󰊗";
        format-linked = "{ifname} (No IP) 󰊗";
        format-disconnected = "Disconnected ⚠";
        format-alt = "{ifname}: {ipaddr}/{cidr}";
      };
      
      pulseaudio = {
        format = "{volume}% {icon} {format_source}";
        format-bluetooth = "{volume}% {icon} {format_source}";
        format-bluetooth-muted = " {icon} {format_source}";
        format-muted = " {format_source}";
        format-source = "{volume}% ";
        format-source-muted = "";
        format-icons = {
          headphone = "";
          hands-free = "";
          headset = "";
          phone = "";
          portable = "";
          car = "";
          default = ["" "" ""];
        };
        on-click = "pavucontrol";
      };
      
      tray = {
        icon-size = 21;
        spacing = 10;
      };
    }];
    
    style = ''
      * {
        font-family: "JetBrains Mono Nerd Font";
        font-size: 13px;
      }
      
      window#waybar {
        background-color: rgba(30, 30, 46, 0.8);
        color: #cdd6f4;
        transition-property: background-color;
        transition-duration: .5s;
        border-radius: 0;
      }
      
      window#waybar.hidden {
        opacity: 0.2;
      }
      
      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: #cdd6f4;
        border: none;
        border-radius: 0;
      }
      
      #workspaces button:hover {
        background: rgba(0, 0, 0, 0.2);
      }
      
      #workspaces button.active {
        background-color: #89b4fa;
        color: #1e1e2e;
      }
      
      #workspaces button.urgent {
        background-color: #f38ba8;
      }
      
      #clock,
      #battery,
      #cpu,
      #memory,
      #disk,
      #temperature,
      #backlight,
      #network,
      #pulseaudio,
      #wireplumber,
      #custom-media,
      #tray,
      #mode {
        padding: 0 10px;
        color: #cdd6f4;
      }
      
      #battery.charging, #battery.plugged {
        color: #a6e3a1;
      }
      
      @keyframes blink {
        to {
          background-color: #f38ba8;
          color: #1e1e2e;
        }
      }
      
      #battery.critical:not(.charging) {
        background-color: #f38ba8;
        color: #1e1e2e;
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }
    '';
  };
}