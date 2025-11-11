# Keystone Devcontainer

This directory contains the devcontainer configuration for the Keystone project.

## Quick Start

1. Open this repository in VS Code with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. When prompted, click "Reopen in Container"
3. Wait for the container to build (first time may take several minutes)
4. Once ready, you'll have access to the full Keystone development environment

## What's Inside

The devcontainer provides:
- **Nix** with flakes enabled
- **Docker-in-Docker** for container workflows
- **SSH server** for remote access
- **All tools** from the Keystone flake devShell
- **VS Code extensions** for Nix development

## Hardware Requirements

- **CPUs**: 8 cores recommended
- **Memory**: 32GB RAM recommended

## Files

- `devcontainer.json` - Main configuration file

## Documentation

See [docs/devcontainer.md](../docs/devcontainer.md) for:
- Detailed setup instructions
- SSH access methods
- Troubleshooting guide
- Tool usage examples

## Customization

To add tools or modify the environment:
1. Edit the `devShells` section in `../flake.nix`
2. Rebuild the container: "Dev Containers: Rebuild Container"

To change VS Code settings:
1. Edit the `customizations.vscode` section in `devcontainer.json`
2. Reload the window or rebuild the container
