# REQ-004: User Input

This document defines requirements for the TUI interactive interface.
Phase 2 — stub for future implementation.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

**REQ-004.1** The TUI MUST run on Linux and macOS. Windows support MAY be
added as a stretch goal.

**REQ-004.2** The TUI MUST collect all REQUIRED inputs from REQ-002 via
interactive prompts with sensible defaults.

**REQ-004.3** The TUI SHOULD auto-detect SSH public keys from
`~/.ssh/*.pub` and offer them for selection.

**REQ-004.4** The TUI SHOULD detect connected hardware security keys
(YubiKey, SoloKey) and offer to configure `keystone.os.hardwareKey`.

**REQ-004.5** The TUI MUST support a non-interactive JSON mode where all
inputs are provided via a JSON file or stdin, enabling scripted deployments.

**REQ-004.6** The TUI MUST validate inputs before generating config (e.g.,
hostId is 8 hex chars, at least one device, at least one user).
