## Nix Dev Shell

## Agent Project Standards

1. Agents MUST use Nix devshells (`flake.nix`) to manage dependencies for all technical projects.
2. Repositories SHOULD use `flake.nix` if the agent is the creator or primary maintainer.
3. If working in a third-party repository where the agent is NOT the primary maintainer, the agent SHOULD avoid committing Nix configuration files, instead using local or untracked Nix shells to manage their own toolchain.
4. If a project requires service orchestration (e.g., databases, caching), `process-compose` SHOULD be included in the devshell.
5. The use of `.envrc` with `direnv` is the standard method for auto-loading the environment.

## Shell Usage

For shell script authoring standards (strict mode, ShellCheck, Nix packaging), see `code.shell-scripts`.

4. All repos MUST use `flake.nix` with a dev shell providing project dependencies.
5. Commands that need project tools (Node, pnpm, cargo, etc.) MUST be run via `nix develop --command <cmd>`, from within an interactive `nix develop` session, or from a direnv-activated shell.
6. You MUST NOT install tools globally or use `npx` — always use the project's dev shell.
7. You MUST NOT run `npm install -g` or equivalent global installs.

## Direnv Integration

5. Repos that use `flake.nix` SHOULD include an `.envrc` file containing `use flake`.
6. Before using direnv in a repo, you MUST run `direnv allow` to authorize the `.envrc`.
7. The `.direnv/` directory MUST be listed in `.gitignore`.
8. Projects SHOULD use `nix-direnv` for cached shell evaluation to avoid slow reloads.
9. Direnv MAY be used as a substitute for manually running `nix develop` sessions.

## Playwright in Nix Dev Shells

10. You MUST NEVER run `playwright install` or `npx playwright install`.
11. Nix flake dev shells provide browser binaries via `playwright-driver.browsers`. The shell hook sets `PLAYWRIGHT_BROWSERS_PATH` to the Nix store path.
12. The npm `@playwright/test` version MUST exactly match the Nix `playwright-driver` version.
13. To align versions, you MUST check the Nix version with `nix eval --raw nixpkgs#playwright-driver.version` and pin `@playwright/test` to that exact version.

## Adding Packages

14. If a task requires a CLI tool that is not available, it MUST be added to the devshell rather than marking the task as blocked.
15. To add a package: edit `flake.nix`, add the package to `devShells.default.buildInputs`, run `direnv allow`, and verify with `which <tool>`.
16. Package names MUST use `pkgs.<name>` — search with `nix search nixpkgs <name>` if unsure.
17. `nix flake lock --update-input nixpkgs` SHOULD only be run if the package is not found in the current lockfile.
18. Additions MUST be documented in the commit message.

## Flake Conventions

19. Dev shells SHOULD provide all build and test dependencies — no manual setup steps.
20. Shell hooks MAY set environment variables (e.g., `PLAYWRIGHT_BROWSERS_PATH`, `DATABASE_URL`).
21. Changes to `flake.nix` MUST be tested with `nix develop --command true` to verify the shell builds.

## Nix-Managed Configs

22. Config files in `/nix/store/` or symlinked from it MUST NOT be edited directly. For module authors managing runtime-writable configs, see `tool.nix` rules 17-21.
23. Changes to Nix-managed tools (e.g., himalaya) MUST be made via home-manager configuration updates.