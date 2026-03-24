# Pull Request Update

## Objective

Prepare the PR for review by updating the Demo section with evidence that the
implementation works. Run screenshot tests if available, post visual evidence,
and ensure the PR body reflects the current state of the work.

## Task

### Process

#### Step 1: Collect Current State

Read run.md and TASK.md from the worktree to understand what was implemented:

```bash
WORKTREE=.repos/OWNER/REPO/.worktrees/BRANCH

cat $WORKTREE/TASK.md
git -C $WORKTREE log --oneline main..HEAD
git -C $WORKTREE diff main..HEAD --stat
```

Get the PR number:
```bash
# GitHub
PR_NUM=$(gh pr list --repo OWNER/REPO --head $BRANCH --json number --jq '.[0].number')

# Forgejo
PR_NUM=$(fj pr list --repo OWNER/REPO --head $BRANCH --json number --jq '.[0].number')
```

#### Step 2: Run Screenshot Tests (if available)

Check if the project has screenshot test infrastructure:

```bash
cd $WORKTREE

# Look for screenshot test scripts in package.json
grep -q 'test:screenshots' package.json 2>/dev/null && HAS_SCREENSHOTS=true
```

If screenshot tests exist, run them:

```bash
bun run test:screenshots  # or npm/pnpm equivalent
```

Commit and push screenshots:

```bash
git add -A tests/**/screenshots/ packages/**/screenshots/
git commit -m "test(screenshots): capture requirement evidence"
git push
```

**Skip this step** if no screenshot test infrastructure exists in the project.

#### Step 3: Post Screenshot Demo on PR

Screenshots must be uploaded so they render inline in PR comments. The method
depends on whether the repo is public or private.

**Detect repo visibility:**
```bash
PRIVATE=$(gh api repos/OWNER/REPO --jq '.private')
```

**Public repos** — use `raw.githubusercontent.com` URLs directly:
```bash
SHA=$(git rev-parse --short HEAD)
IMAGE_URL="https://raw.githubusercontent.com/OWNER/REPO/$SHA/path/to/screenshot.png"
```

**Private repos** — `raw.githubusercontent.com` returns 404 for unauthenticated
viewers. Upload screenshots as **draft release assets** instead:

```bash
# Create a draft release for hosting screenshot assets
RELEASE_ID=$(gh api repos/OWNER/REPO/releases -X POST \
  -f tag_name="screenshots-$(date +%Y%m%d-%H%M%S)" \
  -f name="Screenshot Evidence" \
  -F draft=true \
  --jq '.id')

# Upload each screenshot
for f in path/to/screenshots/*.png; do
  NAME=$(basename "$f")
  URL=$(curl -sS -X POST \
    -H "Authorization: token $(gh auth token)" \
    -H "Content-Type: image/png" \
    "https://uploads.github.com/repos/OWNER/REPO/releases/$RELEASE_ID/assets?name=$NAME" \
    --data-binary "@$f" | jq -r '.browser_download_url')
  echo "$NAME -> $URL"
done
```

Draft release assets are accessible to anyone with repo access and render inline
in GitHub markdown.

**Post the PR comment:**
```bash
gh pr comment $PR_NUM --repo OWNER/REPO --body "$(cat <<EOF
## Demo Screenshots

Automated Playwright screenshots capturing requirement evidence.

### Screenshot 1 — Description (REQ-NNN)
![Description]($IMAGE_URL_1)

### Screenshot 2 — Description (REQ-NNN)
![Description]($IMAGE_URL_2)
EOF
)"
```

Each screenshot should reference the requirement(s) it provides evidence for.

**Forgejo:**
```bash
fj pr comment $PR_NUM --repo OWNER/REPO --body "..."
```

Note: Forgejo does not support release asset uploads in the same way. For Forgejo
private repos, consider hosting screenshots in a public location or using inline
base64 data URIs for small images.

#### Step 4: Update PR Demo Section

Update the PR body's `# Demo` section with evidence the work is correct.
Include all available evidence:

- **Screenshot URLs** (if captured in Steps 2-3)
- **Deploy preview URL** (if the project uses Cloudflare Workers, Vercel, Netlify — check for bot comments on the PR)
- **Test results** summary
- **Key behaviors verified**

```bash
gh pr edit $PR_NUM --repo OWNER/REPO --body "$(cat <<'EOF'
...existing body with Goal/Tasks/Changes sections...

# Demo

## Screenshots
- [Screenshot descriptions with requirement references]

## Verification
- Tests pass: `bun test` — N/N passed
- [Specific behaviors verified]
EOF
)"
```

#### Step 5: Write pull_request_update.md

Write the output document to `.deepwork/tmp/sweng/pull_request_update.md`:

```markdown
---
pr_number: 42
pr_url: https://github.com/OWNER/REPO/pull/42
screenshots_posted: true
demo_updated: true
updated: 2026-03-21T15:30:00Z
platform: github
---

# PR Update: feat/task-slug

## Screenshots
- 01-full-layout.png (REQ-007) — posted as PR comment
- 02-file-viewer.png (REQ-001) — posted as PR comment

## Demo Section
Updated with screenshot evidence and test results.

## Deploy Preview
[URL if available, or "N/A — no deploy preview configured"]
```

## Quality Criteria

- PR Demo section updated with concrete evidence (screenshots, test results, preview URLs)
- Screenshot tests run if available; screenshots committed, pushed, and posted as PR comment
- Private repos use draft release assets (not raw.githubusercontent.com which 404s)
- Screenshots reference specific requirements (REQ-NNN) they provide evidence for
- PR body reflects the current state of implementation
- Platform-appropriate commands used (gh vs fj)
- pull_request_update.md written with evidence summary

## Context

This step runs after the agent completes implementation (assign) and before
the review loop begins. Its purpose is to gather and present evidence so that
reviewers (Copilot, humans, or other agents) can evaluate the PR effectively.

Screenshot tests are best-effort — not all projects have them. When they do exist,
they provide strong visual evidence for UI requirements and should always be run.
