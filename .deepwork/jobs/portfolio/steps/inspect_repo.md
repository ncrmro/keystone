# Inspect Gap Project Repo

## Objective

Fetch a complete snapshot of a single project's repo state — releases, recent commits,
open issues, README, and any existing charter/profile — to give the proposal step
enough context to suggest a meaningful milestone.

## Task

1. **Fetch releases and tags**

   Get the most recent 5 releases or tags to understand the project's release history:

   **GitHub**:
   ```bash
   gh release list --repo {owner}/{repo} --limit 5
   gh api repos/{owner}/{repo}/tags --jq '.[0:5] | .[] | .name'
   ```

   **Forgejo**:
   ```bash
   fj releases list {owner}/{repo} --limit 5
   # or: tea api GET /repos/{owner}/{repo}/releases?limit=5
   ```

   Note: if there are no releases, check for tags via `git tag` on a local clone.

2. **Fetch recent commit history**

   Get the last 20 commits to understand what has been worked on recently:

   **GitHub**:
   ```bash
   gh api repos/{owner}/{repo}/commits --jq '.[] | "\(.commit.author.date[:10]) \(.commit.message | split("\n")[0])"' | head -20
   ```

   **Local clone** (if available under `~/code/ncrmro/{repo}` or similar):
   ```bash
   git -C {local_path} log --oneline --since="180 days ago" | head -20
   ```

3. **Fetch open issues**

   Get up to 30 open issue titles to understand the backlog:

   **GitHub**:
   ```bash
   gh issue list --repo {owner}/{repo} --limit 30 --json number,title,labels \
     --jq '.[] | "#\(.number) \(.title)"'
   ```

   **Forgejo**:
   ```bash
   fj issue list {owner}/{repo} --limit 30
   ```

4. **Read README**

   Fetch the first 100 lines of the README to understand the project's stated purpose:

   **GitHub**:
   ```bash
   gh api repos/{owner}/{repo}/readme --jq '.content' | base64 -d | head -100
   ```

   **Local clone**:
   ```bash
   head -100 {local_path}/README.md
   ```

5. **Read charter/profile if available**

   If any of these files exist in the notes repo, read them:
   - `{notes_path}/projects/{slug}/charter.md`
   - `{notes_path}/projects/{slug}/README.md`
   - `{notes_path}/projects/{slug}/status.md`

   These provide context on the project's original goals and intended direction.

## Output Format

### repo_snapshot.md

```markdown
# Repo Snapshot — {project_slug}

**Date**: [YYYY-MM-DD]
**Repos**: [owner/repo (platform)]

## Releases / Tags

- v0.1.0 — 2025-09-01
- v0.0.1 — 2025-06-15

(no releases found — most recent tag: v0.1.0 on 2025-09-01)

## Recent Commits (last 180 days)

- 2025-11-15 fix: handle empty state on startup
- 2025-11-10 feat: add dark mode toggle
- 2025-10-28 chore: update dependencies
[...]

## Open Issues (30 most recent)

- #12 Crash on large file import
- #11 Add keyboard shortcut for search
- #8 Export to PDF broken
[3 total]

## README Excerpt

[First ~100 lines of README]

## Charter / Profile Notes

[Content of charter.md or status.md if found, otherwise: "No notes found."]
```

## Quality Criteria

- At least one repo was successfully queried (not all failures)
- Releases/tags section accurately reflects the repo state (not fabricated)
- Open issues are real issues from the repo
- README excerpt is present if the repo has a README
