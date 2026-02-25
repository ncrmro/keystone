# Agent isolation VM test
#
# Boots a NixOS VM with 2 agents and 1 human user, then verifies:
# - Agent UIDs in the 4000+ range
# - Agents in `agents` group, NOT `wheel`
# - Home directories with chmod 700 and correct ownership
# - Cross-agent, agent-human, and human-agent filesystem isolation
# - Agents cannot sudo or write to system paths
# - Users can write to their own home
# - Desktop agent has labwc/wayvnc services and config files
# - Non-desktop agent has no desktop services
#
# Build: nix build .#test-agent-isolation
# Interactive: nix build .#test-agent-isolation.driverInteractive
#
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.nixosTest {
  name = "agent-isolation";

  nodes.machine =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        self.nixosModules.operating-system
      ];

      # Keystone OS with agents
      keystone.os = {
        enable = true;

        # Skip disko/secure-boot/tpm for VM testing
        storage.enable = false;
        secureBoot.enable = false;
        tpm.enable = false;

        # ext4 code path (creates create-agent-homes + create-user-homes services)
        storage.type = "ext4";

        # Human user
        users.testuser = {
          fullName = "Test User";
          initialPassword = "testpass";
          extraGroups = [ "wheel" ];
        };

        # Two agents (alphabetical: coder=4001, researcher=4002)
        # researcher has desktop enabled, coder does not
        agents.coder = {
          fullName = "Coding Agent";
        };
        agents.researcher = {
          fullName = "Research Agent";
          desktop.enable = true;
        };
      };

      # Minimal boot config for VM
      fileSystems."/" = {
        device = "/dev/vda";
        fsType = "ext4";
      };
      boot.loader.systemd-boot.enable = true;
      system.stateVersion = "25.05";

      # sudo needed for testing agent can't use it
      security.sudo.enable = true;

      # VM settings
      virtualisation = {
        memorySize = 2048;
        cores = 2;
      };
    };

  testScript = ''
    print("Starting agent isolation test...")

    machine.wait_for_unit("multi-user.target")
    print("System booted successfully")

    # Wait for home directory services
    machine.wait_for_unit("create-agent-homes.service")
    machine.wait_for_unit("create-user-homes.service")
    print("Home directory services completed")

    # 1. Agent UIDs in 4000+ range (alphabetical: coder=4001, researcher=4002)
    uid_coder = machine.succeed("id -u agent-coder").strip()
    assert uid_coder == "4001", f"Expected agent-coder UID 4001, got {uid_coder}"
    print(f"  agent-coder UID: {uid_coder}")

    uid_researcher = machine.succeed("id -u agent-researcher").strip()
    assert uid_researcher == "4002", f"Expected agent-researcher UID 4002, got {uid_researcher}"
    print(f"  agent-researcher UID: {uid_researcher}")
    print("PASS: Agent UIDs in 4000+ range")

    # 2. Agents in `agents` group, NOT in `wheel`
    coder_groups = machine.succeed("id -Gn agent-coder").strip()
    assert "agents" in coder_groups, f"agent-coder not in agents group: {coder_groups}"
    assert "wheel" not in coder_groups, f"agent-coder should not be in wheel: {coder_groups}"

    researcher_groups = machine.succeed("id -Gn agent-researcher").strip()
    assert "agents" in researcher_groups, f"agent-researcher not in agents group: {researcher_groups}"
    assert "wheel" not in researcher_groups, f"agent-researcher should not be in wheel: {researcher_groups}"
    print("PASS: Agents in agents group, not wheel")

    # 3. Human user exists with wheel
    testuser_groups = machine.succeed("id -Gn testuser").strip()
    assert "wheel" in testuser_groups, f"testuser not in wheel: {testuser_groups}"
    print("PASS: Human user in wheel group")

    # 4. Home dirs exist with chmod 700
    coder_perms = machine.succeed("stat -c '%a' /home/agent-coder").strip()
    assert coder_perms == "700", f"agent-coder home perms: {coder_perms}, expected 700"

    researcher_perms = machine.succeed("stat -c '%a' /home/agent-researcher").strip()
    assert researcher_perms == "700", f"agent-researcher home perms: {researcher_perms}, expected 700"

    testuser_perms = machine.succeed("stat -c '%a' /home/testuser").strip()
    assert testuser_perms == "700", f"testuser home perms: {testuser_perms}, expected 700"
    print("PASS: Home directories have 700 permissions")

    # 5. Correct ownership (user:agents for agents, user:users for human)
    coder_owner = machine.succeed("stat -c '%U:%G' /home/agent-coder").strip()
    assert coder_owner == "agent-coder:agents", f"agent-coder home owner: {coder_owner}"

    researcher_owner = machine.succeed("stat -c '%U:%G' /home/agent-researcher").strip()
    assert researcher_owner == "agent-researcher:agents", f"agent-researcher home owner: {researcher_owner}"

    testuser_owner = machine.succeed("stat -c '%U:%G' /home/testuser").strip()
    assert testuser_owner == "testuser:users", f"testuser home owner: {testuser_owner}"
    print("PASS: Correct ownership on home directories")

    # 6. Agent can't read other agent's home
    machine.fail("su - agent-researcher -c 'ls /home/agent-coder/'")
    print("PASS: Agent cannot read other agent's home")

    # 7. Agent can't read human user's home
    machine.fail("su - agent-researcher -c 'ls /home/testuser/'")
    print("PASS: Agent cannot read human user's home")

    # 8. Human can't read agent homes
    machine.fail("su - testuser -c 'ls /home/agent-researcher/'")
    print("PASS: Human cannot read agent's home")

    # 9. Agent can't sudo
    machine.fail("su - agent-researcher -c 'sudo -n id'")
    print("PASS: Agent cannot sudo")

    # 10. Agent can't write to /etc or /nix/store
    machine.fail("su - agent-researcher -c 'touch /etc/test-write'")
    machine.fail("su - agent-researcher -c 'touch /nix/store/test-write'")
    print("PASS: Agent cannot write to system paths")

    # 11. Users can write to their own home
    machine.succeed("su - agent-coder -c 'touch ~/test-file'")
    machine.succeed("su - agent-researcher -c 'touch ~/test-file'")
    machine.succeed("su - testuser -c 'touch ~/test-file'")
    print("PASS: Users can write to own home")

    # === Desktop runtime validation (FR-002) ===
    print("")
    print("Starting desktop runtime tests...")

    # 12. labwc compositor is running
    machine.wait_for_unit("labwc-agent-researcher.service")
    print("PASS: labwc service active for researcher")

    # 13. Wayland socket created (researcher UID=4002)
    machine.wait_for_file("/run/user/4002/wayland-0", timeout=15)
    print("PASS: Wayland socket created")

    # 15. wayvnc is running
    machine.wait_for_unit("wayvnc-agent-researcher.service")
    print("PASS: wayvnc service active for researcher")

    # 16. VNC port accepting connections
    machine.wait_for_open_port(5901, timeout=15)
    print("PASS: VNC port 5901 accepting connections")

    # 17. wlr-randr confirms virtual output at correct resolution
    output = machine.succeed(
        "su - agent-researcher -c '"
        "XDG_RUNTIME_DIR=/run/user/4002 "
        "WAYLAND_DISPLAY=wayland-0 "
        "wlr-randr'"
    )
    assert "HEADLESS-1" in output, f"Expected HEADLESS-1 in wlr-randr output: {output}"
    print("PASS: wlr-randr shows HEADLESS-1 virtual output")

    # 18. Config files exist with correct ownership
    machine.succeed("test -f /home/agent-researcher/.config/labwc/autostart")
    machine.succeed("test -f /home/agent-researcher/.config/labwc/rc.xml")
    config_owner = machine.succeed("stat -c '%U:%G' /home/agent-researcher/.config/labwc/autostart").strip()
    assert config_owner == "agent-researcher:agents", f"labwc config owner: {config_owner}"
    print("PASS: Config files exist with correct ownership")

    # 19. VNC is localhost-only (not in firewall)
    fw_rules = machine.succeed("iptables -L -n 2>/dev/null || nft list ruleset 2>/dev/null || echo 'no firewall'")
    assert "5901" not in fw_rules, "VNC port 5901 should NOT be in firewall (localhost-only)"
    print("PASS: VNC port not exposed in firewall (localhost-only)")

    # 20. Non-desktop agent has none of this
    machine.fail("systemctl is-enabled labwc-agent-coder.service")
    machine.fail("test -f /home/agent-coder/.config/labwc/autostart")
    print("PASS: Non-desktop agent has no desktop services or config")

    print("")
    print("All agent isolation tests passed!")
  '';
}
