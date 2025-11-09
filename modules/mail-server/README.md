# Keystone Mail Server Module

This module provides a complete mail server setup using [Stalwart Mail](https://stalw.art/), a modern all-in-one mail server written in Rust that supports SMTP, IMAP, and JMAP protocols.

## Features

- **Complete mail server**: SMTP, IMAP, and JMAP support
- **Modern security**: Built-in spam filtering, DKIM, SPF, and DMARC support
- **Automatic TLS**: Optional ACME/Let's Encrypt integration
- **Internal user directory**: Built-in user management (LDAP/SQL also supported)
- **High performance**: Written in Rust with RocksDB storage backend
- **Firewall integration**: Automatic firewall port configuration

## Quick Start

### Basic Configuration

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    keystone.url = "github:ncrmro/keystone";
  };

  outputs = { nixpkgs, nixpkgs-unstable, keystone, ... }: {
    nixosConfigurations.mailserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        keystone.nixosModules.mailServer
        {
          # Pass unstable packages for stalwart-mail
          _module.args.pkgs-unstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };

          # Configure mail server
          keystone.mail-server = {
            enable = true;
            hostname = "mail.example.com";
            primaryDomain = "example.com";
            acmeEmail = "admin@example.com";  # For Let's Encrypt
          };

          # Basic system configuration
          networking.hostName = "mailserver";
          system.stateVersion = "25.05";
        }
      ];
    };
  };
}
```

## Configuration Options

### Required Options

- `keystone.mail-server.enable` - Enable the mail server module
- `keystone.mail-server.hostname` - The FQDN for the mail server (e.g., "mail.example.com")
- `keystone.mail-server.primaryDomain` - The primary email domain (e.g., "example.com")

### Optional Options

- `keystone.mail-server.acmeEmail` - Email for ACME/Let's Encrypt certificates (default: null)
  - If null, you must provide certificates manually
- `keystone.mail-server.openFirewall` - Open firewall ports automatically (default: true)
- `keystone.mail-server.package` - Custom stalwart-mail package (default: pkgs-unstable.stalwart-mail)

## DNS Configuration

After enabling the module, configure these DNS records:

### Required Records

```dns
# A/AAAA records (replace with your server IP)
mail.example.com.    IN A     203.0.113.1
mail.example.com.    IN AAAA  2001:db8::1

# MX record
example.com.         IN MX    10 mail.example.com.

# SPF record
example.com.         IN TXT   "v=spf1 mx -all"
```

### Recommended Records (after setup)

```dns
# DMARC record
_dmarc.example.com.  IN TXT   "v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com"

# DKIM record (generate key first using Stalwart)
default._domainkey.example.com. IN TXT "v=DKIM1; k=rsa; p=<your-public-key>"
```

## Firewall Ports

The module automatically opens these ports (if `openFirewall = true`):

- **25** - SMTP (incoming mail)
- **587** - Submission (authenticated mail submission with STARTTLS)
- **465** - Submissions (authenticated mail submission with implicit TLS)
- **143** - IMAP (mail retrieval with STARTTLS)
- **993** - IMAPS (mail retrieval with implicit TLS)
- **443** - HTTPS (JMAP and web admin interface)

The management interface runs on `127.0.0.1:8080` (local only).

## User Management

### Creating Users

Stalwart uses an internal user directory by default. Access the management interface to create users:

```bash
# SSH into your server and access the management interface
curl http://localhost:8080

# Or use port forwarding to access from your local machine
ssh -L 8080:localhost:8080 root@mail.example.com
# Then open http://localhost:8080 in your browser
```

### Using External Directory

To use LDAP or SQL for user management, extend the configuration:

```nix
keystone.mail-server = {
  enable = true;
  hostname = "mail.example.com";
  primaryDomain = "example.com";
};

# Override Stalwart settings for LDAP
services.stalwart-mail.settings = {
  directory."ldap" = {
    type = "ldap";
    url = "ldap://ldap.example.com";
    # ... additional LDAP configuration
  };
};
```

## Security Considerations

1. **Reverse DNS**: Ensure your server IP has proper PTR records
2. **DKIM Keys**: Generate and configure DKIM keys after initial setup
3. **DMARC**: Implement DMARC policy for email authentication
4. **Rate Limiting**: Stalwart includes built-in rate limiting
5. **Spam Filtering**: Configure spam filtering rules in Stalwart settings

## Storage

Mail data is stored in `/var/lib/stalwart-mail/data` using RocksDB with LZ4 compression.

For production deployments, consider:
- Regular backups of `/var/lib/stalwart-mail`
- ZFS or other CoW filesystem for snapshots
- Monitoring disk space usage

## Monitoring

Check service status:

```bash
systemctl status stalwart-mail
journalctl -u stalwart-mail -f
```

View logs in Stalwart admin interface at `http://localhost:8080`.

## Troubleshooting

### Certificates Not Working

If using ACME, ensure:
1. DNS A/AAAA records point to your server
2. Port 443 is accessible from the internet
3. The hostname matches the certificate request

### Mail Not Sending/Receiving

Check:
1. DNS records are correctly configured (MX, A/AAAA, SPF)
2. Ports 25, 587, 465 are not blocked by ISP or firewall
3. Reverse DNS (PTR) is properly configured
4. Stalwart service is running: `systemctl status stalwart-mail`

### Port 25 Blocked

Many ISPs block port 25. Consider:
- Using a VPS or dedicated server
- Requesting your ISP to unblock port 25
- Using a mail relay service

## Advanced Configuration

For advanced Stalwart configuration, override the `services.stalwart-mail.settings` attribute:

```nix
services.stalwart-mail.settings = {
  # Your custom Stalwart configuration
  # See https://stalw.art/docs/ for full documentation
};
```

## References

- [Stalwart Documentation](https://stalw.art/docs/)
- [NixOS Stalwart Module](https://search.nixos.org/options?query=services.stalwart-mail)
- [Email Server Best Practices](https://www.rfc-editor.org/rfc/rfc5321.html)
