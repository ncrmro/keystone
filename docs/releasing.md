# Keystone releasing

Keystone uses `main` as the unstable integration branch. Every merge to `main`
is eligible for the next release train, but `main` is not the branch that
publishes stable releases.

## Branch model

- `main` is unstable and always open for ongoing development.
- `release/X.Y` branches are the stabilization branches for the `X.Y` release line.
- `hotfix/X.Y.Z` branches are optional and only used for urgent post-release fixes.

## Release cadence

1. A human starts the GitHub Actions `Release` workflow from `main`.
2. The workflow takes `X.Y.Z` as the release input and derives `release/X.Y`.
3. If `release/X.Y` does not exist, the workflow creates it from `main`.
4. If `release/X.Y` already exists, the workflow reuses it as the stabilization branch for the next patch in that series.
5. The workflow builds, tests, tags `vX.Y.Z`, and publishes a GitHub Release with generated notes from the `release/X.Y` branch head.
6. Any stabilization fixes to `release/X.Y` happen through pull requests with human approval.
7. Merge the finalized `release/X.Y` branch back into `main` after the series is stabilized.

## Versioning

- Stable project releases are identified by git tags in the form `vX.Y.Z`.
- The git tag is the canonical release version for Keystone.
- `main` does not carry a stable version number. It represents the next unstable state after the latest tag.
- Package-local versions may remain package-specific, but they do not define the Keystone release line.

## Release notes

- GitHub Releases are the canonical generated release notes for each stable release.
- GitHub generates release notes from merged pull requests and labels using `.github/release.yml`.
- `CHANGELOG.md` remains available as the curated historical summary for the repository.

## Publishing model

- Keystone releases publish to GitHub Releases.
- Keystone does not currently publish release binaries or packages from this workflow.
- Consumers primarily consume Keystone through the git repository and flake input.

## Branch protection

Keystone now uses GitHub repository rulesets for branch protection.

Configured `main` rules:

- Require pull requests before merging.
- Require the `flake-check` status check before merging.
- Block force pushes and branch deletion.

Configured `release/X.Y` rules:

- Require pull requests before merging stabilization changes.
- Require one approval before merging stabilization changes.
- Dismiss stale approvals when new commits land on the pull request.
- Require last-push approval so the actor behind the final push cannot self-approve.
- Require all review threads to be resolved before merging.
- Require the `flake-check` status check before merging, and require the branch to be up to date with the base branch before merge.
- Block force pushes.
- Block branch deletion.

Notes:

- The release rules are implemented as a wildcard GitHub ruleset targeting `refs/heads/release/*`.
- No bypass actors are configured for the `release/*` ruleset, so direct updates to existing release branches are blocked for every actor.
- The `Release` workflow is a human-owned `workflow_dispatch` action from `main`. It is the only supported path for creating new `release/*` branches.
- GitHub repository rulesets on this repo cannot currently express "GitHub Actions may create `release/*`, but no other actor may do so." Keystone therefore treats branch creation as an operator policy enforced by process, and the ruleset enforces PR-only updates after the branch exists.
- Agents may propose changes to `release/*` through pull requests, but they must not create release branches directly and they must not merge stabilization changes without human approval.
- If Keystone starts using `hotfix/*` branches, add a matching GitHub ruleset for that namespace.

## Operating notes

- Only run the `Release` workflow from `main`.
- The workflow rejects duplicate tags.
- The workflow derives `release/X.Y` from the supplied `X.Y.Z`.
- If a release series already exists, the workflow releases from the current `release/X.Y` branch head rather than from `main`.
- If a release needs an urgent patch after publication, branch `hotfix/X.Y.Z` from the released tag, land the fix there, rerun the release process for the next patch version, and merge the result back into `main`.
