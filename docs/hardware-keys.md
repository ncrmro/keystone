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

## SSH with FIDO2 Keys

There are two types of FIDO2 SSH keys:

| Type | Firmware Required | Key File Needed | Best For |
|------|------------------|-----------------|----------|
| **Resident** | 5.2.3+ | No (stored on YubiKey) | Primary key, multiple machines |
| **Non-resident** | 5.0+ | Yes (copy between machines) | Older YubiKeys, backup keys |

Check your firmware: `ykman info`

### Resident Keys (Firmware 5.2.3+)

Stored directly on the YubiKey - no key files to manage. Plug in your YubiKey on any machine and the key is available.

```bash
ssh-keygen -t ed25519-sk -O resident -O application=ssh:myidentity
```

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
ssh-keygen -t ed25519-sk -O application=ssh:myidentity -f ~/.ssh/id_ed25519_sk_mykey
```

You'll need to copy `id_ed25519_sk_mykey` and `id_ed25519_sk_mykey.pub` to other machines, or manage via home-manager (see below).

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

Add your YubiKey age public key to `secrets.nix`:

```nix
let
  # YubiKey age public key (from age-plugin-yubikey --list)
  yubikey = "age1yubikey1...";
in {
  "secret.age".publicKeys = [ yubikey ];
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
