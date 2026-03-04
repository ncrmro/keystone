# Hardware Keys (YubiKey/FIDO2)

This guide covers using hardware security keys (YubiKey, SoloKey, etc.) with Keystone for SSH authentication, GPG signing, and secrets management.

## Prerequisites

Enable the hardware-key module in your NixOS configuration:

```nix
keystone.hardwareKey.enable = true;
```

This enables:
- `pcscd` service for smart card communication
- GPG agent with SSH support
- YubiKey management tools

## Multi-Key Strategy (Primary + Backup)

Use two YubiKeys: a **primary** for daily carry and a **backup** stored securely. Distinguish them with color stickers (YubiKey sells sticker packs) and use color names throughout your configuration.

| Key Name | Role | Storage | Color |
|----------|------|---------|-------|
| `yubi-black` | Primary - daily carry | Keychain | Black (default) |
| `yubi-green` | Backup - safe storage | Home safe / lockbox | Green sticker |

Both keys should be enrolled for SSH, age encryption, and authorized on all hosts. If the primary is lost, the backup can decrypt all secrets and re-key without downtime.

### Naming Convention

Use `yubi-<color>` as the key name everywhere:
- NixOS module: `keystone.hardwareKey.keys.yubi-black`, `keystone.hardwareKey.keys.yubi-green`
- SSH application: `-O application=ssh:ncrmro-yubi-black`, `-O application=ssh:ncrmro-yubi-green`
- SSH comment: `-C "ncrmro-yubi-black"`, `-C "ncrmro-yubi-green"`
- Age identity labels in config comments: `# Serial: XXXXX, yubi-black`

### Example NixOS Configuration

```nix
keystone.hardwareKey = {
  enable = true;
  keys.yubi-black = {
    description = "Primary YubiKey 5 NFC (USB-A, black)";
    sshPublicKey = "sk-ssh-ed25519@openssh.com AAAAGnNr... ncrmro-yubi-black";
  };
  keys.yubi-green = {
    description = "Backup YubiKey 5C NFC (USB-C, green sticker)";
    sshPublicKey = "sk-ssh-ed25519@openssh.com AAAAGnNr... ncrmro-yubi-green";
  };
  rootKeys = [ "yubi-black" "yubi-green" ];
};
```

### Example agenix secrets.nix

```nix
yubikeys = {
  ncrmro-yubi-black = "age1yubikey1q...";  # Serial: 36854515
  ncrmro-yubi-green = "age1yubikey1q...";  # Serial: 36862273
};

adminKeys = [
  users.ncrmro-laptop
  users.ncrmro-workstation
  yubikeys.ncrmro-yubi-black
  yubikeys.ncrmro-yubi-green
];
```

### Example Home Manager (age identities)

```nix
keystone.terminal.ageYubikey = {
  enable = true;
  identities = [
    "AGE-PLUGIN-YUBIKEY-17DDRYQ..."  # Serial: 36854515, Slot: 1 (yubi-black)
    "AGE-PLUGIN-YUBIKEY-1A2B3C4..."  # Serial: 36862273, Slot: 1 (yubi-green)
  ];
};
```

## SSH with FIDO2 Keys

There are two types of FIDO2 SSH keys, with different firmware requirements:

| Feature | Firmware Required |
|---------|------------------|
| ECDSA-SK (non-resident) | 5.0+ |
| Ed25519-SK (non-resident) | 5.2.3+ |
| Resident keys | 5.2.3+ |

Check your firmware: `ykman info`

**Note:** YubiKey firmware cannot be updated. If you have firmware < 5.2.3, use `ecdsa-sk` instead of `ed25519-sk`.

### Resident Keys (Firmware 5.2.3+)

Stored directly on the YubiKey - no key files to manage. Plug in your YubiKey on any machine and the key is available.

```bash
# Primary key (black)
ssh-keygen -t ed25519-sk -O resident -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black"

# Backup key (green) - swap YubiKeys and run again
ssh-keygen -t ed25519-sk -O resident -O application=ssh:ncrmro-yubi-green -C "ncrmro-yubi-green" -f ~/.ssh/id_ed25519_sk_yubi_green
```

The `-C` flag sets a descriptive comment (instead of defaulting to `user@hostname`), and `-O application=ssh:<name>` namespaces the credential on the YubiKey.

#### Load Resident Keys into SSH Agent

On any machine with your YubiKey plugged in:

```bash
ssh-add -K
```

This loads all resident SSH keys from the YubiKey into your agent. No key files needed.

#### Automate Key Loading on Shell Startup

Add to your shell configuration (e.g., `~/.zshrc` or via home-manager):

```bash
# Auto-load YubiKey SSH keys if available
if command -v ssh-add &> /dev/null && [ -n "$SSH_AUTH_SOCK" ]; then
  ssh-add -K 2>/dev/null
fi
```

Or with home-manager:

```nix
programs.zsh.initExtra = ''
  # Auto-load YubiKey SSH keys if available
  if command -v ssh-add &> /dev/null && [ -n "$SSH_AUTH_SOCK" ]; then
    ssh-add -K 2>/dev/null
  fi
'';
```

### Non-Resident Keys (Firmware 5.0+)

For older YubiKeys (firmware < 5.2.3) or backup keys. The "private key" file is just a handle - the actual secret never leaves the YubiKey. Safe to store in dotfiles/home-manager.

```bash
# Firmware 5.2.3+ (preferred)
ssh-keygen -t ed25519-sk -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black" -f ~/.ssh/id_ed25519_sk_yubi_black

# Firmware 5.0+ (use if ed25519-sk fails)
ssh-keygen -t ecdsa-sk -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black" -f ~/.ssh/id_ecdsa_sk_yubi_black
```

You'll need to copy the key files to other machines, or manage via home-manager (see below).

#### Managing Non-Resident Keys with Home Manager

For non-resident keys, you can distribute the key handle via home-manager. The "private key" is just a reference - useless without the physical YubiKey.

```nix
# In your home-manager config
home.file.".ssh/id_ed25519_sk_yubikey" = {
  source = ./keys/id_ed25519_sk_yubikey;
  mode = "0600";
};

home.file.".ssh/id_ed25519_sk_yubikey.pub" = {
  source = ./keys/id_ed25519_sk_yubikey.pub;
  mode = "0644";
};

# Add to SSH config
programs.ssh = {
  enable = true;
  matchBlocks."*".identityFile = "~/.ssh/id_ed25519_sk_yubikey";
};
```

Store the key files in your config repo (e.g., `home-manager/keys/`). They're safe to commit - the private key handle is useless without your YubiKey.

### List Keys on YubiKey

```bash
# List resident credentials
ykman fido credentials list

# List keys in SSH agent
ssh-add -L
```

## GPG with YubiKey

The hardware-key module enables GPG agent with SSH support. To use GPG keys stored on YubiKey:

```bash
# Check YubiKey GPG status
gpg --card-status

# Import public key (if not already in keyring)
gpg --import publickey.asc

# Trust the key
gpg --edit-key <KEY_ID>
> trust
> 5
> quit
```

### SSH via GPG Agent

If you have SSH keys on your YubiKey's GPG applet:

```bash
# Get SSH public key from GPG
gpg --export-ssh-key <KEY_ID>

# Add to ~/.ssh/authorized_keys on remote hosts
```

## Age Encryption with YubiKey (agenix)

The module includes `age-plugin-yubikey` for encrypting secrets with your YubiKey.

### Setup

```bash
# Generate age identity on YubiKey
age-plugin-yubikey

# List YubiKey identities
age-plugin-yubikey --list
```

### Use with agenix

Add your YubiKey age public keys to `secrets.nix`. Enroll both primary and backup keys so either can decrypt secrets:

```nix
let
  yubikeys = {
    ncrmro-yubi-black = "age1yubikey1q...";  # Serial: 36854515
    ncrmro-yubi-green = "age1yubikey1q...";  # Serial: 36862273
  };
  adminKeys = [ yubikeys.ncrmro-yubi-black yubikeys.ncrmro-yubi-green ];
in {
  "secret.age".publicKeys = adminKeys;
}
```

## Troubleshooting

### YubiKey not detected

```bash
# Check if pcscd is running
systemctl status pcscd

# Check USB devices
lsusb | grep -i yubi

# Restart pcscd
sudo systemctl restart pcscd
```

### SSH agent not loading keys

```bash
# Check if SSH agent is running
echo $SSH_AUTH_SOCK

# Check agent keys
ssh-add -l

# Try loading manually with verbose output
ssh-add -K -v
```

### GPG card not found

```bash
# Restart GPG agent
gpgconf --kill gpg-agent
gpg --card-status
```

## References

- [YubiKey SSH Guide](https://developers.yubico.com/SSH/)
- [FIDO2 Resident Keys](https://developers.yubico.com/WebAuthn/WebAuthn_Developer_Guide/Resident_Keys.html)
- [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey)
