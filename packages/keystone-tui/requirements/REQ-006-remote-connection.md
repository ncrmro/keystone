# REQ-006: Remote Connection

This document defines requirements for connecting to a Keystone ISO
installer and deploying the generated configuration. Phase 3 — stub for
future implementation.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

**REQ-006.1** The TUI SHOULD detect Keystone ISO installer instances on the
local network via mDNS/Avahi.

**REQ-006.2** The TUI MUST accept a target IP address for manual connection
when auto-detection is unavailable.

**REQ-006.3** The TUI MUST deploy the generated configuration to the target
machine via `nixos-anywhere --flake .#<hostname> root@<ip>`.

**REQ-006.4** The TUI SHOULD auto-detect local SSH keys and offer them for
the deployment connection.

**REQ-006.5** The TUI MUST display deployment progress and surface errors
from `nixos-anywhere` to the user.
