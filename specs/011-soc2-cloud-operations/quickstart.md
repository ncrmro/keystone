# SOC2 Cloud Operations - Quickstart Guide

## Overview

This quickstart guide helps you deploy Keystone infrastructure with SOC2 compliance controls for cloud or hybrid cloud environments. It provides the fastest path to achieving SOC2 Type 2 certification readiness.

## Prerequisites

- **Time to Certification**: 6-12 months minimum (required for SOC2 Type 2 evidence collection)
- **Infrastructure**: Cloud accounts (AWS, GCP, Azure, or others) or hybrid infrastructure
- **Personnel**: Security officer, operations team, compliance specialist
- **Budget**: Auditor fees ($15,000-$50,000+), tooling costs, personnel time

## Trust Services Criteria Selection

Before starting, determine which criteria apply to your organization:

- **Security** (MANDATORY): All organizations
- **Availability**: If you provide always-on services or have uptime SLAs
- **Confidentiality**: If you handle sensitive customer data
- **Processing Integrity**: If you process data on behalf of customers
- **Privacy**: If you handle personally identifiable information (PII)

## Quick Deployment Path

### Step 1: Deploy Base Infrastructure (Week 1-2)

Deploy Keystone with full security stack enabled:

```bash
# 1. Create NixOS configuration with SOC2 controls
cat > configuration.nix <<'EOF'
{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    <keystone/modules/disko-single-disk-root>
    <keystone/modules/server>  # or modules/client for workstations
  ];

  # Enable full security stack
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/your-disk-id";
    enableEncryptedSwap = true;
  };

  # TPM2 for automatic unlock
  keystone.tpm-enrollment.enable = true;

  # Server services (adjust based on needs)
  keystone.server = {
    enable = true;
    vpn.enable = true;  # Encrypted inter-node communication
    dns.enable = true;
  };

  # SOC2 compliance configurations
  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=31536000  # 1 year retention
    Compress=yes
    Seal=yes
  '';

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    execWheelOnly = true;
  };

  # Firewall with logging
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    logRefusedConnections = true;
  };

  # User management (declarative only)
  users.mutableUsers = false;
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3... admin@company.com"
    ];
  };

  system.stateVersion = "25.05";
}
EOF

# 2. Deploy to cloud VM or on-premises hardware
nixos-anywhere --flake .#your-config root@<target-ip>

# 3. Verify security controls
ssh admin@<target-ip>
sudo systemctl status
sudo zpool status
sudo tpm2_pcrread  # Verify TPM is functional
```

### Step 2: Implement Git-Based Configuration Management (Week 2)

```bash
# 1. Create Git repository for infrastructure
git init infrastructure
cd infrastructure
mkdir -p hosts/{server1,server2,client1}

# 2. Store all configurations
cp /etc/nixos/configuration.nix hosts/server1/
git add hosts/
git commit -m "Initial infrastructure configuration"

# 3. Create change management workflow
cat > .github/pull_request_template.md <<'EOF'
## Change Description
<!-- Describe the infrastructure change -->

## Testing
- [ ] Tested in staging environment
- [ ] Rollback procedure documented
- [ ] No security regressions

## Security Review
- [ ] Maintains SOC2 compliance controls
- [ ] Reviewed by security team
- [ ] Audit logging not affected

## Approval
- [ ] Operations team approval
- [ ] Security team approval (for security-impacting changes)
EOF

git add .github/
git commit -m "Add change management workflow"

# 4. Push to remote repository (GitHub, GitLab, etc.)
git remote add origin git@github.com:yourorg/infrastructure.git
git push -u origin main
```

### Step 3: Deploy Centralized Logging (Week 3)

```bash
# Option A: Using systemd-journal-remote (built-in)
# On log collection server:
services.systemd-journal-upload.enable = true;

# On each Keystone node:
services.systemd-journal-remote = {
  enable = true;
  url = "https://log-server.company.com:19532/upload";
};

# Option B: Using Loki + Grafana (recommended)
# Deploy Loki stack for centralized logging
services.loki = {
  enable = true;
  configuration = {
    auth_enabled = false;
    server.http_listen_port = 3100;
    ingester = {
      lifecycler = {
        address = "127.0.0.1";
        ring.kvstore.store = "inmemory";
        final_sleep = "0s";
      };
      chunk_idle_period = "5m";
      chunk_retain_period = "30s";
    };
  };
};

services.promtail = {
  enable = true;
  configuration = {
    server = {
      http_listen_port = 9080;
      grpc_listen_port = 0;
    };
    clients = [{
      url = "http://localhost:3100/loki/api/v1/push";
    }];
    scrape_configs = [{
      job_name = "journal";
      journal = {
        max_age = "12h";
        labels = {
          job = "systemd-journal";
        };
      };
    }];
  };
};

services.grafana = {
  enable = true;
  settings.server = {
    http_addr = "0.0.0.0";
    http_port = 3000;
  };
};
```

### Step 4: Implement Backup and DR (Week 4)

```bash
# 1. Configure automated ZFS snapshots
services.zfs.autoSnapshot = {
  enable = true;
  frequent = 4;  # Every 15 minutes
  hourly = 24;
  daily = 30;
  weekly = 12;
  monthly = 84;  # 7 years for compliance
};

# 2. Configure off-site backups using Syncoid
services.syncoid = {
  enable = true;
  commands = {
    "rpool/data" = {
      target = "backup-server:rpool/backups/server1/data";
      recursive = true;
      extraArgs = [ "--no-privilege-elevation" ];
    };
  };
};

# 3. Test disaster recovery
# Document the procedure in docs/disaster-recovery.md
```

### Step 5: Vulnerability Management (Week 5)

```bash
# 1. Set up weekly vulnerability scanning
# Using nmap and OpenVAS (or Nessus, Qualys for commercial)

# Simple vulnerability check using nix-shell
nix-shell -p nmap --run "nmap -sV --script vulners <target-ip>"

# 2. Automate patching process
# Create weekly maintenance window for updates
services.system.autoUpgrade = {
  enable = true;
  dates = "Sun 02:00";  # Weekly Sunday 2 AM
  allowReboot = false;  # Require manual approval
  channel = "https://nixos.org/channels/nixos-unstable";
};

# 3. Create vulnerability tracking system
# Use Jira, Linear, or GitHub Issues to track findings
```

### Step 6: Documentation (Week 6-8)

Create required policy documents:

```bash
mkdir -p docs/policies
cd docs/policies

# Create each required policy (templates below)
touch information-security-policy.md
touch access-control-policy.md
touch encryption-policy.md
touch backup-disaster-recovery-policy.md
touch incident-response-policy.md
touch change-management-policy.md
touch risk-management-policy.md
touch vendor-management-policy.md

# Create operational procedures
mkdir -p docs/procedures
touch docs/procedures/user-provisioning.md
touch docs/procedures/patch-management.md
touch docs/procedures/backup-restore.md
touch docs/procedures/disaster-recovery.md
touch docs/procedures/incident-response.md
```

### Step 7: Begin Evidence Collection (Month 3+)

SOC2 Type 2 requires 3-12 months of evidence. Start collecting immediately:

```bash
# 1. Create evidence collection directory structure
mkdir -p evidence/{access-reviews,backups,vulnerability-scans,patches,incidents,changes,training}

# 2. Automate evidence collection
# Example: Monthly access review
cat > scripts/access-review.sh <<'EOF'
#!/usr/bin/env bash
# Monthly access review evidence collection

DATE=$(date +%Y-%m)
EVIDENCE_DIR="evidence/access-reviews/$DATE"
mkdir -p "$EVIDENCE_DIR"

# Export current user list with privileges
nixos-rebuild build-vm --show-trace && \
  nix eval .#nixosConfigurations.your-config.config.users.users --json > \
  "$EVIDENCE_DIR/user-list.json"

# Export sudo access
sudo grep -r "wheel" /etc/group > "$EVIDENCE_DIR/sudo-access.txt"

# Export SSH keys
sudo find /etc/ssh -name "*.pub" > "$EVIDENCE_DIR/ssh-keys.txt"

echo "Access review evidence collected: $EVIDENCE_DIR"
EOF

chmod +x scripts/access-review.sh

# 3. Schedule monthly evidence collection
# Add to cron or systemd timer
```

## Minimum Compliance Timeline

- **Month 1-2**: Infrastructure deployment, security controls implementation
- **Month 3-5**: Evidence collection begins, operational procedures established
- **Month 6-8**: Continue evidence collection, conduct internal audit, DR testing
- **Month 9-10**: Gap remediation, audit preparation, documentation review
- **Month 11-12**: SOC2 audit engagement, provide evidence, receive report

**Note**: You cannot achieve SOC2 Type 2 faster than 3 months because the audit requires evidence of control operation over time. 6-month audit periods are most common.

## Common Pitfalls

1. **Starting evidence collection late**: Begin on Day 1, not Month 6
2. **Incomplete documentation**: Policies and procedures must be complete before audit
3. **Manual processes**: Automate evidence collection to ensure completeness
4. **Ignoring availability controls**: Most cloud services need availability in scope
5. **Poor change management**: Every infrastructure change must be tracked in Git
6. **Missing access reviews**: Quarterly access reviews are expected for SOC2
7. **No DR testing**: Disaster recovery must be tested, not just documented
8. **Weak vendor management**: Cloud providers and other vendors need assessment

## Testing Your Compliance

### Pre-Audit Self-Assessment

Run this self-assessment quarterly:

```bash
#!/usr/bin/env bash
# SOC2 compliance self-assessment

echo "=== SOC2 Compliance Self-Assessment ==="

# Check encryption
echo "✓ Checking encryption..."
lsblk -f | grep -q "crypto_LUKS" && echo "  ✓ LUKS encryption enabled" || echo "  ✗ LUKS encryption missing"
zfs get encryption rpool/crypt | grep -q "aes-256" && echo "  ✓ ZFS encryption enabled" || echo "  ✗ ZFS encryption missing"

# Check TPM
echo "✓ Checking TPM..."
systemd-cryptenroll --tpm2-device=list >/dev/null 2>&1 && echo "  ✓ TPM2 available" || echo "  ✗ TPM2 not found"

# Check logging
echo "✓ Checking audit logging..."
journalctl --disk-usage | grep -q "Archived" && echo "  ✓ Journal retention configured" || echo "  ✗ Journal retention not configured"

# Check backups
echo "✓ Checking backups..."
zfs list -t snapshot | grep -q "$(date +%Y-%m-%d)" && echo "  ✓ Recent snapshots found" || echo "  ✗ No recent snapshots"

# Check firewall
echo "✓ Checking firewall..."
systemctl is-active firewall >/dev/null 2>&1 && echo "  ✓ Firewall active" || echo "  ✗ Firewall not active"

# Check fail2ban
echo "✓ Checking intrusion prevention..."
systemctl is-active fail2ban >/dev/null 2>&1 && echo "  ✓ fail2ban active" || echo "  ✗ fail2ban not active"

# Check user management
echo "✓ Checking user management..."
grep -q "mutableUsers = false" /etc/nixos/configuration.nix && echo "  ✓ Declarative users enabled" || echo "  ✗ Mutable users allowed"

# Check Git repository
echo "✓ Checking configuration management..."
cd /etc/nixos && git status >/dev/null 2>&1 && echo "  ✓ Git repository initialized" || echo "  ✗ No Git repository"

echo ""
echo "Review complete. Address any ✗ items before audit."
```

## Next Steps

1. **Review the full specification**: `specs/011-soc2-cloud-operations/spec.md`
2. **Engage a SOC2 auditor**: Select a CPA firm experienced with technology companies
3. **Develop detailed procedures**: Use spec as template for organization-specific procedures
4. **Implement monitoring**: Set up dashboards to track compliance metrics
5. **Train personnel**: Ensure team understands SOC2 requirements and their roles
6. **Conduct internal audit**: Test controls before engaging external auditor
7. **Begin Type 1 (optional)**: Some organizations do Type 1 first, then Type 2 after 6 months

## Resources

- AICPA Trust Services Criteria: https://www.aicpa.org/
- SOC2 Academy (free training): https://soc2.academy/
- Keystone Documentation: https://github.com/ncrmro/keystone
- Compliance automation tools: Vanta, Drata, Secureframe (commercial options)

## Support

For Keystone-specific SOC2 implementation questions:
- GitHub Issues: https://github.com/ncrmro/keystone/issues
- Discussions: https://github.com/ncrmro/keystone/discussions

For SOC2 audit questions:
- Consult with your chosen auditor
- AICPA resources and guidance
- Information security consultants specializing in compliance
