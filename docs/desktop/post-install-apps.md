# Post-install applications

After a fresh Keystone laptop install, the desktop ships core desktop utilities
but no web browser, IDE, or password manager. This page documents the supported
post-install paths for the most common tools.

## Where to add packages

| Where | Scope | Installed via | Example |
|-------|-------|---------------|---------|
| `shared.desktopUserModules` | Desktop hosts only | Home Manager (per-user) | browser, Obsidian, VS Code, Bitwarden |
| `shared.userModules` | Every host | Home Manager (per-user) | fd, ripgrep |
| `shared.systemModules` | Every host | NixOS (OS-wide) | btop, 1Password NixOS module |
| `hosts/<name>/configuration.nix` | One host | NixOS (OS-wide) | GPU-specific tools |

Desktop user modules apply to laptop and workstation hosts but not servers.
GUI apps belong in `desktopUserModules` — installed per-user via Home Manager,
not at the OS level.

## flake.nix example

```nix
keystone.lib.mkSystemFlake {
  admin = { /* ... */ };
  hostsRoot = ./hosts;

  shared = {
    # Installed in your user profile via Home Manager on every host.
    userModules = [
      ({ pkgs, ... }: { home.packages = with pkgs; [ fd ]; })
    ];

    # Installed OS-wide via NixOS on every host.
    systemModules = [
      ({ pkgs, ... }: { environment.systemPackages = with pkgs; [ btop ]; })
    ];

    # Installed in your user profile via Home Manager on desktop hosts only.
    # As the list grows, extract to a file:
    #   desktopUserModules = [ (import ./modules/home/desktop-apps.nix) ];
    desktopUserModules = [
      (
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            # --- Browser (pick one, then set keystone.desktop.browser below) ---
            # chromium              # Chromium (open-source Chrome base)
            # google-chrome-stable  # Google Chrome
            # firefox               # Firefox

            # --- Editors and IDEs ---
            # vscode                # VS Code (supports Claude Code extension)
            # obsidian              # Knowledge management (vaults at ~/notes/)

            # --- Password managers ---
            # bitwarden-desktop     # Bitwarden GUI
            # bitwarden-cli         # bw CLI for scripting and Walker integration

            # --- AI coding ---
            # pkgs.keystone.codex   # Antigravity IDE (codex CLI)
          ];
        }
      )
    ];
  };

  # Default browser binding ($mod+B). Set to match the browser you added above
  # ("chromium", "google-chrome-stable", or "firefox").
  # keystone.desktop.browser = "chromium";

  hosts = {
    laptop = { kind = "laptop"; };          # gets desktopUserModules
    workstation = { kind = "workstation"; }; # gets desktopUserModules
    server-ocean = { kind = "server"; };     # does not
  };
}
```

## Finding packages

- [Packages](https://search.nixos.org/packages?channel=unstable) — attribute name for `home.packages` or `environment.systemPackages`
- [Options](https://search.nixos.org/options?channel=unstable) — NixOS module options like `programs._1password-gui.enable`

## Applying changes

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```

---

## Browser

No browser ships by default. The `$mod+B` keybinding launches `$browser`, which
is set by `keystone.desktop.browser`. Until you add a browser and set the
option, the keybinding does nothing.

**Step 1** — add the package to `desktopUserModules`:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    chromium              # or: google-chrome-stable, firefox
  ];
}
```

**Step 2** — set the browser option in `flake.nix` or a shared module:

```nix
# Set to match the package you added: "chromium", "google-chrome-stable", or "firefox"
keystone.desktop.browser = "chromium";
```

**Step 3** — apply:

```bash
ks build && ks switch
```

### Google Chrome vs. Chromium

`chromium` is the open-source build available in nixpkgs. `google-chrome-stable`
is the proprietary Google build, available via the `browser-previews` flake
input that Keystone already includes. Both support Wayland natively via
`--ozone-platform=wayland`.

---

## VS Code

Add to `desktopUserModules`:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [ vscode ];
}
```

Apply with `ks build && ks switch`. VS Code is the recommended host for the
[Claude Code extension](https://marketplace.visualstudio.com/items?itemName=anthropics.claude-code).

To manage extensions declaratively:

```nix
{ pkgs, ... }: {
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      # Add extension attributes here
    ];
  };
}
```

---

## Obsidian

Add to `desktopUserModules`:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [ obsidian ];
}
```

Obsidian vaults integrate naturally with Keystone's notes module at `~/notes/`.
After install, open Obsidian and point it at the `~/notes` directory. Note that
Keystone manages notes via [zk](https://github.com/zk-org/zk) (plain Markdown),
so Obsidian and zk share the same files without conflict.

---

## Antigravity IDE (codex)

Codex is the AI coding CLI shipped as `pkgs.keystone.codex` in the Keystone
overlay. It is a terminal-first coding agent comparable to Claude Code.

Add to `desktopUserModules` (GUI/desktop installs) or `userModules` (all hosts):

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.keystone.codex ];
}
```

Codex reads the `OPENAI_API_KEY` environment variable. Set it in your shell
profile or via a secrets manager before running `codex`.

---

## Text editors

**Helix** ships by default via the Keystone terminal module with automatic theme
integration. It is available as `hx` immediately after install.

For additional editors:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    # zed-editor      # Zed — fast Rust-based editor with AI built in
    # neovim          # Neovim
    # emacs           # Emacs
  ];
}
```

---

## 1Password

1Password requires both the GUI app and the `op` CLI. The GUI needs a
NixOS-level module for polkit and SSH agent bridge integration; the CLI can
be added as either a system package or a home-manager package.

**In `shared.systemModules`** (or per-host `configuration.nix`):

```nix
{ ... }: {
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "your-username" ];  # replace with your login name
  };
  programs._1password.enable = true;  # installs the op CLI system-wide
}
```

Apply with `ks build && ks switch`. Verify:

```bash
which 1password   # GUI
op --version      # CLI
op signin         # sign in to your account
```

### 1Password SSH agent integration

1Password can serve as the SSH agent. In the app: **Settings → Developer → Use
the SSH agent**. Then point your SSH config at the 1Password socket:

```
# ~/.ssh/config
Host *
  IdentityAgent ~/.1password/agent.sock
```

---

## Bitwarden

Add to `desktopUserModules`:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    bitwarden-desktop  # GUI vault
    bitwarden-cli      # bw CLI for scripting and Walker integration
  ];
}
```

Sign in via CLI after install:

```bash
bw login
bw unlock           # outputs a session token
export BW_SESSION="<token from unlock>"
bw list items       # verify access
```

---

## Walker / Elephant + password manager integration

Walker and Elephant can surface password manager entries in the Keystone menu
system (`$mod+Escape`).

### 1Password via `op` CLI

The Keystone secrets menu (`keystone-secrets-menu`) detects `op` at runtime when
it is on `PATH` and a session is active. No extra configuration is required.

To keep `op` signed in across sessions, enable the 1Password SSH agent and add
the following to your shell profile so the session token is sourced
automatically:

```bash
# ~/.zshrc or ~/.bashrc
eval "$(op signin)"
```

Retrieve individual fields from the CLI:

```bash
op item get "My Login" --fields password
op run -- my-script  # inject secrets as environment variables
```

### Bitwarden via `rbw` (recommended for scripting)

[rbw](https://github.com/doy/rbw) is an unofficial Bitwarden client designed for
non-interactive CLI use. It keeps a local encrypted cache that can be queried
without a full sign-in:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [ rbw ];
  programs.rbw = {
    enable = true;
    settings = {
      email = "you@example.com";
      lock_timeout = 300;
    };
  };
}
```

After `ks switch`:

```bash
rbw register     # first-time setup
rbw sync         # pull vault entries
rbw get "My Login"   # retrieve by name
```

Walker/Elephant menus that support a secrets backend will use `rbw get` if `rbw`
is on `PATH`. Run `rbw unlock` once per session to allow background access.

---

## Adding SSH keys for remote access

To allow an operator to SSH into a freshly installed laptop (for example, for
rc validation debugging), add their public key to the `admin.sshKeys` list in
`flake.nix`:

```nix
keystone.lib.mkSystemFlake {
  admin = {
    username = "your-username";
    sshKeys = [
      "ssh-ed25519 AAAA... operator@example.com"  # add operator key here
    ];
  };
  ...
}
```

Apply the change with `ks switch` on the laptop, or push to the config repo and
run `ks update`. After the switch, the operator can connect as the admin user
over the Tailscale hostname or LAN IP:

```bash
# Over Tailscale (if configured)
ssh your-username@laptop.your-tailnet.ts.net

# Over LAN — find the IP first
ip addr show
ssh your-username@192.168.x.x
```

The `sshKeys` list is the canonical place for all authorized public keys on this
machine.

---

## Notes

- OS-level desktop settings (such as `programs._1password-gui.enable`) go in
  per-host `configuration.nix` or `shared.systemModules` to apply everywhere.
