# Keystone OS Hardware Key Module
#
# Enables FIDO2/YubiKey integration for system authentication.
# Provides support for:
# - GPG/SSH agent with hardware key support
# - age-plugin-yubikey for agenix secrets
#
# Hardware key SSH public keys and age identities are declared in
# keystone.keys.<user>.hardwareKeys — this module only handles
# hardware enablement (pcscd, udev, GPG agent) and rootKeys wiring.
#
# TODO: Physical touch for sudo authentication (PAM U2F)
# TODO: LUKS disk encryption enrollment (slot configuration)
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.hardwareKey;
  keysCfg = config.keystone.keys;

  # Resolve "username/keyname" references to SSH public keys
  resolveRootKey =
    ref:
    let
      parts = splitString "/" ref;
      username = elemAt parts 0;
      keyname = elemAt parts 1;
    in
    keysCfg.${username}.hardwareKeys.${keyname}.publicKey;
in
{
  options.keystone.hardwareKey = {
    enable = mkEnableOption "Hardware key (FIDO2/YubiKey) system integration";

    rootKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        References to hardware keys (format: "username/keyname") whose SSH
        public keys should be added to root's authorized_keys. Keys are
        looked up from keystone.keys.<username>.hardwareKeys.<keyname>.
      '';
      example = [
        "ncrmro/yubi-black"
        "ncrmro/yubi-green"
      ];
    };

    # TODO: LUKS support
    # luksSlot = mkOption {
    #   type = types.int;
    #   default = 2;
    #   description = "LUKS keyslot to use for hardware key enrollment";
    # };

    # TODO: Sudo touch authentication
    # sudoTouchAuth = mkEnableOption "Require physical touch on hardware key for sudo";

    gpgAgent = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GPG agent with SSH support for hardware key authentication";
      };

      enableSSHSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SSH support through GPG agent (use hardware key for SSH)";
      };
    };
  };

  config = mkMerge [
    # Inbound auth: accepting a hardware-key-signed SSH session to root is
    # just static pubkey text in authorized_keys. It does not require any
    # hardware-key reader on THIS host, so it must not be gated on
    # `enable` — VPS hosts with no physical YubiKey still need root SSH
    # from clients that have one. Always wire when rootKeys is non-empty.
    (mkIf (cfg.rootKeys != [ ]) {
      assertions = map (
        ref:
        let
          parts = splitString "/" ref;
          username = elemAt parts 0;
          keyname = elemAt parts 1;
        in
        {
          assertion =
            length parts == 2 && keysCfg ? ${username} && keysCfg.${username}.hardwareKeys ? ${keyname};
          message = "keystone.hardwareKey.rootKeys references '${ref}' but no such key exists in keystone.keys.${username}.hardwareKeys.${keyname}";
        }
      ) cfg.rootKeys;

      users.users.root.openssh.authorizedKeys.keys = map resolveRootKey cfg.rootKeys;
    })

    # Outbound auth + local UX: smart-card services, agent, CLI tools. Only
    # makes sense on hosts that actually have the hardware plugged in.
    (mkIf cfg.enable {
      services.pcscd.enable = true;
      hardware.gpgSmartcards.enable = true;

      # TODO: PAM U2F authentication for sudo
      # security.pam.services.sudo.u2fAuth = cfg.sudoTouchAuth;

      environment.systemPackages = with pkgs; [
        yubikey-manager
        age-plugin-yubikey
        pam_u2f
        yubico-piv-tool
        yubikey-personalization
      ];

      programs.gnupg.agent = mkIf cfg.gpgAgent.enable {
        enable = true;
        enableSSHSupport = cfg.gpgAgent.enableSSHSupport;
      };

      # Outbound: auto-load each declared SK private key into the user's
      # ssh-agent at session start. Without this, the keystone.keys registry
      # only wires authorized_keys on the receiving side; the user still has
      # to manually `ssh-add` every YubiKey after every login.
      # Agent users are skipped (they don't run interactive sessions and
      # the schema asserts agents have no hardwareKeys).
      systemd.user.services = lib.mkMerge (
        lib.concatLists (
          lib.mapAttrsToList (
            username: _userCfg:
            lib.optionals (!lib.hasPrefix "agent-" username) (
              lib.mapAttrsToList (
                keyname: keyCfg:
                lib.mkIf (keyCfg.privateKeyFile != null) {
                  "ssh-add-${username}-${keyname}" = {
                    description = "Auto-load hardware key ${keyname} for ${username}";
                    wantedBy = [ "default.target" ];
                    after = [ "ssh-agent.service" ];
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      Environment = [ "SSH_AUTH_SOCK=%t/ssh-agent" ];
                      # -q swallows "device not found" so absent YubiKeys don't fail.
                      ExecStart = "${pkgs.openssh}/bin/ssh-add -q ${keyCfg.privateKeyFile}";
                    };
                  };
                }
              ) (keysCfg.${username}.hardwareKeys or { })
            )
          ) config.keystone.os.users
        )
      );
    })
  ];
}
