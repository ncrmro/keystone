# REQ-009: Notes Sync

Home Manager module (`keystone.notes`) for managing a user's notes repository
with automated git synchronization. Portable across NixOS and macOS.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Configuration

**REQ-009.1** The module MUST expose `keystone.notes.enable` (bool, default
`false`) to activate notes management.

**REQ-009.2** The module MUST expose `keystone.notes.repo` (string) for the
git remote URL. This option is REQUIRED when `enable` is `true`.

**REQ-009.3** The module MUST expose `keystone.notes.path` (path, default
`~/notes`) for the local checkout location.

**REQ-009.4** The module MUST expose `keystone.notes.syncInterval` (string,
default `*:0/5`) as a systemd `OnCalendar` expression controlling sync
frequency.

### First-Boot Clone

**REQ-009.5** The module MUST provide a systemd user oneshot service that
clones `keystone.notes.repo` to `keystone.notes.path` if the directory does
not already exist.

**REQ-009.6** The clone service MUST depend on an active SSH agent so that
git authentication succeeds without user interaction.

**REQ-009.7** The clone service MUST run before the first sync timer fires.

### Sync Script

**REQ-009.8** The module MUST install a sync script as a Nix derivation that
performs the following sequence: fetch from remote, detect local and upstream
changes, stage and commit local changes, rebase onto upstream, push.

**REQ-009.9** Automatic commits MUST use the message format
`vault sync: YYYY-MM-DD HH:MM:SS`.

**REQ-009.10** The sync script MUST detect rebase conflicts, abort the rebase
to leave the repository in a clean state, write a conflict marker file, and
exit with a non-zero status.

**REQ-009.11** The sync script MUST use atomic directory-based locking
(`mkdir`) to prevent concurrent runs. A stale lock (process no longer running)
SHOULD be automatically cleaned up.

**REQ-009.12** The sync script MUST write per-run log files and structured
JSON metadata (timestamp, exit code, duration) to a logs directory.

**REQ-009.13** The sync script MUST rotate logs, keeping only the last N runs
(default 10). Both the `.log` and `.json` files for a run MUST be rotated
together.

### Integration

**REQ-009.14** The sync script MUST be a standalone derivation so that both
human Home Manager profiles and OS agent profiles (see SPEC-007) can import
it without duplicating logic.

**REQ-009.15** SPEC-007 agent-space sync SHOULD adopt this shared sync script
in place of its current inline implementation.

### Portability

**REQ-009.16** The module MUST NOT depend on NixOS-specific features. It MUST
use Home Manager primitives (systemd user services on Linux, launchd on
macOS in the future).

**REQ-009.17** The module MAY provide launchd plist generation for macOS
support as a future extension.
