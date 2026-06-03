# hardware-key evaluation test
#
# Verifies the auto-load wiring in modules/os/hardware-key.nix:
#   - Each declared keystone.keys.<user>.hardwareKeys.<name> entry with
#     autoLoad = true (default) produces a systemd.user.services
#     "ssh-add-<user>-<name>" unit on hosts with
#     keystone.hardwareKey.enable = true.
#   - Agent users (name starting with "agent-") are skipped — they have no
#     interactive session and the keys.nix schema asserts they must not
#     carry hardware keys anyway.
#   - Setting autoLoad = false on an entry opts that key out of auto-load
#     while leaving the public-key registration intact.
#   - The unit's ExecStart references the canonical absolute path
#     ${user.home}/.ssh/id_ed25519_sk_<keyname> — there is no override.
#
# Build: nix build .#hardware-key-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  home-manager ? null,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Minimal NixOS host that turns on keystone.os + keystone.hardwareKey,
  # declares two hardware keys for a human user, and (for Config A) one
  # agent user with hardware keys — to prove the agent-skip guard works.
  baseModules = extraConfig: [
    {
      nixpkgs.overlays = [ self.overlays.default ];
    }
    self.nixosModules.operating-system
    {
      system.stateVersion = "25.05";
      networking.hostName = "hardware-key-test";
      networking.hostId = "deadbeef";
      boot.loader.systemd-boot.enable = true;

      home-manager.sharedModules = [
        {
          keystone.terminal.sandbox.enable = false;
        }
      ];

      keystone.os = {
        enable = true;
        storage = {
          type = "ext4";
          devices = [ "/dev/vda" ];
        };
        users.ncrmro = {
          fullName = "Test User";
          initialPassword = "testpass";
          admin = true;
        };
      };

      keystone.hardwareKey.enable = true;

      fileSystems."/" = {
        device = lib.mkForce "/dev/vda2";
        fsType = lib.mkForce "ext4";
      };
    }
    extraConfig
  ];

  # Config A: two hardware keys on ncrmro, both with default privateKeyFile,
  # plus an agent user declaring its own hardware keys (which the schema
  # would normally reject — we suppress the assertion to prove the wiring
  # also defends against escapees).
  configAModules = baseModules {
    keystone.keys.ncrmro.hardwareKeys = {
      yubi-black = {
        publicKey = "sk-ssh-ed25519@openssh.com AAAAdummy-black yubi-black";
        description = "Primary daily-carry YubiKey";
      };
      yubi-green = {
        publicKey = "sk-ssh-ed25519@openssh.com AAAAdummy-green yubi-green";
        description = "Backup YubiKey";
      };
    };

    # Declare a synthetic agent user (via keystone.os.agents) and force an
    # entry into its hardwareKeys via _module.args bypass — agent assertions
    # would normally block this; we suppress them so the iteration logic is
    # what skips, not eval failure upstream.
    keystone.os.agents.foo = {
      fullName = "Agent Foo";
      notes.repo = "git@example.com:foo/notes.git";
    };
  };

  # Config B: yubi-green opted out via autoLoad = false.
  configBModules = baseModules {
    keystone.keys.ncrmro.hardwareKeys = {
      yubi-black = {
        publicKey = "sk-ssh-ed25519@openssh.com AAAAdummy-black yubi-black";
      };
      yubi-green = {
        publicKey = "sk-ssh-ed25519@openssh.com AAAAdummy-green yubi-green";
        autoLoad = false;
      };
    };
  };

  evalConfig =
    modules:
    (nixosSystem {
      system = "x86_64-linux";
      modules = modules;
    }).config;

  # Inject hardware keys onto an agent user post-eval would defeat the test;
  # instead Config A exercises only the human-user iteration and adds an
  # agent user via keystone.os.agents whose `keystone.keys` entry is
  # auto-created without hardwareKeys. To prove agent-* prefixed users are
  # skipped, we manually declare keystone.keys."agent-foo".hardwareKeys and
  # rely on the lib.hasPrefix guard in hardware-key.nix.
  configAWithAgentKeys = configAModules ++ [
    {
      # SECURITY: This bypass exists only inside the test to verify the
      # iteration guard. Production agents must not carry hardware keys
      # (see modules/keys.nix assertion).
      keystone.keys."agent-foo".hardwareKeys.fake-yubi = {
        publicKey = "sk-ssh-ed25519@openssh.com AAAAdummy-fake fake-yubi";
      };
    }
  ];

  # The agents-hardware-key assertion would fire — disable assertions for
  # Config A by capturing config via .config without forcing assertions.
  # `lib.evalModules`-style configs always run assertions, but reading
  # `.config.systemd.user.services` does not — assertions only fire when
  # serializing the full system or building it. We read user services
  # directly.
  configA = evalConfig configAWithAgentKeys;
  configB = evalConfig configBModules;

  userServicesA = configA.systemd.user.services;
  userServicesB = configB.systemd.user.services;

  jsonOf = v: builtins.toJSON v;

  hasService = svcs: name: builtins.hasAttr name svcs;

  execStartA-black = userServicesA."ssh-add-ncrmro-yubi-black".serviceConfig.ExecStart or "";
  execStartA-green = userServicesA."ssh-add-ncrmro-yubi-green".serviceConfig.ExecStart or "";

  agentSvcNamesA = builtins.filter (n: lib.hasPrefix "ssh-add-agent-" n) (
    builtins.attrNames userServicesA
  );

  checks = [
    {
      name = "A: ssh-add-ncrmro-yubi-black exists";
      ok = hasService userServicesA "ssh-add-ncrmro-yubi-black";
      got = jsonOf (hasService userServicesA "ssh-add-ncrmro-yubi-black");
      want = "true";
    }
    {
      name = "A: ssh-add-ncrmro-yubi-green exists";
      ok = hasService userServicesA "ssh-add-ncrmro-yubi-green";
      got = jsonOf (hasService userServicesA "ssh-add-ncrmro-yubi-green");
      want = "true";
    }
    {
      name = "A: yubi-black ExecStart references /home/ncrmro/.ssh/id_ed25519_sk_yubi-black";
      ok =
        execStartA-black != ""
        && builtins.match ".*/home/ncrmro/.ssh/id_ed25519_sk_yubi-black$" execStartA-black != null;
      got = execStartA-black;
      want = "matches .*/home/ncrmro/.ssh/id_ed25519_sk_yubi-black$";
    }
    {
      name = "A: yubi-green ExecStart references /home/ncrmro/.ssh/id_ed25519_sk_yubi-green";
      ok =
        execStartA-green != ""
        && builtins.match ".*/home/ncrmro/.ssh/id_ed25519_sk_yubi-green$" execStartA-green != null;
      got = execStartA-green;
      want = "matches .*/home/ncrmro/.ssh/id_ed25519_sk_yubi-green$";
    }
    {
      name = "A: agent-* users are skipped (no ssh-add-agent-* services)";
      ok = agentSvcNamesA == [ ];
      got = jsonOf agentSvcNamesA;
      want = "[]";
    }
    {
      name = "B: ssh-add-ncrmro-yubi-black exists";
      ok = hasService userServicesB "ssh-add-ncrmro-yubi-black";
      got = jsonOf (hasService userServicesB "ssh-add-ncrmro-yubi-black");
      want = "true";
    }
    {
      name = "B: ssh-add-ncrmro-yubi-green does NOT exist (autoLoad = false)";
      ok = !(hasService userServicesB "ssh-add-ncrmro-yubi-green");
      got = jsonOf (hasService userServicesB "ssh-add-ncrmro-yubi-green");
      want = "false";
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
  failureReport = lib.concatMapStringsSep "\n" (
    c: "  - ${c.name}: got=${c.got} want=${c.want}"
  ) failures;
  passReport = lib.concatMapStringsSep "\n" (c: "  - ${c.name}: OK") checks;
in
if failures != [ ] then
  throw ''
    hardware-key-evaluation: ${toString (builtins.length failures)} assertion(s) failed:
    ${failureReport}
  ''
else
  pkgs.runCommand "test-hardware-key-evaluation" { } ''
    mkdir -p $out
    cat > $out/hardware-key-evaluation.json <<'ENDJSON'
    {
      "name": "hardware-key-evaluation",
      "checks": ${toString (builtins.length checks)}
    }
    ENDJSON
    echo "hardware-key-evaluation: ${toString (builtins.length checks)} checks passed"
    cat <<'EOF'
    ${passReport}
    EOF
  ''
