# REQ-005: Publishing

This document defines requirements for committing and publishing the
generated configuration. Phase 2 — stub for future implementation.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

**REQ-005.1** The TUI MUST initialize a git repository in the output
directory and create an initial commit with the generated files.

**REQ-005.2** The TUI SHOULD offer to create a private GitHub repository
via `gh repo create` and push the initial commit.

**REQ-005.3** The TUI MUST configure the git remote with SSH URL format
(`git@github.com:owner/repo.git`).

**REQ-005.4** The TUI MUST warn the user if any generated file contains a
plaintext password (`initialPassword`) and recommend switching to
`hashedPassword` before publishing.

**REQ-005.5** The TUI MUST NOT commit files that contain secrets (e.g.,
private keys, tokens). Age-encrypted secrets MAY be committed.
