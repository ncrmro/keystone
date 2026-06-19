# Keystone Dev VM Module — declarative libvirt domains
#
# Manages one or more long-lived KVM guests on a server host. Each guest
# boots a qcow2 produced by `keystone.lib.mkVMImage` (a normal keystone
# nixosConfiguration), runs on an isolated libvirt NAT network, and is
# defined + autostarted via a systemd one-shot at activation.
#
# This is the lower-level primitive. The agent-facing wrapper is
# modules/os/agents/dev-vm.nix, which generates a guest config per agent
# and registers it here automatically. Operators can also use
# keystone.server.devVm.hosts directly to host arbitrary keystone images.
#
# Lifecycle:
#   - First activation seeds /var/lib/libvirt/images/dev-vm-<name>.qcow2
#     from the image package and writes a sentinel file naming the image
#     store path. Subsequent rebuilds compare the sentinel: if the image
#     hash changes the operator MUST manually clear the disk to pick it
#     up (we never overwrite a running guest's state).
#   - The libvirt network and domain are virsh-defined idempotently. An
#     update to the rendered XML is applied via `virsh define` (which
#     replaces the persistent definition); the running domain keeps its
#     current XML until reboot, matching libvirt semantics.
#
{
  lib,
  config,
  options,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.server.devVm;

  # The dev-VM module reaches into keystone.os.hypervisor when both modules
  # coexist on the same host. Server-only evaluation (without the OS module)
  # would crash on a dangling option path, so guard the cross-module wiring
  # behind this check.
  hasOs = options ? keystone.os && options.keystone.os ? hypervisor;

  netCidr = cfg.network.subnet; # e.g. "192.168.200.0/24"
  netPrefix = elemAt (splitString "/" netCidr) 0; # "192.168.200.0"
  octets = splitString "." netPrefix;
  netBase3 = concatStringsSep "." (lib.lists.take 3 octets); # "192.168.200"
  gatewayIP = "${netBase3}.1";
  netmask = "255.255.255.0"; # /24 only — keep it simple
  dhcpStart = "${netBase3}.100";
  dhcpEnd = "${netBase3}.200";

  vmHostSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        image = mkOption {
          type = types.package;
          description = ''
            A vm-image-* package (keystone.lib.mkVMImage output) whose
            qcow2 disk(s) will boot in this guest.
          '';
        };

        diskFile = mkOption {
          type = types.str;
          default = "disk0.qcow2";
          description = ''
            Filename inside the image package to use as the boot disk.
            ZFS hosts produce disk0.qcow2; ext4 hosts produce root.qcow2.
          '';
        };

        memory = mkOption {
          type = types.int;
          default = 4096;
          description = "RAM in MiB.";
        };

        vcpus = mkOption {
          type = types.int;
          default = 4;
          description = "vCPU count.";
        };

        autostart = mkOption {
          type = types.bool;
          default = true;
          description = "Start the domain on host boot and keep it running.";
        };

        mac = mkOption {
          type = types.str;
          example = "52:54:00:6b:dd:01";
          description = ''
            Stable MAC address for the guest interface. Required so the
            libvirt DHCP server hands out a stable IP and the host's
            ssh_known_hosts entries don't churn on rebuild.
          '';
        };
      };
    }
  );

  # Render libvirt network XML once.
  networkXml = pkgs.writeText "${cfg.network.name}.xml" ''
    <network>
      <name>${cfg.network.name}</name>
      <forward mode='nat'>
        <nat>
          <port start='1024' end='65535'/>
        </nat>
      </forward>
      <bridge name='${cfg.network.bridge}' stp='on' delay='0'/>
      <ip address='${gatewayIP}' netmask='${netmask}'>
        <dhcp>
          <range start='${dhcpStart}' end='${dhcpEnd}'/>
        </dhcp>
      </ip>
    </network>
  '';

  # Render a domain XML for a single guest.
  domainXml =
    name: vm:
    let
      diskPath = "/var/lib/libvirt/images/dev-vm-${name}.qcow2";
    in
    pkgs.writeText "dev-vm-${name}.xml" ''
      <domain type='kvm'>
        <name>dev-vm-${name}</name>
        <memory unit='MiB'>${toString vm.memory}</memory>
        <vcpu placement='static'>${toString vm.vcpus}</vcpu>

        <os>
          <type arch='x86_64' machine='q35'>hvm</type>
          <loader readonly='yes' secure='yes' type='pflash'>/run/libvirt/nix-ovmf/OVMF_CODE.fd</loader>
          <nvram template='/run/libvirt/nix-ovmf/OVMF_VARS.fd'>/var/lib/libvirt/qemu/nvram/dev-vm-${name}_VARS.fd</nvram>
          <boot dev='hd'/>
        </os>

        <features>
          <acpi/>
          <apic/>
          <smm state='on'>
            <tseg unit='MiB'>48</tseg>
          </smm>
        </features>

        <cpu mode='host-passthrough' check='none'/>

        <clock offset='utc'>
          <timer name='rtc' tickpolicy='catchup'/>
          <timer name='pit' tickpolicy='delay'/>
          <timer name='hpet' present='no'/>
        </clock>

        <on_poweroff>destroy</on_poweroff>
        <on_reboot>restart</on_reboot>
        <on_crash>restart</on_crash>

        <devices>
          <emulator>/run/current-system/sw/bin/qemu-system-x86_64</emulator>

          <disk type='file' device='disk'>
            <driver name='qemu' type='qcow2'/>
            <source file='${diskPath}'/>
            <target dev='vda' bus='virtio'/>
          </disk>

          <interface type='network'>
            <source network='${cfg.network.name}'/>
            <mac address='${vm.mac}'/>
            <model type='virtio'/>
          </interface>

          <serial type='pty'>
            <target type='isa-serial' port='0'>
              <model name='isa-serial'/>
            </target>
          </serial>
          <console type='pty'>
            <target type='serial' port='0'/>
          </console>

          <tpm model='tpm-crb'>
            <backend type='emulator' version='2.0'/>
          </tpm>

          <video>
            <model type='virtio' heads='1' primary='yes'/>
          </video>
        </devices>
      </domain>
    '';

  # systemd-bound helpers. virsh always invoked against the system URI.
  virsh = "${pkgs.libvirt}/bin/virsh -c qemu:///system";

  netService = {
    description = "Define libvirt network ${cfg.network.name}";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.libvirt ];
    script = ''
      set -eu
      if ${virsh} net-info ${cfg.network.name} >/dev/null 2>&1; then
        # Update definition in place; this is idempotent.
        ${virsh} net-define ${networkXml} >/dev/null
      else
        ${virsh} net-define ${networkXml} >/dev/null
      fi
      ${virsh} net-autostart ${cfg.network.name} >/dev/null
      if ! ${virsh} net-info ${cfg.network.name} | grep -q '^Active:.*yes'; then
        ${virsh} net-start ${cfg.network.name} >/dev/null
      fi
    '';
  };

  vmServices = mapAttrs' (
    name: vm:
    let
      diskPath = "/var/lib/libvirt/images/dev-vm-${name}.qcow2";
      sentinel = "/var/lib/libvirt/images/dev-vm-${name}.image-source";
    in
    nameValuePair "libvirt-dev-vm-${name}" {
      description = "Define and start dev VM ${name}";
      after = [
        "libvirtd.service"
        "libvirt-keystone-devnet.service"
      ];
      requires = [
        "libvirtd.service"
        "libvirt-keystone-devnet.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.libvirt
        pkgs.coreutils
        pkgs.qemu_kvm
      ];
      script = ''
        set -eu
        # Seed the qcow2 from the image package on first boot only. Once the
        # guest writes to it, the sentinel pins us to the original source —
        # operators must manually clear the disk to pick up a new image.
        if [ ! -e "${diskPath}" ]; then
          install -d -m 0755 /var/lib/libvirt/images
          cp --reflink=auto "${vm.image}/${vm.diskFile}" "${diskPath}"
          chmod 0600 "${diskPath}"
          # Resize the qcow2 virtual size to give the guest headroom; the
          # disko-built image is sized to the layout it carries.
          ${pkgs.qemu_kvm}/bin/qemu-img resize "${diskPath}" +32G || true
          echo "${vm.image}" > "${sentinel}"
        fi

        # Define / redefine the domain. virsh define is idempotent; an
        # already-running domain keeps its current XML until reboot.
        ${virsh} define ${domainXml name vm} >/dev/null

        ${optionalString vm.autostart ''
          ${virsh} autostart dev-vm-${name} >/dev/null || true
          if ! ${virsh} domstate dev-vm-${name} | grep -q running; then
            ${virsh} start dev-vm-${name} >/dev/null
          fi
        ''}
      '';
    }
  ) cfg.hosts;
in
{
  options.keystone.server.devVm = {
    enable = mkEnableOption "Run keystone dev VMs on this host";

    network = {
      name = mkOption {
        type = types.str;
        default = "keystone-devnet";
        description = "libvirt network name shared by all dev VMs on this host.";
      };

      bridge = mkOption {
        type = types.str;
        default = "virkdv0";
        description = "Bridge interface name for the dev-VM network.";
      };

      subnet = mkOption {
        type = types.str;
        default = "192.168.200.0/24";
        description = ''
          IPv4 subnet for the dev-VM network. Currently only /24 is
          supported; the gateway is the .1 host of the subnet.
        '';
      };
    };

    hosts = mkOption {
      type = types.attrsOf vmHostSubmodule;
      default = { };
      description = ''
        Map of dev-VM name → guest options. The name becomes the libvirt
        domain name (prefixed `dev-vm-`) and the on-disk qcow2 filename.
      '';
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.hosts != { }) {
      systemd.tmpfiles.rules = [
        "d /var/lib/libvirt/images 0755 root root -"
        "d /var/lib/libvirt/qemu/nvram 0755 root root -"
      ];

      systemd.services = vmServices // {
        libvirt-keystone-devnet = netService;
      };
    })

    # Cross-module wiring with keystone.os.hypervisor. Only emitted when the
    # OS module is in scope on this host — keeps standalone server-only
    # evaluation (tests/module/server-evaluation.nix) from tripping on a
    # dangling option path.
    (mkIf (cfg.enable && cfg.hosts != { } && hasOs) (
      lib.optionalAttrs hasOs {
        keystone.os.hypervisor.enable = mkDefault true;
        keystone.os.hypervisor.allowedBridges = [
          "virbr0"
          cfg.network.bridge
        ];
      }
    ))

    (mkIf (cfg.enable && cfg.hosts != { } && !hasOs) {
      assertions = [
        {
          assertion = false;
          message = ''
            keystone.server.devVm requires the keystone OS module (which
            provides keystone.os.hypervisor) on the same host. Import
            keystone.nixosModules.operating-system on this host.
          '';
        }
      ];
    })
  ];
}
