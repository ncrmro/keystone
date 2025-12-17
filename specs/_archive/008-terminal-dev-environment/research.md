# Research: Terminal Development Environment Module

**Date**: 2025-11-05
**Status**: Complete

## Overview

This document captures research findings for implementing a home-manager module that provides an opinionated terminal development environment for Keystone users.

---

## 1. Ghostty Terminal Emulator Availability

### Decision: Use Ghostty as the terminal emulator

**Rationale:**
- Ghostty is available in nixpkgs 25.05 stable (the target version for Keystone)
- Package was backported to NixOS 24.11 stable in January 2025
- Home-Manager includes native `programs.ghostty` support with shell integrations
- Modern, GPU-accelerated terminal with excellent Wayland support
- Aligns with Keystone's goal of providing modern infrastructure tools

**Package Details:**
- Package name: `pkgs.ghostty`
- Home-Manager module: `programs.ghostty`
- Configuration location: `$XDG_CONFIG_HOME/ghostty/config`
- Shell integration options: `enableBashIntegration`, `enableZshIntegration`, `enableFishIntegration`

**Alternatives Considered:**
1. **Kitty** - Already default for Hyprland in Keystone's client module, proven stability
2. **Foot** - Lightweight Wayland-native option, minimal resource usage
3. **Alacritty** - Cross-platform, GPU-accelerated, simple configuration

**Conclusion:** Ghostty provides the best balance of modern features, nixpkgs availability, and home-manager integration. Users can override with their preferred terminal if needed.

---

## 2. Home-Manager Module Architecture

### Decision: Use modular structure with individual tool files

**Rationale:**
- Follows official home-manager module patterns
- Separates concerns for maintainability (one file per tool)
- Allows individual tools to be updated independently
- Matches Keystone's existing module structure (e.g., `modules/client/`)

**Module Structure Pattern:**
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
in
{
  meta.maintainers = [ ];

  imports = [
    ./git.nix
    ./helix.nix
    ./zsh.nix
    ./zellij.nix
    ./lazygit.nix
    ./ghostty.nix
  ];

  options.programs.terminal-dev-environment = {
    enable = lib.mkEnableOption "terminal development environment";
    # Tool-specific options in respective files
  };

  config = lib.mkIf cfg.enable {
    # Orchestration logic here
  };
}
```

**Key Patterns Discovered:**
1. **Enable Options**: Use `lib.mkEnableOption` for boolean toggles
2. **Package Options**: Use `lib.mkPackageOption pkgs "packageName" { }` for consistency
3. **Settings**: Use `pkgs.formats.toml/yaml/json` with `freeformType` for flexible configuration
4. **Overrideability**: Use `lib.mkDefault` for all default values to allow user overrides
5. **Conditionals**: Use `lib.mkIf` and `lib.mkMerge` for composition
6. **Type Safety**: Always specify explicit types for all options

---

## 3. Configuration Composition Strategy

### Decision: Provide sensible defaults with individual tool enable toggles

**Rationale:**
- Users want "it just works" out of the box
- Advanced users need granular control to disable specific tools
- Follows NixOS principle of composability

**Recommended Option Structure:**
```nix
options.programs.terminal-dev-environment = {
  enable = lib.mkEnableOption "terminal development environment";

  # Individual tool toggles (all default to true when parent is enabled)
  tools = {
    git = lib.mkEnableOption "Git and Git UI tools" // { default = true; };
    editor = lib.mkEnableOption "Helix text editor" // { default = true; };
    shell = lib.mkEnableOption "Zsh shell with utilities" // { default = true; };
    multiplexer = lib.mkEnableOption "Zellij terminal multiplexer" // { default = true; };
    terminal = lib.mkEnableOption "Ghostty terminal emulator" // { default = true; };
  };

  # Escape hatch for additional packages
  extraPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Additional packages to include in the environment";
  };
};
```

**Implementation Pattern:**
```nix
config = lib.mkIf cfg.enable (lib.mkMerge [
  # Always included
  { home.packages = cfg.extraPackages; }

  # Conditionally included based on tool toggles
  (lib.mkIf cfg.tools.git { programs.git.enable = true; })
  (lib.mkIf cfg.tools.editor { programs.helix.enable = true; })
  # ... etc
]);
```

**Alternatives Considered:**
1. **All-or-nothing approach** - Rejected: Too opinionated, no flexibility
2. **Individual enable per package** - Rejected: Too granular, complex for simple cases
3. **Category-based toggles** - Selected: Right balance of convenience and control

---

## 4. Language Server Configuration for Helix

### Decision: Include essential language servers by default

**Rationale:**
- Helix is useless without language servers for modern development
- Essential LSPs (Nix, Bash, YAML, JSON, Dockerfile) are small and widely useful
- Language-specific LSPs (TypeScript, Python, Rust, etc.) should be opt-in

**Default Language Servers:**
- `nixfmt` - Nix formatting
- `bash-language-server` - Shell script support
- `yaml-language-server` - YAML configuration files
- `dockerfile-language-server-nodejs` - Docker support
- `vscode-langservers-extracted` - JSON, CSS, HTML support
- `marksman` - Markdown support (documentation)

**Configuration Pattern:**
```nix
home.packages = with pkgs; [
  bash-language-server
  yaml-language-server
  dockerfile-language-server-nodejs
  vscode-langservers-extracted
  marksman
];

programs.helix = {
  enable = true;
  settings = {
    theme = lib.mkDefault "default";
    editor = {
      line-number = "relative";
      mouse = true;
      cursor-shape = {
        insert = "bar";
        normal = "block";
        select = "underline";
      };
    };
  };
  languages = {
    language-server = {
      # LSP configurations
    };
    language = [
      # Language-specific settings
    ];
  };
};
```

**Alternatives Considered:**
1. **No LSPs by default** - Rejected: Editor would be nearly non-functional
2. **All possible LSPs** - Rejected: Bloats closure size, includes unused dependencies
3. **Essential + opt-in extras** - Selected: Best balance

---

## 5. Shell Integration Strategy

### Decision: Use oh-my-zsh with starship, zoxide, and direnv

**Rationale:**
- oh-my-zsh provides familiar plugin ecosystem and git integration
- starship gives modern, fast prompt with useful context
- zoxide enables smart directory navigation
- direnv automatically loads project environments
- These tools work together without conflicts

**Configuration Pattern:**
```nix
programs.zsh = {
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;

  shellAliases = lib.mkDefault {
    # Common aliases
    l = "eza -1l";
    ls = "eza -1l";
    grep = "rg";
    g = "git";
    lg = "lazygit";
    hx = "helix";
  };

  oh-my-zsh = {
    enable = true;
    plugins = [ "git" "colored-man-pages" ];
    theme = "robbyrussell";
  };
};

programs.starship.enable = lib.mkDefault true;

programs.zoxide = {
  enable = lib.mkDefault true;
  enableZshIntegration = true;
};

programs.direnv = {
  enable = lib.mkDefault true;
  enableZshIntegration = true;
  nix-direnv.enable = true;
};
```

**Benefits:**
- Single `enable = true` activates complete shell environment
- All integrations configured automatically
- Users can override individual settings with standard home-manager options

---

## 6. Git Configuration Decisions

### Decision: Provide SSH signing support, let users configure identity

**Rationale:**
- Git identity (name, email) is user-specific and should not have defaults
- SSH signing is a security best practice but requires user's SSH key
- Git aliases for common operations improve productivity
- LFS support is lightweight and enables large file handling

**Configuration Pattern:**
```nix
programs.git = {
  enable = true;
  lfs.enable = lib.mkDefault true;

  aliases = lib.mkDefault {
    s = "switch";
    f = "fetch";
    p = "pull";
    b = "branch";
    st = "status -sb";
    co = "checkout";
    c = "commit";
  };

  extraConfig = lib.mkDefault {
    push.autoSetupRemote = true;
    init.defaultBranch = "main";
    # Note: Users configure signing separately:
    # gpg.format = "ssh";
    # commit.gpgsign = true;
    # user.signingkey = "~/.ssh/id_ed25519";
  };
};

programs.lazygit.enable = lib.mkDefault true;
```

**User Responsibility:**
- Setting `programs.git.userName` and `programs.git.userEmail`
- Optionally enabling SSH signing with their own keys
- Module documentation will provide example configuration

---

## 7. Testing Strategy

### Decision: Use Keystone's existing VM testing infrastructure

**Rationale:**
- Keystone already has `bin/virtual-machine` for testing
- Can create test configuration that enables the module
- Allows verification of shell environment and tool integration
- No new testing infrastructure needed

**Testing Approach:**
1. **Build-time validation**: `nix build .#nixosConfigurations.test-config` checks syntax and evaluation
2. **bin/test-home-manager script**: Self-contained automated test script following bin/test-deployment pattern
   - Python script with colored output and checks array
   - SSHs to VM as testuser (not root)
   - Installs home-manager for testuser
   - Copies testuser home-manager config with terminal-dev-environment module
   - Runs `home-manager switch` as testuser
   - Performs comprehensive verification checks
   - Returns exit code 0 on success, 1 on failure (can fail outer test-deployment)
3. **bin/test-deployment integration**: Calls bin/test-home-manager as new verification step after ZFS user checks
4. **Manual integration testing**: Can run `./bin/test-home-manager` independently for debugging

**Test Configuration Example:**
```nix
# vms/test-server/home-manager/home.nix
# Used by bin/test-home-manager for automated testing
{ config, pkgs, ... }:
{
  imports = [ /home/ncrmro/code/ncrmro/keystone/home-manager/modules/terminal-dev-environment ];

  programs.terminal-dev-environment.enable = true;

  programs.git = {
    userName = "Test User";
    userEmail = "testuser@keystone-test-vm";
  };
}
```

**bin/test-home-manager Script Structure:**
```python
#!/usr/bin/env python3
"""Test terminal-dev-environment module via home-manager as testuser"""

# Following bin/test-deployment pattern:
# - Colored output (RED, GREEN, YELLOW, BLUE, CYAN, NC)
# - ssh_testuser() helper for SSH commands
# - Checks array: [(name, lambda), ...]
# - Track passed/failed counts
# - Return exit code 0/1

checks = [
    ("Home-manager installed", verify_hm_installed),
    ("All tools in PATH", verify_tools_in_path),
    ("Zsh is default shell", verify_zsh_default),
    ("Helix with LSP works", verify_helix_lsp),
    ("Lazygit available", verify_lazygit),
    ("Zellij with theme", verify_zellij_theme),
    ("Shell aliases work", verify_aliases),
    ("Starship prompt active", verify_starship),
    ("Zoxide navigation", verify_zoxide),
]
```

**bin/test-deployment Integration:**
```python
# In main() after verify_zfs_user_permissions()
current_step += 1
print_step(current_step, total_steps, "Testing terminal development environment")

result = run_command("./bin/test-home-manager", check=False, timeout=300)
if not result:
    print_error("Terminal dev environment test failed")
    print_info(f"You can manually test: ./bin/test-home-manager")
    return 1
```

---

## 8. Integration with Keystone Client Module

### Decision: Optional integration, not required dependency

**Rationale:**
- Terminal dev environment should work standalone (e.g., on servers)
- When used with client module, provides enhanced desktop integration
- Follows Keystone's modular composability principle

**Integration Points:**
- Ghostty can be set as default terminal for Hyprland via `$TERMINAL` environment variable
- Module works independently of desktop environment
- No hard dependency on client module

**Example Integrated Configuration:**
```nix
{
  imports = [
    keystone.nixosModules.client
    keystone.homeManagerModules.terminal-dev-environment
  ];

  keystone.client.enable = true;
  programs.terminal-dev-environment.enable = true;

  # Ghostty will be available in Hyprland
  home.sessionVariables.TERMINAL = "ghostty";
}
```

---

## Summary of Key Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| Terminal Emulator | Ghostty | Available in nixpkgs 25.05, modern features, native HM support |
| Module Structure | Modular with per-tool files | Maintainability, follows Keystone patterns |
| Default Behavior | Sensible defaults, all tools enabled | "Just works" out of box |
| Customization | Individual tool toggles + overrides | Granular control when needed |
| Language Servers | Essential LSPs included | Helix functional for common tasks |
| Shell Setup | Zsh + oh-my-zsh + starship + zoxide | Modern, productive shell environment |
| Git Identity | User-configured | Respects user sovereignty |
| Testing | Keystone VM infrastructure | Reuses existing tooling |
| Desktop Integration | Optional, not required | Works standalone or with client module |

---

## Next Steps (Phase 1)

1. Create data-model.md documenting module options structure
2. Generate contracts (not applicable - no API endpoints)
3. Create quickstart.md with usage examples
4. Update agent context with new technology choices
