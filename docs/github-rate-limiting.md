# GitHub rate limiting in the Keystone update flow

The supervised update flow hits api.github.com from two places, and
both contribute to the 60-requests-per-hour unauthenticated cap that
GitHub enforces per source IP:

1. **`ks` release fetcher** — `cmd::update_menu::fetch_stable_latest_release`
   (and the unstable counterpart) calls
   `https://api.github.com/repos/ncrmro/keystone/releases/latest`
   every time the Walker update menu queries status, and again before
   `ks update --approve` resolves the target rev.
2. **Nix flake fetcher** — `nix flake update keystone` (and the
   `path:`/`github:` override variants) calls
   `https://api.github.com/repos/<owner>/<repo>/commits/<rev>` for
   every input fetch, on every rebuild iteration that re-locks.

A few rebuild iterations from a single household/NAT'd IP is enough
to trip 60/hr. Symptoms:

- Walker menu: `Keystone OS unavailable` with subtext
  `Unable to fetch the latest Keystone release from GitHub: GitHub
  returned non-success status` (this is `ks` surfacing the 403).
- `nix flake update`:
  `error: unable to download 'https://api.github.com/repos/.../commits/<rev>':
  HTTP error 403` with body
  `{"message":"API rate limit exceeded for <ip>. (But here's the good
  news: Authenticated requests get a higher rate limit. Check out the
  documentation for more details.)"}`.

Authenticated requests get **5000/hr**, so a read-only fine-grained
PAT eliminates the wall for any realistic rebuild cadence.

## Provisioning a read-only token

Generate a fine-grained PAT at
`https://github.com/settings/personal-access-tokens/new`:

- Repository access: **Only select repositories** → `ncrmro/keystone`
  (and any other repo your host's flake.lock pulls from
  `github:`-style — e.g. an org-private agenix-secrets repo).
- Permissions → Repository:
  - **Contents: Read-only**
  - **Metadata: Read-only**
- Expiration: pick a value you're comfortable rotating (30–90 days
  for a test host, 1 year for a permanent host).

Generate. Copy the `github_pat_…` value once — GitHub won't show it
again.

## Wiring it into a Keystone-managed host

The token has to reach two consumers:

| Consumer | How it reads the token |
|---|---|
| `nix` (flake fetcher, `nix-prefetch-url`, etc.) | `access-tokens = github.com=<token>` in `/etc/nix/nix.conf` (or a `!include`d fragment) |
| `ks` (release fetcher in `update_menu.rs`) | `$GITHUB_TOKEN` env var on the process; the Authorization header is then set as `Bearer <token>` |

The minimal NixOS module that handles both:

```nix
# github-token.nix (host config, not in keystone itself)
{ config, pkgs, ... }:
let tokenFile = "/etc/nix-github-token"; in {
  # nix.conf include for the flake fetcher.
  nix.extraOptions = ''
    !include ${tokenFile}
  '';

  # systemd user-environment generator exports GITHUB_TOKEN to every
  # user-mode service (walker, hyprpolkitagent, the helpers Walker
  # spawns for ks update).
  environment.etc."systemd/user-environment-generators/10-github-token" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      if [[ -r ${tokenFile} ]]; then
        token=$(${pkgs.gnused}/bin/sed -n 's/^access-tokens = github\.com=//p' ${tokenFile} | ${pkgs.coreutils}/bin/head -1)
        if [[ -n "$token" ]]; then
          echo "GITHUB_TOKEN=$token"
        fi
      fi
    '';
  };
}
```

Place the token outside the nix store, world-unreadable but
group-readable to the user so the env generator can read it:

```sh
sudo install -m 0440 -o root -g users /dev/null /etc/nix-github-token
sudo tee /etc/nix-github-token > /dev/null <<'EOF'
access-tokens = github.com=github_pat_xxxxxxxxxxxx
EOF
```

Activate. Then re-exec the user systemd manager so the env generator
runs in the live session:

```sh
systemctl --user daemon-reexec
systemctl --user show-environment | grep GITHUB_TOKEN   # confirm
```

A fresh login achieves the same thing. Walker, hyprpolkitagent, and
anything they spawn (including ks) inherit `$GITHUB_TOKEN` from then
on.

## Why a single file in nix.conf-format

The same file feeds both consumers, so the operator only provisions
one secret. The format is `nix.conf`'s native `access-tokens = …`
syntax, so `nix`'s `!include` directive picks it up directly with no
shimming. The env generator strips the prefix to get the raw token
for `$GITHUB_TOKEN`.

If the file is absent, `!include` is tolerated (modern Nix treats a
missing include as a soft error, not a build failure) and the env
generator emits nothing — the host falls back to unauthenticated
behaviour, which is fine for a freshly-provisioned host that hasn't
been wired yet.

## Why not store the PAT in the consumer flake

A PAT is a credential. Keeping it in the consumer flake repo means
it ends up in `flake.lock` references, git history, and the
nix-store output — none of which honor secrecy. The two real options
are:

- **Plain file outside the store**, provisioned manually
  (`/etc/nix-github-token`, mode `0440 root:users`). Simple, works
  immediately, but no rotation tracking.
- **agenix / sops-nix secret** decrypted to the same path. Tracks
  rotation, survives `nixos-rebuild` cleanly, requires the host to
  have an SSH host key registered as a recipient. Use this once the
  host graduates beyond rc.

The above module supports both transparently: it only reads from
`/etc/nix-github-token`. The plain-file vs. agenix question is
upstream of the module.

## Scope and lifetime guidance

- A read-only `Contents` permission is the minimum required for both
  the release-fetcher and the flake-fetcher. Don't grant `Actions`,
  `Pull requests`, or anything else.
- Scope the token to **only the repos your flake.lock references**.
  For a Keystone host with only the upstream pin, that's just
  `ncrmro/keystone`.
- Expiration: pick the shortest interval you'll actually rotate.
  Rate limiting cost without a token is "Walker update flow doesn't
  work until you wait an hour" — annoying, not catastrophic — so
  defaulting to 30 days and re-issuing is a reasonable tradeoff.

## Caveats

- The user-environment generator only runs when the user systemd
  manager starts (login) or is explicitly re-exec'd
  (`systemctl --user daemon-reexec`). Services already running
  before the token was provisioned won't see `$GITHUB_TOKEN` until
  they're restarted.
- `ks` only checks `$GITHUB_TOKEN`. If you have a different env var
  set (`GH_TOKEN`, `GITHUB_API_TOKEN`, etc.) it won't be picked up.
- The token is **per-host**. If you have a fleet of Keystone
  machines behind the same NAT, each host needs its own token (or
  share one — group bandwidth allowing). 5000/hr per token is far
  more than any realistic rebuild cadence consumes.

## Detection

Quick check on a host whether the rate-limit fix is wired:

```sh
# Is the include file present?
test -r /etc/nix-github-token && echo "token file: yes" || echo "token file: NO"

# Does nix.conf reference it?
grep -q '^!include /etc/nix-github-token$' /etc/nix/nix.conf && echo "nix.conf wired: yes" || echo "nix.conf wired: NO"

# Does the user session export GITHUB_TOKEN?
systemctl --user show-environment | grep -q '^GITHUB_TOKEN=' && echo "env wired: yes" || echo "env wired: NO"

# Sanity-check the token works
curl -sH "Authorization: Bearer $(systemctl --user show-environment | sed -n 's/^GITHUB_TOKEN=//p')" \
  https://api.github.com/rate_limit | grep -A2 '"core"'
```

The last line should show `"limit": 5000` instead of `60`.
