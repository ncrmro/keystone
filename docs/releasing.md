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

## Update channels

Hosts running the Walker update menu (`ks menu update`, wired up via
`modules/desktop/home/services.nix`) track one of two sources. Selection is
declarative, through the `keystone.update.channel` option:

- `stable` (default) — the Walker menu reads `/releases/latest` and only
  treats strict `v<major>.<minor>.<patch>` tags as release-tag matches.
  If the repository has no matching tagged release, `/releases/latest`
  returns 404 and the menu renders `Keystone OS unavailable`.
- `unstable` — the menu reads `GET /repos/OWNER/REPO/branches/main` —
  this tracks the tip commit, not a tagged release. The displayed
  `latest` row renders as `main@<short-sha>` and always reflects the
  current head of `main`.

To change a host's channel:

```nix
# In your consumer flake (nixos-config)
keystone.update.channel = "unstable";
```

Then run `ks update --dev` (deploy the current checkout) to pick up the
new value. The channel is embedded into the `ks-update.service` unit
environment and the shell's `home.sessionVariables` at activation time,
so interactive `ks menu update status` and background Walker dispatches
agree on which source the host polls.

The stable channel remains the default and requires no per-host declaration.

### Fleet default and per-host overrides

Consumer flakes that use `keystone.lib.mkSystemFlake` can set the fleet-wide
channel once and override it per host:

```nix
keystone.lib.mkSystemFlake {
  defaults = {
    timeZone = "UTC";
    updateChannel = "unstable"; # fleet-wide default
  };
  hosts = {
    laptop = { kind = "laptop"; }; # inherits unstable
    server = {
      kind = "server";
      updateChannel = "stable"; # overrides the fleet default
    };
  };
}
```

Resolution order (highest precedence first):

1. `config.keystone.update.channel` set directly in a host's NixOS or
   home-manager modules.
2. The host entry's `updateChannel` attribute in `hosts`.
3. `defaults.updateChannel` in `mkSystemFlake`.
4. The option default (`"stable"`, declared in
   `modules/shared/update.nix`).

The fleet and per-host attributes apply through `lib.mkDefault`, so explicit
module-level declarations always win.

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
