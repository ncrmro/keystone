---
title: Desktop VM development
description: Rootless build-vm workflow for Keystone Desktop iteration, capture, and demo publishing
---

# Desktop VM development

Use the rootless `build-vm` workflow for day-to-day Keystone Desktop work.

## Standard loop

Start the desktop VM in the background:

```bash
./bin/build-vm desktop --background
```

Open a shell into the guest:

```bash
./bin/build-vm desktop --ssh
```

Capture a desktop screenshot:

```bash
./bin/dev-vm-capture screenshot
```

Capture terminal evidence as text plus PNG:

```bash
./bin/dev-vm-capture terminal
```

Publish the artifact set to R2:

```bash
export KEYSTONE_DEMO_R2_BUCKET=keystone-demo
export KEYSTONE_DEMO_PUBLIC_BASE_URL=https://demo-assets.example.com
./bin/demo-artifact-publish artifacts/demos/2026-03-31_12-00-00
```

Stop the VM when finished:

```bash
./bin/build-vm desktop --stop
```

## Commands

- `./bin/build-vm desktop --background` builds the VM, starts it as a background process, and waits for SSH on `localhost:2223`
- `./bin/build-vm desktop --ssh` opens an SSH shell to the running guest
- `./bin/build-vm desktop --status` prints PID, SSH target, log path, and disk path
- `./bin/dev-vm-capture screenshot` saves `desktop.png` under `artifacts/demos/<timestamp>/`
- `./bin/dev-vm-capture terminal` saves `terminal.txt`, `terminal.png`, and `metadata.json`
- `./bin/demo-artifact-publish <path>` uploads a file or artifact directory with `wrangler`, then writes `published.json` and `published.md`

## Why this path

- `build-vm` works without sudo on the local host
- It is fast enough for desktop iteration
- Screenshot capture happens inside the guest via the active Wayland session, then copies back to the repo
- Terminal evidence is reproducible because it is captured as text and rendered to PNG locally

## Tradeoffs

- Use microvm for TPM-focused Tier 1 testing, not for Keystone Desktop iteration
- Use libvirt for full-fidelity manual testing when you need that stack specifically
- Do not use Git LFS as the default artifact path for iterative demo evidence
