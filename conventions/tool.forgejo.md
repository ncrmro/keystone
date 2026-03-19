
## Forgejo

## Repository Access

1. Repositories MUST be cloned via SSH, not HTTPS.
2. If a repo was cloned with HTTPS, the remote MUST be updated: `git remote set-url origin git@...`.
3. Full clones MUST be used — do NOT use `--depth 1` unless explicitly requested.

## Git Workflow

4. Branches MUST use semantic prefixes: `feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `test/`.
5. Commit messages MUST use semantic style (e.g., `feat: add API route`, `fix: null check`).
6. Force-pushing to `main` MUST NOT be done without explicit approval.

## CI/Actions

7. Forgejo Actions workflows SHOULD live in `.forgejo/workflows/`.
8. Workflow files MUST be YAML and follow the Forgejo Actions syntax (GitHub Actions compatible subset).
9. Secrets MUST be configured via the Forgejo web UI, not committed to the repo.

## CLI Tools

Two CLIs are available for Forgejo interaction:

- **`fj`** (forgejo-cli) — primary CLI for scripted/non-interactive operations (issues, PRs, releases, wiki)
- **`tea`** (Gitea tea) — used only for `tea api` raw API calls to cover entities `fj` lacks (milestones, labels, webhooks, PR reviews)

10. Agents MUST use `fj` as the primary CLI for issues, PRs, releases, and wiki.
11. Agents MUST use `tea api` for milestones, labels, webhooks, and any entity `fj` does not support.
12. Agents MUST NOT use `tea` interactive/TUI commands — only `tea api` is non-interactive and agent-safe.

### Common Flags

`fj` commands require the host flag at the top level. Repo context varies by subcommand — some accept `-r`/`--repo` (owner/repo slug), others accept `-R`/`--remote` (local git remote name). When running inside a cloned repo, `fj` auto-detects the remote, so explicit flags are often unnecessary.

```
fj -H https://git.ncrmro.com <subcommand> [args]
```

`tea api` commands require the login flag and take the endpoint directly:

```
tea api --login forgejo [method] <endpoint> [fields]
```

`tea api` supports `{owner}` and `{repo}` placeholders in endpoints that auto-resolve from `-r`.

All examples below omit the `-H` host flag for brevity. Prepend it to every `fj` command.

## Authentication

13. keystone.os provisions `fj` and `tea` authentication automatically. Agents SHOULD NOT manually configure auth under normal circumstances.
14. Verify `fj` auth: `fj whoami`.
15. Verify `tea` auth: `tea api --login forgejo /user`.
16. If `tea` returns "token is required": create a token via the Forgejo API using basic auth with the vault password, then update the tea login config.

## Pull Request Workflow

17. PRs MUST be squash-merged.
18. PRs MUST have the repo owner assigned as reviewer. The reviewer is the `{owner}` from the repo slug `{owner}/{repo}`.
19. Draft PRs on Forgejo use a `WIP: ` title prefix (not a `--draft` flag).
20. PRs SHOULD reference the issue they resolve (e.g., `Closes #123`).

### Happy Path

1. **Create a branch** with a semantic prefix:
   ```bash
   git checkout -b feat/short-description
   ```

2. **Push and create the PR:**
   ```bash
   git push -u origin feat/short-description
   fj pr create "feat: short description" --head feat/short-description --base main --body "Closes #123"
   ```

3. **Request the repo owner as reviewer** (`fj` has no reviewer command; token is read from tea config since `fj auth list` only shows `user@host`):
   ```bash
   TOKEN=$(yq '.logins[] | select(.name == "forgejo") | .token' ~/.config/tea/config.yml)
   curl -s -X POST \
     -H "Authorization: token $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"reviewers":["{owner}"]}' \
     "https://git.ncrmro.com/api/v1/repos/{owner}/{repo}/pulls/{number}/requested_reviewers"
   ```

4. **Wait for approval.** Check status with:
   ```bash
   fj pr view {number}
   ```

5. **Squash merge** after approval:
   ```bash
   fj pr merge {number} --method squash --delete --title "feat: short description (#{number})"
   ```

## Issues (fj)

21. Issues SHOULD have descriptive titles and labels.

```bash
issue search [QUERY]                          # default: open
  # -l labels, -c creator, -a assignee, -s state (open|closed|all)
issue create "Title" --body "Description"
issue view <NUMBER>
issue comment <NUMBER> --body "Comment"
issue close <NUMBER>
issue edit <NUMBER> --title "New title"
```

## Releases (fj)

```bash
release create "v1.0.0" -T -b "Release notes"
  # -T: create tag, -a <FILE>: attach asset
release list
release view <NAME>
release edit <NAME>
release delete <NAME>
```

## Wiki (fj)

```bash
wiki contents
wiki view <PAGE>
wiki clone
```

## Advanced: tea api

### Milestones

```bash
tea api --login forgejo /repos/{owner}/{repo}/milestones                                    # list
tea api --login forgejo -X POST /repos/{owner}/{repo}/milestones -f title="v1.0"           # create (simple values only)
tea api --login forgejo -X PATCH /repos/{owner}/{repo}/milestones/{id} -f state="closed"   # update
tea api --login forgejo -X DELETE /repos/{owner}/{repo}/milestones/{id}                     # delete
```

**Note**: `tea api -f` breaks when values contain spaces. For milestones with spaces in title or description, use the curl fallback below.

### Labels

```bash
tea api --login forgejo /repos/{owner}/{repo}/labels                                        # list
tea api --login forgejo -X POST /repos/{owner}/{repo}/labels -f name="bug" -f color="#ee0701"
tea api --login forgejo -X DELETE /repos/{owner}/{repo}/labels/{id}
```

### PR Reviews

```bash
tea api --login forgejo /repos/{owner}/{repo}/pulls/{index}/reviews                         # list reviews
tea api --login forgejo -X POST /repos/{owner}/{repo}/pulls/{index}/reviews \
  -f body="LGTM" -f event="APPROVED"                                                       # submit review
```

### Curl Fallback

When `tea api -f` cannot handle the payload (spaces in values, JSON arrays, nested objects), use `curl` directly:

```bash
TOKEN=$(yq '.logins[] | select(.name == "forgejo") | .token' ~/.config/tea/config.yml)
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"My Milestone","description":"Has spaces and special chars"}' \
  "https://git.ncrmro.com/api/v1/repos/{owner}/{repo}/milestones"
```

### Raw API Fallback

22. For any entity not covered above, agents SHOULD use `tea api` or `curl` with the [Forgejo API docs](https://git.ncrmro.com/api/swagger).

## Known Limitations

- **`fj pr view` does not accept `-r owner/repo`** — must be run from inside the repo's git directory, or use `tea api /repos/{owner}/{repo}/pulls/{number}` instead.
- **`fj pr merge` returns 405 if the PR has not been approved** — this means approval is pending, not a bug. Wait for review.
- **Agents cannot self-approve PRs** — a PR created by an agent cannot be approved by that same agent.

## Project Boards

23. Forgejo 14.0.2 has **no project board REST API** (verified against the swagger spec).
24. Boards are managed via web UI only at `https://{host}/{owner}/{repo}/projects`.
25. Agents MUST document board URLs in milestone or issue descriptions for easy access.
26. See `process.project-board` for full board lifecycle and Forgejo-specific guidance.
