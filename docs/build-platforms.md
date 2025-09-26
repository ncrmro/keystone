# Build Platforms

## Requirements

- **Local builds**: Nix must be installed (see Platform Setup below)
- **GitHub Actions**: No local Nix required - builds in cloud
- **NixOS systems**: Nix already installed

## Quick Build Commands

```bash
# Clone and build
git clone https://github.com/yourusername/keystone
cd keystone
./bin/build-iso

# With SSH keys
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

## Platform Setup

### Ubuntu/Debian
```bash
# Install Nix
curl -L https://nixos.org/nix/install | sh
source ~/.bashrc
```

### macOS
```bash
# Install Nix
curl -L https://nixos.org/nix/install | sh
# Or with Homebrew
brew install nix
```

### Windows
```powershell
# Install WSL2 + Ubuntu
wsl --install -d Ubuntu
wsl
# Then follow Ubuntu instructions above
```

## GitHub Actions

Add to `.github/workflows/build-iso.yml`:

```yaml
name: Build ISO
on:
  workflow_dispatch:
    inputs:
      ssh_key:
        description: 'SSH public key to embed in ISO'
        required: false
        type: string

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v22
      
      - name: Build ISO with SSH key
        if: github.event.inputs.ssh_key != ''
        run: |
          ./bin/build-iso --ssh-key '${{ github.event.inputs.ssh_key }}'
          
      - name: Build ISO without SSH key
        if: github.event.inputs.ssh_key == ''
        run: nix build .#iso
        
      - uses: actions/upload-artifact@v3
        with:
          name: keystone-iso
          path: result/iso/*.iso
```

## Fork Instructions

1. Fork this repo on GitHub
2. Clone your fork: `git clone https://github.com/YOURUSERNAME/keystone`
3. Add SSH keys to `flake.nix` or use `./bin/build-iso --ssh-keys`
4. Enable Actions in your fork's Settings → Actions
5. Push to trigger build

## Output

- **Local**: `result/iso/*.iso`
- **GitHub Actions**: Download from Artifacts tab