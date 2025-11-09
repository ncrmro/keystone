#!/usr/bin/env python3
"""
Run nix flake check on Stop event, but only if Nix files were modified.
Uses git to detect changed files.

Only runs nix flake check if .nix files actually changed - not on every stop.
"""
import sys
import os
import subprocess


def get_workspace_dir():
    """Get workspace directory, handling worktree context."""
    workspace = os.environ.get('CLAUDE_WORKSPACE_DIR')
    return workspace if workspace else os.getcwd()


def main():
    try:
        # Change to workspace directory
        workspace = get_workspace_dir()
        os.chdir(workspace)

        # Get list of modified files using git
        result = subprocess.run(
            ['git', 'diff', '--name-only', 'HEAD'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            # If git command fails, skip flake check
            print("⚠ Could not check git status, skipping nix flake check", file=sys.stderr)
            sys.exit(0)

        # Check if any Nix files were modified
        modified_files = result.stdout.strip().split('\n')
        has_nix_files = any(
            f.endswith('.nix')
            for f in modified_files
            if f  # Skip empty strings
        )

        if not has_nix_files:
            # No Nix files modified, skip flake check
            sys.exit(0)

        # Run nix flake check
        print("Nix files modified, running nix flake check...")
        result = subprocess.run(
            ['nix', 'flake', 'check'],
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes max
        )

        if result.returncode == 0:
            print("✓ nix flake check passed")
            sys.exit(0)  # Exit 0: Success, don't show to agent
        else:
            # Exit 2: Flake check failed - show to agent so they can fix issues
            print("nix flake check failed:", file=sys.stderr)
            print(result.stdout, file=sys.stderr)
            if result.stderr:
                print(result.stderr, file=sys.stderr)
            sys.exit(2)

    except subprocess.TimeoutExpired:
        print("⚠ nix flake check timed out after 5 minutes", file=sys.stderr)
        sys.exit(2)  # Exit 2: Show timeout to agent
    except Exception as e:
        print(f"Error in nix-flake-check-on-stop hook: {e}", file=sys.stderr)
        sys.exit(2)  # Exit 2: Show error to agent


if __name__ == '__main__':
    main()
