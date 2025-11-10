# Using Keystone Terminal Dev Environment in Codespaces/Devcontainers

This guide explains how to use Keystone's terminal development environment in GitHub Codespaces, VS Code devcontainers, or any remote development environment. This is ideal for developers who want a consistent, fully-configured terminal environment at work or in cloud-based development scenarios.

## Overview

Keystone's terminal development environment provides a complete, pre-configured terminal-based development setup with:

### 🛠️ Core Tools

| Tool | Description | Key Features |
|------|-------------|--------------|
| **Helix** | Modern modal text editor | LSP support for Nix, Bash, YAML, JSON, Dockerfile, Markdown |
| **Zsh** | Enhanced shell | oh-my-zsh, auto-suggestions, syntax highlighting |
| **Zellij** | Terminal multiplexer | Tabs, panes, session persistence (alternative to tmux) |
| **Git & Lazygit** | Version control | Git with LFS + beautiful TUI interface |
| **Starship** | Cross-shell prompt | Git-aware, context-rich prompt |
| **Zoxide** | Smart directory navigation | Jump to frequent directories with `z` command |
| **Direnv** | Environment loader | Auto-load project-specific environments |

### 📦 Additional Utilities

- **eza** - Modern `ls` replacement with icons and git integration
- **ripgrep** - Lightning-fast search (aliased as `grep`)
- **jq** - JSON processor
- **htop** - Interactive process viewer
- **tree** - Directory tree viewer
- **zesh** - Custom Zellij session manager with zoxide integration

### 🎯 Quick Aliases

```bash
l, ls    → eza -1l           # Better file listing
grep     → rg                # Faster searching
g        → git               # Quick git access
lg       → lazygit           # Launch Lazygit TUI
hx       → helix             # Launch Helix editor
zs       → zesh              # Zellij session manager
z <name> → zoxide jump       # Smart directory jumping
```

---

## Why Use This in Codespaces/Devcontainers?

✅ **Consistent Environment** - Same tools and configuration everywhere
✅ **Pre-configured LSPs** - Language servers ready for Nix, Bash, YAML, JSON, etc.
✅ **Modular & Composable** - Enable/disable individual tools as needed
✅ **Nix-powered** - Reproducible, declarative configuration
✅ **Work-ready** - Professional setup without manual configuration
✅ **Fast Setup** - Get productive immediately in any environment

---

## Setup Methods

### Method 1: NixOS-based Devcontainer (Recommended)

This method uses a NixOS base image with the full terminal dev environment.

#### 1. Create Devcontainer Configuration

Create `.devcontainer/devcontainer.json` in your project:

```json
{
  "name": "Keystone Terminal Dev",
  "image": "nixos/nix:latest",
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": false,
      "installOhMyZsh": false
    }
  },
  "postCreateCommand": "bash .devcontainer/setup.sh",
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh"
      },
      "extensions": [
        "jnoortheen.nix-ide"
      ]
    }
  },
  "remoteUser": "nixos"
}
```

#### 2. Create Setup Script

Create `.devcontainer/setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up Keystone Terminal Dev Environment..."

# Enable Nix flakes and modern Nix commands
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF

# Add Keystone flake input to your project flake (if using flakes)
# Or clone Keystone repository for standalone use
if [ ! -f "flake.nix" ]; then
  echo "📦 Creating standalone flake.nix with Keystone terminal environment..."
  cat > flake.nix <<'EOF'
{
  description = "Development environment with Keystone terminal tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    keystone.url = "github:ncrmro/keystone";
  };

  outputs = { self, nixpkgs, home-manager, keystone, ... }: {
    homeConfigurations.devuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        keystone.homeManagerModules.terminalDevEnvironment
        {
          home.username = "devuser";
          home.homeDirectory = "/home/devuser";
          home.stateVersion = "25.05";

          programs.terminal-dev-environment = {
            enable = true;

            # All tools enabled by default, but can be toggled:
            tools = {
              git = true;
              editor = true;      # Helix
              shell = true;       # Zsh + utilities
              multiplexer = true; # Zellij
              terminal = true;    # Ghostty (may not work in container)
            };

            # Optional: Add extra packages
            extraPackages = with nixpkgs.legacyPackages.x86_64-linux; [
              # Add your project-specific tools here
              # ripgrep  # Already included
              # fd
              # bat
            ];
          };

          programs.git = {
            userName = "Your Name";
            userEmail = "your.email@example.com";
          };
        }
      ];
    };
  };
}
EOF
fi

# Build and activate home-manager configuration
echo "🔨 Building home-manager configuration..."
nix build .#homeConfigurations.devuser.activationPackage

echo "✨ Activating configuration..."
./result/activate

echo "✅ Setup complete! Terminal dev environment is ready."
echo "💡 Reload your shell or run: exec zsh"
```

Make it executable:
```bash
chmod +x .devcontainer/setup.sh
```

#### 3. Open in Codespace/Devcontainer

**For GitHub Codespaces:**
1. Push `.devcontainer/` directory to your repository
2. Create a new Codespace
3. Wait for setup to complete
4. Reload terminal: `exec zsh`

**For VS Code Devcontainers:**
1. Open project in VS Code
2. Press `F1` → "Dev Containers: Reopen in Container"
3. Wait for setup to complete
4. Reload terminal: `exec zsh`

---

### Method 2: Home-Manager in Any Environment

Use this method to add the terminal dev environment to an existing devcontainer or Codespace.

#### 1. Install Nix

Add to your `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/nix:1": {
      "version": "latest"
    }
  },
  "postCreateCommand": "bash .devcontainer/setup-home-manager.sh"
}
```

#### 2. Create Home-Manager Setup Script

Create `.devcontainer/setup-home-manager.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up Home-Manager with Keystone terminal environment..."

# Enable experimental features
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF

# Install home-manager
nix-channel --add https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz home-manager
nix-channel --update

# Create home-manager configuration
mkdir -p ~/.config/home-manager
cat > ~/.config/home-manager/flake.nix <<'EOF'
{
  description = "Home Manager configuration with Keystone terminal environment";

  inputs = {
    nixpkgs.url = "github:nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    keystone.url = "github:ncrmro/keystone";
  };

  outputs = { nixpkgs, home-manager, keystone, ... }: {
    homeConfigurations."$USER" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        keystone.homeManagerModules.terminalDevEnvironment
        {
          home.username = builtins.getEnv "USER";
          home.homeDirectory = builtins.getEnv "HOME";
          home.stateVersion = "25.05";

          programs.terminal-dev-environment.enable = true;

          programs.git = {
            userName = "Your Name";
            userEmail = "your.email@example.com";
          };
        }
      ];
    };
  };
}
EOF

# Build and activate
cd ~/.config/home-manager
nix run home-manager/release-25.05 -- switch --flake .

echo "✅ Home-Manager setup complete!"
echo "💡 Reload your shell: exec zsh"
```

Make it executable:
```bash
chmod +x .devcontainer/setup-home-manager.sh
```

---

### Method 3: Quick Setup with Nix Profile (Lightweight)

For a simpler, non-declarative approach:

```bash
# Install Nix (if not present)
curl -L https://nixos.org/nix/install | sh

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Install Keystone terminal environment directly
nix profile install github:ncrmro/keystone#homeConfigurations.testuser.activationPackage

# Activate
~/.nix-profile/activate

# Reload shell
exec zsh
```

---

## Configuration Examples

### Minimal Configuration

Just the essentials:

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    tools = {
      git = true;
      editor = true;
      shell = true;
      multiplexer = false;  # Disable Zellij
      terminal = false;     # Disable Ghostty (not needed in containers)
    };
  };

  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
}
```

### Full Configuration with Customization

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    tools = {
      git = true;
      editor = true;
      shell = true;
      multiplexer = true;
      terminal = false;  # Usually not needed in devcontainers
    };

    extraPackages = with pkgs; [
      # Your project-specific tools
      nodejs_22
      python312
      docker-compose
      kubectl
    ];
  };

  # Customize Git configuration
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";

    # Override default aliases
    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      unstage = "reset HEAD --";
    };

    extraConfig = {
      pull.rebase = true;
      fetch.prune = true;
    };
  };

  # Customize Helix editor
  programs.helix.settings = {
    theme = "gruvbox";
    editor = {
      line-number = "relative";
      mouse = true;
      auto-save = true;
    };
  };

  # Customize Zsh
  programs.zsh = {
    shellAliases = {
      dc = "docker-compose";
      k = "kubectl";
      vim = "hx";  # Use Helix instead of vim
    };
  };

  # Customize Zellij
  programs.zellij.settings = {
    theme = "gruvbox-dark";
    startup_tips = false;
    default_layout = "compact";
  };
}
```

### Project-Specific Environment

For a specific project with custom tools:

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    extraPackages = with pkgs; [
      # Web development
      nodejs_22
      yarn
      nodePackages.typescript
      nodePackages.typescript-language-server

      # Database tools
      postgresql
      redis

      # Infrastructure
      terraform
      ansible

      # Cloud CLI tools
      awscli2
      google-cloud-sdk
    ];
  };

  # Add language servers for Helix
  programs.helix = {
    languages.language = [
      {
        name = "typescript";
        language-servers = [ "typescript-language-server" ];
        auto-format = true;
      }
      {
        name = "javascript";
        language-servers = [ "typescript-language-server" ];
        auto-format = true;
      }
    ];
  };
}
```

---

## Usage Guide

### Getting Started

After setup, reload your shell:

```bash
exec zsh
```

### Core Workflow

```bash
# Navigate with zoxide (learns from your usage)
z projects          # Jump to ~/projects or similar
z keystone          # Jump to most-used "keystone" directory

# Edit files with Helix
hx README.md        # Opens with LSP support
hx src/main.nix     # Nix files get auto-formatting

# Use Zellij for terminal multiplexing
zellij              # Start default session
zs                  # Use zesh for smart session management

# Git workflow with Lazygit
lg                  # Opens beautiful TUI for git operations
g st                # Quick git status
g f && g p          # Fetch and pull
```

### Helix Editor Basics

Helix is a **modal editor** (like Vim/Kakoune) with built-in LSP support:

```
Normal mode (default):
  i     → Insert mode (before cursor)
  a     → Insert mode (after cursor)
  o     → Insert line below
  O     → Insert line above
  x     → Select line
  w     → Select word
  d     → Delete selection
  y     → Copy selection
  p     → Paste
  u     → Undo
  /     → Search
  :     → Command mode

Command mode:
  :w    → Save
  :q    → Quit
  :wq   → Save and quit
  :q!   → Quit without saving

LSP features:
  gd    → Go to definition
  gr    → Go to references
  K     → Show hover documentation
  Space + a → Code actions
```

Full manual: `:tutor` inside Helix

### Zellij Basics

```
Ctrl + o          → Enter command mode (then release and press next key)

In command mode:
  c               → Create new tab
  n               → Next tab
  p               → Previous tab
  h/j/k/l         → Move between panes
  n (then arrow)  → New pane in direction
  x               → Close pane
  d               → Detach session

Smart session management:
  zs              → Open zesh (Zellij + zoxide integration)
```

### Zoxide Smart Navigation

```bash
# Zoxide learns your habits
cd ~/projects/keystone
cd ~/work/important-project
cd ~/personal/blog

# Later, jump quickly:
z key           # Jumps to ~/projects/keystone
z imp           # Jumps to ~/work/important-project
z blog          # Jumps to ~/personal/blog

# Interactive selection with multiple matches
z proj          # Shows menu if multiple matches

# Query what zoxide knows
zoxide query key
zoxide query --list
```

### Direnv for Project Environments

The terminal environment includes `direnv` for automatic environment loading:

```bash
# In your project directory, create .envrc:
echo 'use flake' > .envrc
direnv allow

# Now direnv automatically loads/unloads as you cd in/out
cd ~/project      # Loads .envrc
cd ~              # Unloads .envrc
```

---

## Integration with VS Code

### Recommended Settings

Add to `.vscode/settings.json`:

```json
{
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.profiles.linux": {
    "zsh": {
      "path": "zsh",
      "args": ["-l"]
    }
  },
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nil"
}
```

### Recommended Extensions

```json
{
  "recommendations": [
    "jnoortheen.nix-ide",
    "bbenoist.nix"
  ]
}
```

### Using Helix as VS Code Terminal Editor

You can use Helix for quick edits in the VS Code terminal while keeping VS Code for larger work:

```bash
# In VS Code terminal
hx quick-edit.md    # Opens in terminal with Helix
```

---

## Troubleshooting

### "nix: command not found"

**Solution**: Install Nix first:
```bash
curl -L https://nixos.org/nix/install | sh
```

### "experimental-features 'nix-command flakes' are not enabled"

**Solution**: Enable flakes:
```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### Zsh not loading configuration

**Solution**: Ensure home-manager activation completed:
```bash
~/.nix-profile/activate
exec zsh
```

### LSP not working in Helix

**Solution**: Verify language servers are installed:
```bash
which bash-language-server
which yaml-language-server
which nil  # Nix LSP
```

If missing, rebuild home-manager:
```bash
home-manager switch --flake ~/.config/home-manager
```

### Ghostty not working in container

**Expected**: Ghostty is a GUI terminal emulator and won't work in headless containers. Disable it:

```nix
programs.terminal-dev-environment.tools.terminal = false;
```

### Zellij sessions not persisting

**Solution**: Zellij stores sessions in `~/.local/share/zellij`. Ensure this directory persists in your devcontainer by mounting it:

```json
{
  "mounts": [
    "source=${localWorkspaceFolder}/.devcontainer/zellij-data,target=/home/vscode/.local/share/zellij,type=bind"
  ]
}
```

### Git credentials not working

**Solution**: For GitHub Codespaces, use the built-in credential helper:

```nix
programs.git.extraConfig = {
  credential.helper = "store";
};
```

Or use SSH keys:
```bash
ssh-keygen -t ed25519 -C "your.email@example.com"
cat ~/.ssh/id_ed25519.pub  # Add to GitHub
```

---

## Performance Tips

### Faster Builds with Binary Cache

Add to `.devcontainer/devcontainer.json`:

```json
{
  "postCreateCommand": "echo 'substituters = https://cache.nixos.org https://nix-community.cachix.org' >> ~/.config/nix/nix.conf && echo 'trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=' >> ~/.config/nix/nix.conf"
}
```

### Reduce Container Size

Use a multi-stage build or only install what you need:

```nix
programs.terminal-dev-environment = {
  enable = true;
  tools = {
    git = true;
    editor = true;
    shell = true;
    multiplexer = false;  # Skip if you don't need it
    terminal = false;     # Not needed in containers
  };
};
```

### Persistent Nix Store

Mount Nix store to avoid rebuilding on container restart:

```json
{
  "mounts": [
    "source=keystone-nix-store,target=/nix,type=volume"
  ]
}
```

---

## FAQ

### Q: Can I use this with Docker Compose?

**A**: Yes! Add a devcontainer service:

```yaml
version: '3.8'
services:
  devcontainer:
    image: nixos/nix:latest
    volumes:
      - .:/workspace
      - nix-store:/nix
    working_dir: /workspace
    command: sleep infinity

volumes:
  nix-store:
```

### Q: How do I update the terminal environment?

**A**: Rebuild home-manager configuration:

```bash
home-manager switch --flake ~/.config/home-manager
```

Or rebuild the entire devcontainer.

### Q: Can I use this locally (not in a container)?

**A**: Absolutely! Follow the same home-manager setup steps on your local Linux/macOS machine.

### Q: What's the difference between this and the desktop configuration?

**A**: The desktop configuration includes Hyprland, graphical applications, and GUI tools. The terminal environment is lightweight and focused on terminal-based development.

### Q: Is this compatible with tmux?

**A**: Yes, but Zellij is the recommended multiplexer. If you prefer tmux, disable Zellij:

```nix
programs.terminal-dev-environment.tools.multiplexer = false;
```

### Q: Can I use this with non-Nix projects?

**A**: Yes! The terminal environment is project-agnostic. Use it with any language or framework.

---

## Real-World Example

Complete `.devcontainer` setup for a TypeScript project:

```
my-project/
├── .devcontainer/
│   ├── devcontainer.json
│   └── setup.sh
├── flake.nix                    # Terminal environment config
├── src/
└── package.json
```

**devcontainer.json**:
```json
{
  "name": "TypeScript Project with Keystone Terminal",
  "image": "nixos/nix:latest",
  "postCreateCommand": "bash .devcontainer/setup.sh",
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh",
        "editor.formatOnSave": true
      },
      "extensions": [
        "jnoortheen.nix-ide",
        "dbaeumer.vscode-eslint"
      ]
    }
  },
  "forwardPorts": [3000, 5173],
  "remoteUser": "nixos"
}
```

**flake.nix**:
```nix
{
  description = "TypeScript project with Keystone terminal environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    keystone.url = "github:ncrmro/keystone";
  };

  outputs = { nixpkgs, home-manager, keystone, ... }: {
    homeConfigurations.devuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        keystone.homeManagerModules.terminalDevEnvironment
        {
          home.username = "devuser";
          home.homeDirectory = "/home/devuser";
          home.stateVersion = "25.05";

          programs.terminal-dev-environment = {
            enable = true;

            extraPackages = with nixpkgs.legacyPackages.x86_64-linux; [
              nodejs_22
              nodePackages.typescript
              nodePackages.typescript-language-server
              nodePackages.eslint
              nodePackages.prettier
            ];
          };

          programs.git = {
            userName = "Your Name";
            userEmail = "your.email@example.com";
          };

          # Add TypeScript LSP to Helix
          programs.helix.languages.language = [
            {
              name = "typescript";
              language-servers = [ "typescript-language-server" ];
              auto-format = true;
              formatter = {
                command = "prettier";
                args = [ "--parser" "typescript" ];
              };
            }
          ];
        }
      ];
    };
  };
}
```

**.devcontainer/setup.sh**:
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up development environment..."

# Enable Nix flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Build and activate terminal environment
nix build .#homeConfigurations.devuser.activationPackage
./result/activate

# Install Node dependencies
if [ -f "package.json" ]; then
  npm install
fi

echo "✅ Setup complete! Run 'exec zsh' to reload your shell."
```

---

## Next Steps

1. **Choose a setup method** based on your needs (NixOS container, Home-Manager, or Nix profile)
2. **Customize the configuration** with your preferred tools and settings
3. **Push to your repository** and open in Codespaces/devcontainer
4. **Start developing** with a fully-configured terminal environment!

## Resources

- **Keystone Repository**: https://github.com/ncrmro/keystone
- **Detailed Terminal Environment Docs**: [docs/modules/terminal-dev-environment.md](./modules/terminal-dev-environment.md)
- **Helix Documentation**: https://docs.helix-editor.com/
- **Zellij Documentation**: https://zellij.dev/documentation/
- **Home-Manager Manual**: https://nix-community.github.io/home-manager/

---

## Contributing

Found an issue or have a suggestion? Please open an issue on the [Keystone repository](https://github.com/ncrmro/keystone/issues).

---

**Happy coding! 🚀**
