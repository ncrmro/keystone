# 2026-07 Q3 — ks.systems org stabilization plan

Canonical plan for stabilizing every ks.systems project on a first cut
release. Directives:

- **each project stabilizes on a 0.1.0**;
- **KS OS v1 is rescoped to only baremetal setup, ks-config templating, and
  secrets repo templating**;
- **terminal modules move to a new `ks.systems/hterm` repo and desktop
  modules to a new `ks.systems/desktop` repo**, each releasing its own
  0.1.0. The extractions are what make the narrow os v1 scope structural
  rather than documentary.

Landing mode: small PRs, fast-forward or `--no-ff` per milestone; never
squash a planned span. Time flows up; the lowest ○ in each graph is the next
unit of work.

---

## ks.systems/os — KS OS v1 (rescoped)

v1 bar: a stranger can take a bare machine to a running, rebuildable system
using a templated ks-config and a templated secrets repo. Terminal and
desktop are no longer part of this repo at v1 — they are consumed as flake
inputs (`ks.systems/hterm`, `ks.systems/desktop`) by ks-config, not by os.

The repo was reset to an empty root commit on 2026-07-27 (9cf9864); all
prior history lives on `archive/2026-07-27-Q3-{main,v1,v2}`, the retired
branches, and the v0.x/rc tags. v1 is a rebuild, seeded from the
`~/repos/keystone-systems/os` fleet harness (mkFleet, ksvm, REQ-001
foundation: disko LUKS/ZFS, lanzaboote, TPM2, headscale mesh, ISO flow —
see that workspace's NOTES.md).

```text
◇  v1.1.0 (later)
│
│ ── milestone: first-node-intranet (os#2) ──
│ ○  test(vm): multi-node fleet — underlay server + overlay agent join
│ ○  feat(k3s): cert-manager + ExternalDNS (Cloudflare, DNSEndpoint CRD)
│ ○  feat(k3s): overlay agent role — tailnet-gated join to first node
│ ○  feat(k3s): first-node underlay role — LAN boot, no tailscale ordering
│
◇  v1.0.0 (next)
│
│ ○  test(e2e): install template-instantiated config in a VM end to end
│ ○  docs(install): baremetal quickstart — ISO to first rebuild
│ ○  feat(templates): sops secrets repo template with age host-key enrollment
│ ○  feat(templates): ks-config consumer flake template (nix flake init)
│ ○  refactor(secrets)!: replace agenix with sops-nix
│ ○  fix(installer): stabilize nixos-anywhere baremetal path (disko, LUKS/TPM)
│ ○  test(harness): canokey-backed FIDO2 LUKS unlock exercised end to end
│ ○  feat(installer): import ISO + offline-install flow from keystone-systems
│ ○  docs(milestones): define v1 scope — baremetal + templating; terminal/desktop live elsewhere
├─╯
●  848008e  feat(harness): install realization — disko image boot with TPM2/FIDO2 emulation
●  f2126a8  feat(fleet): unified vm/machine fleet harness — mkFleet, fleetMeta, ks-fleet runner
●  9cf9864  chore!: reset repository to an empty root for the KS OS v1 rebuild
◇  (archive boundary — v1.0.0-rc.4 and all prior history on archive/*)
```

Notes:
- v1.1's `first-node-intranet` milestone implements
  [os#2](https://git.ncrmro.com/ks.systems/os/issues/2): underlay-first K3s
  server, tailnet-gated agents, cert-manager/ExternalDNS — resolving the
  Headscale-in-K3s circular dependency per
  `~/notes/wiki/research/headscale-k3s-bootstrap-relocation.md`. Its
  multi-node VM test rides the fleet harness imported in v1 — that is why
  the harness import is a v1 commit, not deferred.
- The harness gains a third realization tier, `install`: instead of the
  fast vmVariant (which swaps out storage/boot), it boots the host's real
  disko-built disk image (`system.build.vmWithDisko`) under QEMU with
  swtpm attached (TPM2 enrollment/auto-unlock) and canokey-qemu (emulated
  FIDO2 token) — so users can test yubikey/TPM LUKS unlock flows in a VM
  before touching hardware. disko.tests bootCommands (already present in
  delltop's disk-config) are the assertion hook. Landed in 848008e
  (install + swtpm verified on ks-demo-luks: guest sees tpm0, LUKS unlocks,
  boots to login; canokey wiring present but needs a canokey-enabled qemu
  build and an end-to-end unlock test — the remaining ○).
- Terminal and desktop never enter the rebuilt os repo; the new repos
  import from `~/repos/keystone-systems/{terminal,desktop}` and the
  archive/* branches instead (see their sections).
- Secrets stack: agenix is replaced with sops-nix. The migration commit is
  breaking for consumers (agenix flake input and `age.secrets.*` options go
  away; hosts re-key to sops with age host keys). ncrmro/ks-config and its
  private secrets repo migrate alongside; the CI fixture pattern from
  ks-config#1 (inert override input for PR builds) carries over to sops.
- The ks-config template generalizes what ncrmro/ks-config#1 (Delltop +
  dotfiles refactor) is proving out on real hardware; land that PR first as
  the reference consumer, then update it to consume hterm + desktop inputs
  and the sops secrets layout.
- Former M9 items outside the new scope move to the M9 tracker's v1.1
  section rather than blocking v1.

## ks.systems/hterm — terminal modules, v0.1.0

Standalone terminal surface (shell, editor, AI, git, projects tooling).
Repo does not exist yet; the seed is the already-split
`~/repos/keystone-systems/terminal` flake, with the pre-reset os tree
(`archive/2026-07-27-Q3-main`) as the richer migration source.

```text
◇  v0.1.0 (next)
│
│ ○  chore(release): adopt release-please, 0.1.0 baseline
│ ○  docs: standalone usage as a flake input consumed by ks-config
│ ○  feat: expose terminal modules as flake outputs with own namespace
│ ○  chore: import keystone-systems/terminal flake as the seed
├─╯
◇  (no history — new repo)
```

## ks.systems/desktop — desktop modules, v0.1.0

Standalone desktop surface (Hyprland, greetd session path, walker, project
menus). Seed: `~/repos/keystone-systems/desktop` (already carries the
stow/dotfiles link engine and theming docs), pre-reset os tree as migration
source. Depends on hterm only if shared lib code emerges — prefer
duplicating small helpers over a cross-repo dep at 0.1.0.

```text
◇  v0.1.0 (next)
│
│ ○  chore(release): adopt release-please, 0.1.0 baseline
│ ○  docs: standalone usage as a flake input consumed by ks-config
│ ○  feat: expose desktop modules as flake outputs with own namespace
│ ○  chore: import keystone-systems/desktop flake as the seed
├─╯
◇  (no history — new repo)
```

Shared milestone across os/hterm/desktop:
`── milestone: module-split ──` — done when ks-config builds green consuming
os + hterm + desktop as three flake inputs and the rebuilt os ships neither
module tree.

## ks.systems/vega

Stabilize what runs today, close the three live issues, then cut 0.1.0.

```text
◇  v0.1.0 (next)
│
│ ○  chore(release): adopt release-please, 0.1.0 baseline
│ ○  chore(repo): complete canonical-repository migration (#38)
│ │ ◉  ci(link): deploy approved revisions to Ocean via Forgejo OIDC  PR #37 ci/link-ocean-deploy → main · draft (#36)
│ ├─╯
│ ○  fix(web): restore host web process health — /healthz 502 (#40)
├─╯
●  e500c55  chore(agent): pin Channels streaming head c9b4b30
●  49fd83c  fix(deploy): pin streaming Channels head and invalidate stale caches
◇  (no prior release)
```

Note: the primary checkout has uncommitted edits to
`.agents/agents/{vega,channels-relay}/agent.md` and
`deploy/link/{vega,channels-relay}.yaml` — commit or fold into #36/#37
before cutting.

## ks.systems/zejent

Already functional (3 commits); 0.1.0 is release plumbing plus docs.

```text
◇  v0.1.0 (next)
│
│ ○  docs: usage and versioning policy
│ ○  chore(release): adopt release-please and registry publish CI
├─╯
●  40ce6af  fix(image): ship /etc/passwd and /etc/group as regular files
●  015ee09  feat: label image with OCI source for ghcr repo linking
●  f6fca27  feat: graduate zejent from podman-nix-zellij-session spike
◇  (no prior release)
```

## ks.systems/operator

Scope is answered by the org-control-plane research
(`~/notes/wiki/research/organization-control-plane-operator.md`): a
Kubernetes operator provisioning per-organization boundaries — Headscale
tailnet, Forgejo, Stalwart mail, scoped K8s access, OpenBao secrets,
hardware-key-backed humans, and agent identities (Vega). 0.1.0 takes the
narrowest vertical slice: the per-organization Headscale instance, since
os#2's first-node foundation is what makes that workload bootstrappable.

```text
◇  v0.1.0 (next)
│
│ ○  test(e2e): reconcile an Organization on a first-node dev cluster
│ ○  feat: Organization CRD + per-org Headscale instance reconciler
│ ○  chore: scaffold operator (flake, CI, release-please)
│ ○  docs: adopt org-control-plane research as scope; define Organization CRD
├─╯
●  09d9745  Initial commit
◇  (no prior release)
```

Depends on os v1.1's `first-node-intranet` milestone for a cluster to
reconcile against — sequence operator 0.1.0 after os#2's substrate exists
(the fleet-harness VM cluster is the dev target in the meantime).

## ks.systems/wiki

No commits yet (`main` has never been pushed). 0.1.0 is the structure plus a
seeded knowledge base.

```text
◇  v0.1.0 (next)
│
│ ○  chore(release): adopt release-please
│ ○  docs: seed concepts, projects, and people from existing notes
│ ○  chore: scaffold wiki structure and AGENTS.md
├─╯
◇  (no history)
```

---

Out-of-org but coupled: `ncrmro/ks-config#1` (Delltop, stow dotfiles) is the
reference consumer proving the os v1 baremetal path — its landing precedes
the ks-config template commit above, and ks-config is the first consumer of
the hterm and desktop flake inputs.

Steering inputs binding this plan together:

- [os#2 — first-node intranet foundation](https://git.ncrmro.com/ks.systems/os/issues/2):
  the K3s-first substrate contract (underlay-first server, overlay agents,
  cert-manager/ExternalDNS). Drives os v1.1 and unblocks operator 0.1.0.
- `~/notes/wiki/research/headscale-k3s-bootstrap-relocation.md` (2026-07-26):
  feasibility of bootstrapping K3s before the tailnet exists and relocating
  the Headscale pod — the design os#2's required behavior encodes.
- `~/notes/wiki/research/organization-control-plane-operator.md`
  (2026-07-26): multi-tenant org control plane — the operator repo's scope.
- `~/repos/keystone-systems/NOTES.md` (2026-07-11): fleet-in-VMs harness and
  repo-split state — migration source for os v1, hterm, and desktop seeds.
