# Devcontainer Development Environment

This repository includes a devcontainer configuration that provides a complete development environment using the Nix flake defined in this repository.

## Quick Start

### Using VS Code / Codespaces

1. **VS Code Desktop**:
   - Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
   - Open the repository in VS Code
   - When prompted, click "Reopen in Container" or run the command `Dev Containers: Reopen in Container`

2. **GitHub Codespaces**:
   - Open the repository on GitHub
   - Click the "Code" button and select "Codespaces"
   - Click "Create codespace on main" (or your branch)

### Using Other IDEs

The devcontainer can be used with any IDE that supports the devcontainer specification, including:
- JetBrains IDEs with the [Dev Containers plugin](https://plugins.jetbrains.com/plugin/21962-dev-containers)
- CLI tools like [devcontainer CLI](https://github.com/devcontainers/cli)

## What's Included

The devcontainer provides all tools from the Keystone terminal development environment:

### Version Control
- **Git** with Git LFS support
- **lazygit** - Terminal UI for Git

### Editor
- **Helix** - Modern modal text editor with LSP support

### Shell Environment
- **Zsh** with Oh My Zsh
- **Starship** - Cross-shell prompt
- **Zoxide** - Smarter cd command
- **direnv** - Environment variable management

### Terminal Tools
- **Zellij** - Terminal multiplexer
- **Ghostty** - Modern terminal emulator
- **zesh** - Zellij session manager with zoxide integration

### File Utilities
- **eza** - Modern replacement for ls
- **ripgrep** - Fast text search
- **fd** - Modern find alternative
- **bat** - Cat with syntax highlighting
- **tree** - Directory tree visualization

### Development Tools
- **nixfmt-rfc-style** - Nix code formatter
- **nil** - Nix Language Server
- **nixos-anywhere** - NixOS deployment tool
- **jq** / **yq** - JSON/YAML processors
- **htop** / **bottom** - System monitors

## SSH Access to Devcontainer

### Method 1: VS Code Remote-SSH (Recommended)

When running in a devcontainer, VS Code automatically sets up SSH access. The container's SSH port (22) is forwarded to your host machine.

1. **Find the forwarded port**:
   - In VS Code, open the "Ports" panel (View → Ports)
   - Look for port 22 - it will show the local forwarded port (e.g., `localhost:32768`)

2. **Connect via SSH**:
   ```bash
   # Use the forwarded port from the Ports panel
   ssh -p <FORWARDED_PORT> vscode@localhost
   ```

   Example:
   ```bash
   ssh -p 32768 vscode@localhost
   ```

3. **Set up SSH key authentication** (optional):
   ```bash
   # Copy your public key to the container
   # First, get a shell in the container via VS Code terminal, then:
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   
   # On your host machine:
   cat ~/.ssh/id_ed25519.pub | ssh -p <FORWARDED_PORT> vscode@localhost 'cat >> ~/.ssh/authorized_keys'
   
   # In the container:
   chmod 600 ~/.ssh/authorized_keys
   ```

### Method 2: GitHub Codespaces SSH

GitHub Codespaces provides direct SSH access:

1. **Install the GitHub CLI** (if not already installed):
   ```bash
   # macOS
   brew install gh
   
   # Linux
   # See: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
   ```

2. **Authenticate with GitHub**:
   ```bash
   gh auth login
   ```

3. **List your codespaces**:
   ```bash
   gh codespace list
   ```

4. **SSH into a codespace**:
   ```bash
   gh codespace ssh
   ```

   Or specify the codespace by name:
   ```bash
   gh codespace ssh -c <codespace-name>
   ```

5. **Port forwarding from codespace**:
   ```bash
   # Forward a port from the codespace to your local machine
   gh codespace ports forward 8080:8080 -c <codespace-name>
   ```

### Method 3: Docker Exec (Direct Container Access)

If you're running the devcontainer locally with Docker:

1. **Find the container ID**:
   ```bash
   docker ps | grep keystone
   ```

2. **Execute a shell in the container**:
   ```bash
   docker exec -it <container-id> /bin/sh
   ```

3. **Or start a Zsh shell directly**:
   ```bash
   docker exec -it <container-id> nix develop --command zsh
   ```

### Method 4: Enable SSH Server in Container (Advanced)

For a persistent SSH server in the container, you can modify the devcontainer:

1. **Add SSH server to the Dockerfile**:
   ```dockerfile
   # In .devcontainer/Dockerfile
   RUN nix-env -iA nixpkgs.openssh
   ```

2. **Update devcontainer.json**:
   ```json
   {
     "postCreateCommand": "sudo service ssh start",
     "forwardPorts": [22]
   }
   ```

3. **Configure SSH**:
   ```bash
   # In the container
   sudo mkdir -p /etc/ssh
   sudo ssh-keygen -A
   sudo service ssh start
   ```

## Using the Development Environment

Once connected (via VS Code terminal, SSH, or direct access):

1. **Enter the Nix development shell**:
   ```bash
   nix develop
   ```

2. **Or use specific tools directly**:
   ```bash
   # Edit files
   hx README.md
   
   # Git operations
   lg  # lazygit
   
   # Terminal multiplexer
   zellij
   
   # Or use the zesh session manager
   zesh
   ```

3. **Format Nix code**:
   ```bash
   nixfmt flake.nix
   ```

4. **Build ISO**:
   ```bash
   nix build .#iso
   ```

## Troubleshooting

### Container won't start
- Ensure Docker has enough resources (CPU, memory, disk space)
- Check Docker logs: `docker logs <container-id>`
- Try rebuilding: Dev Containers → Rebuild Container

### SSH connection refused
- Verify port forwarding in the Ports panel
- Check if the SSH server is running in the container
- Ensure firewall allows the forwarded port

### Nix commands fail
- The first build may take time to download packages
- Ensure internet connectivity in the container
- Check Nix configuration: `nix show-config`

### Performance issues
- The devcontainer uses a Docker volume for `/nix` for better performance
- On macOS, ensure you're using the latest Docker Desktop
- Consider increasing Docker resource limits

## Additional Resources

- [VS Code Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [GitHub Codespaces Documentation](https://docs.github.com/en/codespaces)
- [Devcontainer Specification](https://containers.dev/)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)
