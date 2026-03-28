# Dev Environment Audit

## Objective

Audit a repository's development environment against keystone conventions. Check
devshell setup, git conventions, TDD infrastructure, and CI pipeline health.
Produce an actionable audit report with pass/fail results and remediation steps.

## Task

### Process

#### Step 1: Determine Target Repository

Ask structured questions if needed:

- **repo_path**: Path to the repository to audit. Defaults to current working directory.

If a repo path is provided, verify it exists and is a git repository:

```bash
git -C $REPO_PATH rev-parse --is-inside-work-tree
```

#### Step 2: Devshell Audit (tool.nix-devshell)

Check Nix devshell setup:

1. **flake.nix exists**:

   ```bash
   test -f $REPO_PATH/flake.nix && echo "PASS" || echo "FAIL: No flake.nix"
   ```

2. **flake.lock committed**:

   ```bash
   git -C $REPO_PATH ls-files flake.lock | grep -q flake.lock && echo "PASS" || echo "FAIL: flake.lock not tracked"
   ```

3. **Devshell builds**:

   ```bash
   cd $REPO_PATH && nix develop --command true 2>&1
   ```

   Record the exit code and any error output.

4. **.envrc exists with `use flake`**:

   ```bash
   grep -q 'use flake' $REPO_PATH/.envrc 2>/dev/null && echo "PASS" || echo "FAIL: No .envrc or missing 'use flake'"
   ```

5. **.direnv/ in .gitignore**:

   ```bash
   grep -q '.direnv' $REPO_PATH/.gitignore 2>/dev/null && echo "PASS" || echo "FAIL: .direnv not in .gitignore"
   ```

6. **No global tool usage** (spot check):
   ```bash
   # Check for npx, npm install -g, or playwright install in scripts/CI
   rg -l 'npx |npm install -g|playwright install' $REPO_PATH/.github/ $REPO_PATH/.forgejo/ $REPO_PATH/Makefile $REPO_PATH/scripts/ 2>/dev/null
   ```

#### Step 3: Git Conventions Audit (process.version-control)

Check git hygiene:

1. **.gitignore covers common artifacts**:

   ```bash
   # Check for standard entries
   for pattern in node_modules .env dist build target .direnv; do
     grep -q "$pattern" $REPO_PATH/.gitignore 2>/dev/null && echo "PASS: $pattern" || echo "WARN: $pattern not in .gitignore"
   done
   ```

2. **No gitignored files in repo**:

   ```bash
   git -C $REPO_PATH status --ignored --short 2>/dev/null | head -20
   ```

3. **Conventional commit format** (check recent commits):

   ```bash
   git -C $REPO_PATH log --oneline -20
   ```

   Verify messages follow `type(scope): subject` format.

4. **CODEOWNERS file exists**:

   ```bash
   test -f $REPO_PATH/CODEOWNERS || test -f $REPO_PATH/.github/CODEOWNERS || test -f $REPO_PATH/docs/CODEOWNERS
   ```

5. **Commit discipline** (spot check):
   - Check for commits that bundle unrelated changes
   - Check for dependency changes in dedicated commits

#### Step 4: TDD Infrastructure Audit

Check that a clean TDD path exists:

1. **Test runner/framework present**:
   - Check `package.json` for test scripts and test dependencies
   - Check `Cargo.toml` for test dependencies
   - Check `flake.nix` for test packages in devshell
   - Check for test directory (`tests/`, `test/`, `__tests__/`, `spec/`)

2. **Tests can execute**:

   ```bash
   cd $REPO_PATH
   # Try common test runners (adapt to detected tech stack)
   nix develop --command npm test 2>&1 | tail -5
   # or: nix develop --command cargo test 2>&1 | tail -5
   ```

   Record pass/fail and count.

3. **TDD commit pattern supported**:
   - Verify the test framework supports running individual tests
   - Check if there's a watch mode for rapid iteration
   - Note: per convention, failing tests MUST be committed separately from implementation

#### Step 5: CI Pipeline Audit (process.continuous-integration)

Check CI configuration:

1. **CI config exists**:

   ```bash
   ls $REPO_PATH/.github/workflows/*.yml 2>/dev/null || \
   ls $REPO_PATH/.forgejo/workflows/*.yml 2>/dev/null
   ```

2. **CI runs on PRs**:
   Check workflow triggers include `pull_request` or equivalent.

3. **CI includes test step**:

   ```bash
   rg -l 'test|check|lint' $REPO_PATH/.github/workflows/ $REPO_PATH/.forgejo/workflows/ 2>/dev/null
   ```

4. **Recent CI status** (if on a platform):

   ```bash
   # GitHub:
   gh run list --repo OWNER/REPO -L 5 --json conclusion,name,status
   # Forgejo:
   tea api --login forgejo /repos/OWNER/REPO/actions/runs | head -20
   ```

5. **Branch protection**:
   ```bash
   # GitHub:
   gh api repos/OWNER/REPO/branches/main/protection 2>/dev/null
   ```

#### Step 5b: Platform Secrets Audit (Cloudflare Workers / Vercel / Netlify)

If the project deploys to a platform, check that required secrets and variables
are configured:

1. **GitHub Actions secrets/variables**:

   ```bash
   gh secret list --repo OWNER/REPO
   gh variable list --repo OWNER/REPO
   ```

   Cross-reference with what the deploy workflow expects (search for `${{ secrets.*}}`
   and `${{ vars.*}}` in `.github/workflows/`).

2. **For Cloudflare Workers projects** (detected by `wrangler.jsonc` or `wrangler.toml`):

   ```bash
   # Check wrangler config exists
   test -f $REPO_PATH/wrangler.jsonc || test -f $REPO_PATH/wrangler.toml

   # Check for OpenNext.js (Next.js on CF Workers)
   test -f $REPO_PATH/open-next.config.ts && echo "OpenNext.js project"
   ```

   Required setup for CF Workers + Next.js (OpenNext.js):
   - `wrangler.jsonc` with worker name, compatibility settings, R2 bindings
   - `open-next.config.ts` for the OpenNext.js adapter
   - GitHub Actions secrets: platform-specific (e.g., `DATABASE_AUTH_TOKEN`)
   - GitHub Actions variables: platform-specific (e.g., `DATABASE_URL`)
   - Wrangler secrets set via `wrangler secret put` from the server
   - CF Workers Builds git integration enabled in Cloudflare dashboard

3. **Report missing secrets**: List each expected secret/variable and whether it's configured.

#### Step 6: Generate Audit Report

Write the audit report to `.deepwork/tmp/sweng/audit_report.md`:

```bash
mkdir -p .deepwork/tmp/sweng
```

## Output Format

### audit_report.md

```markdown
# Dev Environment Audit Report

**Repository**: owner/repo
**Path**: /path/to/repo
**Date**: 2026-03-21
**Overall**: X/Y checks passed

## Devshell (tool.nix-devshell)

| Check                 | Status | Details                              |
| --------------------- | ------ | ------------------------------------ |
| flake.nix exists      | PASS   |                                      |
| flake.lock committed  | PASS   |                                      |
| Devshell builds       | PASS   | nix develop --command true succeeded |
| .envrc with use flake | FAIL   | No .envrc file found                 |
| .direnv in .gitignore | FAIL   | .direnv not listed                   |
| No global tool usage  | PASS   | No npx/global installs found         |

### Remediation

- Create `.envrc` with content: `use flake`
- Add `.direnv/` to `.gitignore`

## Git Conventions (process.version-control)

| Check                       | Status | Details                                 |
| --------------------------- | ------ | --------------------------------------- |
| .gitignore coverage         | PASS   | All standard patterns present           |
| No gitignored files tracked | PASS   |                                         |
| Conventional commits        | WARN   | 3/20 recent commits don't follow format |
| CODEOWNERS exists           | FAIL   | No CODEOWNERS file found                |
| Commit discipline           | PASS   | No bundled unrelated changes found      |

### Remediation

- Create `CODEOWNERS` file per process.code-review-ownership convention
- Fix commit message format for: [list specific commits]

## TDD Infrastructure

| Check                  | Status | Details                   |
| ---------------------- | ------ | ------------------------- |
| Test framework present | PASS   | vitest in devDependencies |
| Test directory exists  | PASS   | tests/ with 12 test files |
| Tests execute          | PASS   | 47/47 tests passed        |
| Watch mode available   | PASS   | vitest --watch configured |

### Remediation

(none needed)

## CI Pipeline (process.continuous-integration)

| Check             | Status | Details                               |
| ----------------- | ------ | ------------------------------------- |
| CI config exists  | PASS   | .github/workflows/ci.yml              |
| CI runs on PRs    | PASS   | pull_request trigger configured       |
| CI includes tests | PASS   | test step in workflow                 |
| Recent CI status  | PASS   | Last 5 runs: 5 success                |
| Branch protection | WARN   | No branch protection rules configured |

### Remediation

- Enable branch protection requiring CI checks to pass before merge

## Summary

**Passed**: X checks
**Warnings**: Y checks
**Failed**: Z checks

### Priority Fixes

1. [Most critical finding with specific remediation]
2. [Second most critical]
3. [Third]
```

## Quality Criteria

- Devshell checked: flake.nix exists, builds, .envrc has `use flake`, .direnv/ gitignored
- Git conventions checked: .gitignore covers artifacts, CODEOWNERS exists, commits follow format
- TDD path verified: test framework present, tests execute, supports TDD commit pattern
- CI pipeline verified: config exists, runs on PRs, includes tests, recent status checked
- Each finding includes a specific remediation step — not just "X is missing"
- Report organized by convention area with clear pass/fail/warn status
- Priority fixes listed in order of importance

## Context

The audit workflow provides a health check for any repository's dev environment.
It verifies the conventions that the `implement`, `fix`, and `refactor` workflows
depend on — if the audit fails, those workflows are likely to hit friction.

Run the audit when:

- Setting up a new project
- Onboarding to an unfamiliar repository
- Debugging why the implementation workflow keeps failing
- Periodic maintenance to catch convention drift
