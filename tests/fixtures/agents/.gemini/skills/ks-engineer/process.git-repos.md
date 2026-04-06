# Convention: Git repos (process.git-repos)

This convention standardizes where repositories are cloned depending on their
relationship to the Keystone platform, and how git worktrees are created and
used for active implementation work.

## Repository roots

1. Keystone-managed repositories (those defining or operating this machine's
   infrastructure) MUST keep their main checkout at
   `~/.keystone/repos/{owner}/{repo}/`.
2. `~/.keystone/repos/` MUST only contain repositories that are part of the
   Keystone system itself (e.g., `ncrmro/keystone`, `ncrmro/nixos-config`,
   `Unsupervisedcom/deepwork`). It MUST NOT be used for general project work.
3. All other (non-Keystone) repositories MUST keep their main checkout at
   `$HOME/repos/{owner}/{repo}/`.
4. The main checkout MUST remain on the default branch and serve as the anchor
   for fetch, branch creation, and worktree management.
5. Home Manager activation SHOULD ensure that `$HOME/repos/` and
   `$HOME/.worktrees/` exist before worktree-aware tooling runs.
6. Tooling SHOULD prefer the exported `CODE_DIR`, `WORKTREE_DIR`, and
   `NOTES_DIR` environment variables when it needs to discover workspace roots.

## Worktree layout

7. Implementation work MUST happen in git worktrees rooted at
   `$HOME/.worktrees/{owner}/{repo}/{branch}/`.
8. Worktrees MUST live outside the main checkout directory. Placing worktrees
   inside the repo causes problems with tools that index or glob the directory
   tree (e.g., language servers, file watchers, IDE indexers), because those
   tools are not worktree-aware and treat each worktree as part of the main
   project tree.
9. The worktree directory name MUST match the git branch name exactly.
10. Branch names MUST follow the existing version-control naming conventions.

## Creation and lifecycle

11. Worktrees MUST be created from the main checkout after fetching the latest
    remote state.
12. If the branch does not exist locally, the branch SHOULD be created from the
    appropriate base branch before adding the worktree.
13. Reusing an existing worktree for the same branch SHOULD be preferred over
    creating duplicates.
14. After a branch is merged or abandoned, the external worktree SHOULD be
    removed.

## Project session integration

15. Project tooling that launches a repo-scoped session, such as `pz` or
    `agentctl`, SHOULD resolve the repo root first and then derive the worktree
    path as `$HOME/.worktrees/{owner}/{repo}/{branch}/`.
16. When a requested worktree does not exist, tooling MAY create it if the
    command contract allows creation. Otherwise it MUST fail with a clear error.
17. Repo-scoped sessions MUST expose both the repo root and the worktree path
    in their environment when a worktree is active.

## Environment handling

18. Tools that create a new worktree SHOULD run `direnv allow` in the worktree
    when the repo uses direnv-managed environments.
19. Tooling MUST set the session working directory to the worktree path when a
    worktree is active, not the main checkout.

## Golden example

```bash
# Clone a non-Keystone project repo into the standard location
gh repo clone acme/api "$HOME/repos/acme/api"

# Create a worktree for feature work outside the repo (avoids indexing issues)
cd "$HOME/repos/acme/api"
git fetch origin
git branch feat/add-search-endpoint origin/main
git worktree add "$HOME/.worktrees/acme/api/feat/add-search-endpoint" feat/add-search-endpoint
cd "$HOME/.worktrees/acme/api/feat/add-search-endpoint"
direnv allow
```