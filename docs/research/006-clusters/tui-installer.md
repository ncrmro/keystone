# Research: TUI Installer for Keystone Clusters

**Feature**: 006-clusters
**Date**: 2024-12-20
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for implementing a Terminal User Interface (TUI) installer for Keystone Clusters. The installer provides a guided, interactive experience for bootstrapping the Primer Server on bare metal or virtual machines.

## Research Areas

### 1. Go TUI Library Selection

**Decision**: Use Charm's Bubbletea for the TUI framework

**Rationale**:
- Elm-inspired architecture (clean state management)
- Active community and maintenance
- Composable components (Bubbles library)
- First-class support for forms, spinners, progress bars
- Used by major projects (GitHub CLI, Soft Serve, etc.)

**Library Comparison**:

| Library | Architecture | Maturity | Components | Use Case |
|---------|--------------|----------|------------|----------|
| **Bubbletea** | Elm (TEA) | High | Bubbles lib | Complex wizards |
| tview | Widget-based | High | Built-in | Dashboard apps |
| gocui | Low-level | Medium | Minimal | Custom layouts |
| termui | Dashboard | Medium | Widgets | Monitoring |
| tcell | Low-level | High | None | Custom rendering |

**Alternatives Considered**:
- **tview**: More traditional widget approach, less flexible for wizards
- **gocui**: Too low-level, would need to build everything
- **termui**: Dashboard-focused, not suited for installers
- **Rust TUI (ratatui)**: Would require Rust, team expertise in Go

### 2. Bubbletea Architecture

**Core Concepts**:
```go
// Model holds application state
type Model struct {
    step        int
    diskConfig  DiskConfig
    networkConf NetworkConfig
    err         error
    spinner     spinner.Model
    textInput   textinput.Model
}

// Init returns initial command
func (m Model) Init() tea.Cmd {
    return tea.Batch(
        m.spinner.Tick,
        detectHardware(),
    )
}

// Update handles messages and returns new state
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case "enter":
            return m.nextStep()
        case "q", "ctrl+c":
            return m, tea.Quit
        }
    case hardwareDetectedMsg:
        m.hardware = msg.hardware
        return m, nil
    }
    return m, nil
}

// View renders the UI
func (m Model) View() string {
    switch m.step {
    case stepWelcome:
        return m.renderWelcome()
    case stepDiskSelection:
        return m.renderDiskSelection()
    case stepNetworkConfig:
        return m.renderNetworkConfig()
    case stepInstalling:
        return m.renderProgress()
    }
    return ""
}
```

**Bubbles Components Used**:
- `spinner` - Loading indicators
- `textinput` - Text entry fields
- `list` - Disk/network selection
- `progress` - Installation progress
- `viewport` - Scrollable log output
- `table` - Hardware information display

### 3. Multi-Step Wizard Pattern

**Decision**: Implement wizard as state machine with validation between steps

**Wizard Flow**:
```
┌─────────────────────────────────────────────────────────────────┐
│                         KEYSTONE INSTALLER                       │
│                                                                  │
│  Step 1 of 6: Welcome                                           │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  Welcome to Keystone Cluster Setup                              │
│                                                                  │
│  This installer will help you configure:                        │
│    • Encrypted ZFS storage                                      │
│    • Network configuration                                       │
│    • Primer Server bootstrap                                    │
│    • Initial cluster credentials                                │
│                                                                  │
│  Hardware Detected:                                              │
│    CPU: AMD Ryzen 9 5900X (24 cores)                           │
│    RAM: 64 GB                                                   │
│    Disks: 2x NVMe (1TB each)                                    │
│                                                                  │
│  [Enter] Continue    [q] Quit                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Wizard Steps**:
```go
const (
    stepWelcome = iota
    stepDiskSelection
    stepDiskEncryption
    stepNetworkConfig
    stepClusterConfig
    stepConfirmation
    stepInstalling
    stepComplete
)

type WizardState struct {
    CurrentStep    int
    MaxStep        int
    Steps          []StepConfig
    ValidationErrs map[int][]error
}

type StepConfig struct {
    Title       string
    Description string
    Validate    func(Model) error
    CanSkip     bool
}
```

### 4. Hardware Detection Integration

**Decision**: Use Go system calls and /sys filesystem for hardware detection

**Detection Methods**:
```go
type Hardware struct {
    CPU       CPUInfo
    Memory    MemoryInfo
    Disks     []DiskInfo
    Network   []NetworkInterface
    TPM       *TPMInfo
    SecureBoot bool
}

// CPU detection via /proc/cpuinfo
func detectCPU() (CPUInfo, error) {
    data, err := os.ReadFile("/proc/cpuinfo")
    // Parse model name, cores, etc.
}

// Disk detection via lsblk
func detectDisks() ([]DiskInfo, error) {
    cmd := exec.Command("lsblk", "-J", "-o",
        "NAME,SIZE,TYPE,MODEL,SERIAL,ROTA,TRAN")
    output, err := cmd.Output()
    // Parse JSON output
}

// Network detection via /sys/class/net
func detectNetwork() ([]NetworkInterface, error) {
    entries, err := os.ReadDir("/sys/class/net")
    // Read interface properties
}

// TPM detection
func detectTPM() (*TPMInfo, error) {
    if _, err := os.Stat("/dev/tpm0"); err == nil {
        // Read TPM version from /sys/class/tpm/tpm0
    }
    return nil, nil
}
```

**Hardware Display Component**:
```go
func (m Model) renderHardware() string {
    var b strings.Builder

    table := table.New(
        table.WithColumns([]table.Column{
            {Title: "Component", Width: 15},
            {Title: "Details", Width: 50},
        }),
    )

    table.SetRows([]table.Row{
        {"CPU", fmt.Sprintf("%s (%d cores)", m.hardware.CPU.Model, m.hardware.CPU.Cores)},
        {"Memory", humanize.Bytes(m.hardware.Memory.Total)},
        {"TPM", tpmStatus(m.hardware.TPM)},
        {"Secure Boot", boolStatus(m.hardware.SecureBoot)},
    })

    return table.View()
}
```

### 5. NixOS Installer Integration

**Decision**: Generate NixOS configuration and invoke nixos-install

**Integration Points**:
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   TUI Wizard    │────►│  Config Generator│────►│  nixos-install │
│   (Go binary)   │     │  (Nix templates) │     │  (system build) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │ User Input            │ hardware-config.nix   │ /mnt install
        │ - disk selection      │ configuration.nix     │
        │ - encryption pass     │ disko-config.nix      │
        │ - network config      │                       │
        └───────────────────────┴───────────────────────┘
```

**Configuration Generation**:
```go
type NixConfig struct {
    Hostname        string
    DiskDevice      string
    EncryptionKey   string
    NetworkConfig   NetworkConfig
    SSHKeys         []string
    TimezoneRegion  string
}

func generateNixConfig(cfg NixConfig) error {
    // Generate hardware-configuration.nix
    hwConfig := executeTemplate(hardwareTemplate, cfg)
    os.WriteFile("/mnt/etc/nixos/hardware-configuration.nix", hwConfig, 0644)

    // Generate disko configuration
    diskoConfig := executeTemplate(diskoTemplate, cfg)
    os.WriteFile("/mnt/etc/nixos/disko-config.nix", diskoConfig, 0644)

    // Generate main configuration
    mainConfig := executeTemplate(configTemplate, cfg)
    os.WriteFile("/mnt/etc/nixos/configuration.nix", mainConfig, 0644)

    return nil
}
```

**Installation Execution**:
```go
func runInstallation(cfg NixConfig, progress chan<- InstallProgress) error {
    steps := []InstallStep{
        {Name: "Partitioning disk", Cmd: "disko", Args: []string{"--mode", "disko", "/mnt/etc/nixos/disko-config.nix"}},
        {Name: "Creating ZFS pools", Cmd: "disko", Args: []string{"--mode", "mount", "/mnt/etc/nixos/disko-config.nix"}},
        {Name: "Generating config", Cmd: "nixos-generate-config", Args: []string{"--root", "/mnt"}},
        {Name: "Installing NixOS", Cmd: "nixos-install", Args: []string{"--root", "/mnt", "--no-root-passwd"}},
        {Name: "Setting up credentials", Cmd: "keystone-setup-credentials", Args: []string{}},
    }

    for i, step := range steps {
        progress <- InstallProgress{Step: i, Total: len(steps), Name: step.Name}
        if err := executeStep(step); err != nil {
            return fmt.Errorf("step %q failed: %w", step.Name, err)
        }
    }

    return nil
}
```

### 6. qcow2 Testing Workflow

**Decision**: Provide qcow2 VM image for development and testing

**Testing Workflow**:
```
Developer Machine                    Test VM (qcow2)
┌─────────────────┐                 ┌─────────────────┐
│  1. Build ISO   │                 │                 │
│  nix build .#iso│                 │  QEMU/libvirt   │
└────────┬────────┘                 │                 │
         │                          │  Boot from ISO  │
         ▼                          │  Run TUI        │
┌─────────────────┐                 │  Test install   │
│  2. Create VM   │────────────────►│                 │
│  bin/virtual-   │                 │  Verify boot    │
│  machine --start│                 │  Check services │
└─────────────────┘                 └─────────────────┘
```

**VM Testing Script**:
```bash
#!/usr/bin/env bash
# bin/test-tui-installer

set -euo pipefail

# Build installer ISO
nix build .#iso

# Create test VM with empty disk
qemu-img create -f qcow2 test-disk.qcow2 50G

# Boot VM with ISO attached
qemu-system-x86_64 \
    -enable-kvm \
    -m 4G \
    -smp 2 \
    -drive file=test-disk.qcow2,format=qcow2 \
    -cdrom result/iso/keystone-installer.iso \
    -boot d \
    -nic user,hostfwd=tcp::2222-:22 \
    -display gtk \
    -serial mon:stdio
```

**Automated Testing**:
```go
// test/installer_test.go
func TestInstallationFlow(t *testing.T) {
    // Start qcow2 VM
    vm := startTestVM(t)
    defer vm.Cleanup()

    // Send keystrokes to TUI
    vm.SendKeys("enter")           // Welcome screen
    vm.SendKeys("down", "enter")   // Select disk
    vm.SendKeys("testpass")        // Encryption password
    vm.SendKeys("enter")           // Confirm

    // Wait for installation
    vm.WaitForText("Installation complete", 10*time.Minute)

    // Reboot and verify
    vm.Reboot()
    vm.WaitForSSH()

    // Check services
    output := vm.SSH("systemctl is-active etcd")
    assert.Equal(t, "active", strings.TrimSpace(output))
}
```

### 7. Encryption and Security

**Decision**: Use LUKS + ZFS native encryption with TPM2 support

**Encryption Flow in TUI**:
```
┌─────────────────────────────────────────────────────────────────┐
│  Step 3 of 6: Disk Encryption                                   │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  Encryption Method:                                              │
│    [x] LUKS + ZFS Native Encryption (recommended)               │
│    [ ] ZFS Native Encryption Only                               │
│    [ ] No Encryption (not recommended)                          │
│                                                                  │
│  TPM2 Detected: Yes                                              │
│    [x] Enable TPM2 auto-unlock                                  │
│    [x] Require passphrase on first boot                         │
│                                                                  │
│  Enter encryption passphrase:                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ ●●●●●●●●●●●●                                              │   │
│  └──────────────────────────────────────────────────────────┘   │
│  Confirm passphrase:                                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ ●●●●●●●●●●●●                                              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Password Strength: ████████░░ Strong                           │
│                                                                  │
│  [Enter] Continue    [←] Back    [q] Quit                       │
└─────────────────────────────────────────────────────────────────┘
```

**Credential Generation**:
```go
type ClusterCredentials struct {
    CACert           []byte
    CAKey            []byte
    AdminCert        []byte
    AdminKey         []byte
    EtcdPeerCert     []byte
    EtcdPeerKey      []byte
    ServiceAccountKey []byte
}

func generateClusterCredentials() (*ClusterCredentials, error) {
    creds := &ClusterCredentials{}

    // Generate CA
    caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
    caCert, err := createCACertificate(caKey)
    creds.CACert = pemEncode(caCert)
    creds.CAKey = pemEncode(caKey)

    // Generate admin client cert
    adminKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
    adminCert, err := createClientCertificate("admin", caKey, caCert, adminKey)
    creds.AdminCert = pemEncode(adminCert)
    creds.AdminKey = pemEncode(adminKey)

    // Generate etcd peer certs
    // ... similar for other credentials

    return creds, nil
}
```

### 8. Error Handling and Recovery

**Decision**: Implement comprehensive error handling with recovery options

**Error Display**:
```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠ Installation Error                                          │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  Failed during: Partitioning disk                               │
│                                                                  │
│  Error Details:                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ disko: unable to create ZFS pool on /dev/nvme0n1         │   │
│  │ error: pool 'rpool' already exists                        │   │
│  │                                                            │   │
│  │ This may occur if a previous installation was interrupted.│   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Options:                                                        │
│    [r] Retry step                                                │
│    [f] Force (destroy existing pool)                            │
│    [b] Back to disk selection                                   │
│    [l] View full logs                                           │
│    [q] Quit installer                                           │
└─────────────────────────────────────────────────────────────────┘
```

**Error Types**:
```go
type InstallError struct {
    Step        string
    Cause       error
    Recoverable bool
    Actions     []RecoveryAction
}

type RecoveryAction struct {
    Key         string
    Description string
    Handler     func() error
}

func handleInstallError(err InstallError) tea.Cmd {
    if err.Recoverable {
        return showRecoveryOptions(err)
    }
    return showFatalError(err)
}
```

### 9. Accessibility and UX

**Design Principles**:
- High contrast colors for visibility
- Keyboard-only navigation
- Clear progress indication
- Helpful error messages with solutions
- Consistent layout across screens

**Color Scheme**:
```go
var (
    titleStyle = lipgloss.NewStyle().
        Bold(true).
        Foreground(lipgloss.Color("#00ff00"))

    errorStyle = lipgloss.NewStyle().
        Bold(true).
        Foreground(lipgloss.Color("#ff0000"))

    successStyle = lipgloss.NewStyle().
        Foreground(lipgloss.Color("#00ff00"))

    subtleStyle = lipgloss.NewStyle().
        Foreground(lipgloss.Color("#666666"))
)
```

**Progress Indication**:
```go
func (m Model) renderProgress() string {
    var b strings.Builder

    // Overall progress bar
    b.WriteString(fmt.Sprintf("Installing Keystone... %d%%\n\n", m.progress.Percent))
    b.WriteString(m.progressBar.View())
    b.WriteString("\n\n")

    // Current step indicator
    for i, step := range m.installSteps {
        var status string
        switch {
        case i < m.progress.CurrentStep:
            status = "✓"
        case i == m.progress.CurrentStep:
            status = m.spinner.View()
        default:
            status = "○"
        }
        b.WriteString(fmt.Sprintf("  %s %s\n", status, step.Name))
    }

    // Log output viewport
    b.WriteString("\n")
    b.WriteString(m.logViewport.View())

    return b.String()
}
```

## Integration Points

### With Existing Keystone Base
- Installer extends existing `bin/build-iso` workflow
- Uses existing disko module for disk configuration
- Leverages existing NixOS modules for system configuration

### With Headscale
- Installer generates Headscale pre-auth keys
- Configures initial ACLs for admin access
- Sets up DERP relay configuration

### With Observability
- Installer configures initial Prometheus/Grafana setup
- Sets admin credentials for monitoring services

### With OIDC/AWS
- Generates initial OIDC signing keys
- Configures AWS IAM trust relationship metadata

## Key Findings Summary

1. **Bubbletea is the ideal framework** - Elm architecture, great components, active community
2. **Multi-step wizard pattern** - State machine with validation between steps
3. **Hardware detection is essential** - Guide users to optimal configuration
4. **NixOS integration is straightforward** - Generate configs, call nixos-install
5. **qcow2 enables rapid testing** - Automated end-to-end testing possible
6. **Error recovery is critical** - Installation failures must be handleable

## Open Questions Resolved

- **Q**: Should we use Rust (ratatui) instead of Go (bubbletea)?
  - **A**: Go preferred - team expertise, integration with existing Go tools

- **Q**: How do we test the TUI non-interactively?
  - **A**: Use expect-like testing with screen capture and keystroke injection

- **Q**: Can the installer run on minimal ISO?
  - **A**: Yes, Go binary is self-contained, can embed in NixOS ISO

- **Q**: How do we handle slow disk operations in TUI?
  - **A**: Use async commands with spinner/progress indicators

## Next Steps

1. Set up Go project structure with Bubbletea
2. Implement hardware detection module
3. Create wizard step components (disk, network, encryption)
4. Integrate NixOS configuration generation
5. Build qcow2 testing workflow
6. Create automated test suite
