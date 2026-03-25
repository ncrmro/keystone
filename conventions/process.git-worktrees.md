# Convention: Git worktrees (process.git-worktrees)

This convention standardizes how humans and agents create and use git
worktrees for active implementation work.

## Checkout roots

1. Keystone-managed repositories MUST keep their main checkout at
   `~/.keystone/repos/{owner}/{repo}/`.
2. Non-keystone project repositories MUST keep their main checkout at
   `$HOME/code/{owner}/{repo}/`.
3. The main checkout MUST remain on the default branch and serve as the anchor
   for fetch, branch creation, and worktree management.
4. Home Manager activation SHOULD ensure that `$HOME/code/` and
   `$HOME/.worktrees/` exist before worktree-aware tooling runs.
5. Tooling SHOULD prefer the exported `CODE_DIR`, `WORKTREE_DIR`, and
   `NOTES_DIR` environment variables when it needs to discover workspace roots.

## Worktree layout

6. Implementation work MUST happen in git worktrees rooted at
   `$HOME/.worktrees/{owner}/{repo}/{branch}/`.
7. Worktrees MUST live outside the main checkout so repo-local tooling, search,
   and indexing do not need to be worktree-aware.
8. The worktree directory name MUST match the git branch name exactly.
9. Branch names MUST follow the existing version-control naming conventions.

## Creation and lifecycle

10. Worktrees MUST be created from the main checkout after fetching the latest
   remote state.
11. If the branch does not exist locally, the branch SHOULD be created from the
   appropriate base branch before adding the worktree.
12. Reusing an existing worktree for the same branch SHOULD be preferred over
    creating duplicates.
13. After a branch is merged or abandoned, the external worktree SHOULD be
    removed.

## Project session integration

14. Project tooling that launches a repo-scoped session, such as `pz` or
    `agentctl`, SHOULD resolve the repo root first and then derive the worktree
    path as `$HOME/.worktrees/{owner}/{repo}/{branch}/`.
15. When a requested worktree does not exist, tooling MAY create it if the
    command contract allows creation. Otherwise it MUST fail with a clear error.
16. Repo-scoped sessions MUST expose both the repo root and the worktree path
    in their environment when a worktree is active.

## Environment handling

17. Tools that create a new worktree SHOULD run `direnv allow` in the worktree
    when the repo uses direnv-managed environments.
18. Tooling MUST set the session working directory to the worktree path when a
    worktree is active, not the main checkout.

## Golden example

```bash
cd "$HOME/code/acme/api"
git fetch origin
git branch feat/add-search-endpoint origin/main
git worktree add "$HOME/.worktrees/acme/api/feat/add-search-endpoint" feat/add-search-endpoint
cd "$HOME/.worktrees/acme/api/feat/add-search-endpoint"
direnv allow
```
