# Convention: GitHub Personal Access Tokens (tool.github-pats)

Standards for managing GitHub Personal Access Tokens (PATs) on keystone hosts.
Two distinct tokens MUST be used, scoped to two distinct call sites: an
interactive user PAT and an agents PAT. Sharing one token across both blurs
audit trails and grants agents more than they need.

## Purpose

1. The user PAT MUST authenticate interactive `gh`, `git` over HTTPS, and any
   tool that reads `GITHUB_TOKEN` or `GH_TOKEN` from the environment.
2. The user PAT MUST also be the credential used for `ghcr.io` container
   registry login.
3. The agents PAT MUST be used only by autonomous agent flows that open pull
   requests, fetch repos, or comment on issues. It MUST NOT be exported as
   `GITHUB_TOKEN` in interactive shells.
4. The user PAT and the agents PAT MUST be distinct GitHub tokens with
   distinct scopes — they MUST NOT alias to the same token value.

## The user PAT

5. The secret name MUST follow the user-home naming convention
   `${username}-github-token` (e.g. `ncrmro-github-token`). See CLAUDE.md
   secret-class rules 22-28.
6. The recipient set MUST include every system where the user's home-manager
   profile is installed (rule 26).
7. The agenix file MUST be declared with `owner = <username>; mode = "0400";`
   so the daemon makes it readable only to the owning user.
8. Recommended scopes (fine-grained PAT, preferred):
   - `contents`: Read and write
   - `pull_requests`: Read and write
   - `issues`: Read and write
   - `packages`: Read and write (required for `ghcr.io` push)
   - `metadata`: Read
   - `workflow`: Read and write (only if the user edits Actions YAML)
9. Recommended scopes (classic PAT, fallback for org features fine-grained
   PATs do not yet cover):
   - `repo`
   - `read:org`
   - `read:packages`, `write:packages`
   - `workflow` (optional)
   - `admin:ssh_signing_key` (only when bootstrapping SSH signing per
     `tool.github` rules 11, 18)
10. The user PAT MUST NOT include `delete_repo`, `admin:org`, or
    `admin:enterprise` scopes.

## The agents PAT

11. The secret name SHOULD be `github-agents-token` for a single-owner fleet,
    or `${owner}-github-agents-token` for multi-owner fleets where multiple
    GitHub accounts run agents on the same host.
12. The recipient set MUST include every system that runs agents under this
    GitHub identity. It MAY be broader than the user PAT recipient set when
    agents run on hosts where the human does not log in interactively.
13. The agenix file MUST be declared with `owner = <user-the-agent-runs-as>;
    mode = "0400";`.
14. Recommended scopes (fine-grained PAT):
    - `contents`: Read
    - `pull_requests`: Read and write
    - `issues`: Read and write
    - `metadata`: Read
15. The agents PAT MUST NOT include `packages`, `workflow`, `admin:*`,
    `delete_repo`, or `write` on `contents`.
16. When an agent needs write access to a specific repo, the fine-grained PAT
    SHOULD be scoped to that repo via the resource selector rather than
    granted org-wide.

## Adopter contract

17. The adopter MUST encrypt each token in its agenix-secrets repo. Keystone
    does not ship the `.age` files — they live in the adopter's private
    secrets repo.
18. The adopter MUST declare `age.secrets.<name>` on every host listed as a
    recipient, matching the owner/mode rules above.
19. The adopter MUST enable the keystone module in the user's home-manager
    profile:
    ```nix
    keystone.terminal.github = {
      enable = true;
      username = "<github-username>";
      # userTokenFile defaults to /run/agenix/<username>-github-token
      agentsTokenFile = "/run/agenix/github-agents-token";  # optional
    };
    ```
20. The module exports `GITHUB_TOKEN` and `GH_TOKEN` at shell startup by
    reading `userTokenFile` at runtime. If the file is not readable, the
    shell continues without setting the variables — the module never fails
    the shell on missing credentials.
21. When `agentsTokenFile` is set, the module exports
    `GITHUB_AGENTS_TOKEN_FILE` (the path, not the value). Agents MUST read
    this file explicitly; the token value MUST NOT be exposed as
    `GITHUB_TOKEN`.

## ghcr.io usage

22. The module installs a `ghcr-login` shell function. To authenticate to the
    registry:
    ```
    ghcr-login
    podman pull ghcr.io/<owner>/<image>:<tag>
    ```
23. `ghcr-login` MUST use `--password-stdin` — never pass the token via argv
    or environment, since both leak through `ps` and shell history.
24. The helper writes credentials to the runtime's standard auth file
    (`~/.config/containers/auth.json` for podman, `~/.docker/config.json` for
    docker). Keystone MUST NOT manage this file declaratively because the
    runtime writes other registries into the same file.
25. To log out, use the runtime's native command:
    `podman logout ghcr.io` or `docker logout ghcr.io`.

## Non-uses

26. The user PAT MUST NOT be placed in `nix.settings.access-tokens`. The
    nix-daemon runs as root and cannot read a `mode 0400 owner=<user>` file;
    even if it could, daemon-level access requires its own os-level secret
    with a recipient set that includes every host that fetches flake inputs.
    See `tool.nix` for the os-level access-tokens convention (TODO).
27. Neither token MUST be baked into CI runner images or container images.
28. Neither token MUST be written to a long-lived disk location outside the
    agenix runtime (e.g. `~/.config/gh/hosts.yml`). The module deliberately
    does not run `gh auth login --with-token` for this reason — `gh` reads
    `GH_TOKEN` from env, which is sufficient.

## See also

- `tool.github` — device-flow auth, SSH key sync, commit signing.
- `tool.bitwarden` — model for the agenix runtime path convention.
- CLAUDE.md secret-class rules 22-31 — user-home vs. os-level vs. service
  secret classes and recipient discipline.
