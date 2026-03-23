# REQ-024: Perception Layer

Adds document, voice, and visual perception capabilities to Keystone OS
agents. Agents gain the ability to parse PDFs to structured markdown with
citable source locations, record and transcribe voice locally, search photos
and screenshots by face or text content, sync desktop screenshots to Immich
for ML indexing, link recognized people to CardDAV contacts, and reconstruct
activity summaries that auto-sync into notes.

Press release: https://github.com/ncrmro/keystone/issues/181

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a keystone operator, I want my OS agents to process documents, voice
recordings, and photos on my local hardware so that I can search, extract,
and summarize unstructured data without sending anything to cloud services.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Agent Desktop                                │
│  labwc + wayvnc                                                     │
│                                                                     │
│  ┌──────────────┐    inotify/timer    ┌───────────────────────┐     │
│  │  Screenshots  │ ─────────────────► │  screenshot-sync      │     │
│  │  (PNG files)  │                    │  (systemd user svc)   │     │
│  └──────────────┘                     └───────────┬───────────┘     │
│                                                   │ Immich API      │
│  ┌──────────────┐    ┌──────────────┐             │                 │
│  │  Voice        │───►│  whisper.cpp  │             │                 │
│  │  recordings   │    │  (local STT) │             │                 │
│  └──────────────┘    └──────┬───────┘             │                 │
│                             │ .txt transcript      │                 │
│  ┌──────────────┐    ┌──────┴───────┐             │                 │
│  │  PDF files    │───►│  Docling     │             │                 │
│  │              │    │  (PDF→MD)    │             │                 │
│  └──────────────┘    └──────┬───────┘             │                 │
│                             │ .md + bbox metadata  │                 │
│                             ▼                      ▼                 │
│                     ┌─────────────────────────────────────┐         │
│                     │  perception-processor                │         │
│                     │  (systemd user service, timer)       │         │
│                     │                                     │         │
│                     │  - Collects transcripts, PDFs, photo │         │
│                     │    search results                    │         │
│                     │  - Queries Immich for face/text      │         │
│                     │  - Links faces → cardamum contacts   │         │
│                     │  - Writes structured summaries       │         │
│                     │  - Syncs into notes/ via repo-sync   │         │
│                     └─────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ Tailscale
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Server (ocean)                               │
│                                                                     │
│  ┌───────────────────────────┐    ┌────────────────────────────┐   │
│  │  Immich (photos.domain)   │    │  Stalwart (mail.domain)    │   │
│  │  port 2283                │    │  CardDAV contacts           │   │
│  │                           │    │                            │   │
│  │  ML worker:               │    │  cardamum CLI reads/writes │   │
│  │  - Face recognition       │    │  vCards                    │   │
│  │  - OCR text extraction    │    └────────────────────────────┘   │
│  │  - CLIP image search      │                                     │
│  └───────────────────────────┘                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Affected Modules

- `modules/os/agents/types.nix` — new `perception` option group in agent submodule
- `modules/os/agents/perception.nix` — **new**: systemd services for screenshot-sync and perception-processor
- `modules/os/agents/scripts/screenshot-sync.sh` — **new**: inotify/timer watcher that uploads screenshots to Immich
- `modules/os/agents/scripts/perception-processor.sh` — **new**: collects outputs, queries Immich, links contacts, writes summaries
- `modules/os/agents/default.nix` — import perception.nix
- `modules/terminal/perception.nix` — **new**: CLI tools (docling, whisper.cpp, immich-search) in home-manager
- `modules/terminal/default.nix` — import perception.nix
- `packages/screenshot-sync/` — **new**: screenshot → Immich upload script
- `packages/immich-search/` — **new**: CLI wrapper for Immich search API (face, text, smart)
- `packages/perception-processor/` — **new**: activity summary builder
- `flake.nix` — add Docling, whisper.cpp packages; expose new packages

## Requirements

### PDF Processing

**REQ-024.1** The terminal module MUST provide a `docling` package capable of
converting PDF files to markdown.

**REQ-024.2** The PDF-to-markdown conversion MUST preserve document structure
(headings, tables, lists) in the output markdown.

**REQ-024.3** The conversion MUST produce bounding box metadata alongside the
markdown output so that each extracted element (paragraph, table cell, line)
can be traced to a specific page and region in the source PDF.

**REQ-024.4** The bounding box metadata MUST be stored in a sidecar JSON file
with the same basename as the output markdown (e.g., `document.md` and
`document.bbox.json`).

**REQ-024.5** Scanned PDFs (image-only pages) MUST be processed with OCR
before markdown conversion. Native text PDFs MUST be parsed directly without
OCR.

**REQ-024.6** The `docling` package SHOULD support GPU acceleration when
available but MUST fall back to CPU-only processing.

### Voice Recording and Transcription

**REQ-024.7** The terminal module MUST provide a `whisper.cpp` (or equivalent
local speech-to-text) package for audio transcription.

**REQ-024.8** Transcription MUST run entirely on local hardware. Audio data
MUST NOT be sent to any external service.

**REQ-024.9** The transcription tool MUST accept common audio formats (WAV,
MP3, OGG, M4A) as input and produce a plain text transcript as output.

**REQ-024.10** The transcription tool SHOULD produce timestamped segments
(e.g., `[00:01:23] sentence text`) to enable linking transcript sections
to audio positions.

**REQ-024.11** The transcription tool SHOULD support GPU acceleration when
available but MUST fall back to CPU-only processing.

**REQ-024.12** A voice recording helper script MAY be provided that uses
PipeWire to capture microphone input and save to a timestamped WAV file in
a configurable directory.

### Screenshot Syncing to Immich

**REQ-024.13** Each agent with `perception.enable = true` and
`desktop.enable = true` MUST run a `screenshot-sync` systemd user service
that watches the agent's screenshot directory for new PNG files.

**REQ-024.14** New screenshots MUST be uploaded to the Immich instance via
its API within the sync interval.

**REQ-024.15** The sync service MUST use a configurable timer interval,
defaulting to `*:0/5` (every 5 minutes).

**REQ-024.16** Uploaded screenshots MUST be tagged in Immich with the agent
name and host name for filtering.

**REQ-024.17** The sync service MUST track which files have been uploaded
(e.g., via a state file) to avoid duplicate uploads.

**REQ-024.18** The Immich API key MUST be managed as an agenix secret
(`agent-{name}-immich-api-key`).

### Photo and Screenshot Search

**REQ-024.19** The terminal module MUST provide an `immich-search` CLI tool
that queries the Immich API for assets matching a search query.

**REQ-024.20** The `immich-search` tool MUST support search by:
- Face/person name (using Immich's face recognition index)
- Text content (using Immich's OCR/CLIP index)
- Date range
- Asset type (photo, screenshot, video)

**REQ-024.21** The tool MUST output results as structured JSON containing
asset ID, filename, date, thumbnail URL, and matched metadata.

**REQ-024.22** The tool MUST authenticate via the Immich API key from the
agent's agenix secret.

**REQ-024.23** Immich's ML features (face recognition, CLIP, OCR) MUST be
enabled on the server. The `immich.nix` service module SHOULD emit a warning
if `perception` is enabled on any agent but Immich ML is not configured.

### Contact Linking

**REQ-024.24** The perception processor MUST be able to query Immich for
recognized face clusters and match them against CardDAV contacts via the
`cardamum` CLI.

**REQ-024.25** Matching SHOULD use the contact's display name and any
photo-tagged name from Immich. Exact matching MUST be tried first; fuzzy
matching MAY be used as a fallback.

**REQ-024.26** When a face cluster matches a contact, the perception
processor SHOULD update the Immich person name to match the contact's
canonical display name.

**REQ-024.27** The contact linking step MUST NOT create or modify CardDAV
contacts automatically. It MUST only read contacts for matching and update
Immich person labels.

### Activity Reconstruction and Notes Sync

**REQ-024.28** Each agent with `perception.enable = true` MUST run a
`perception-processor` systemd user service on a configurable timer,
defaulting to `*:0/30` (every 30 minutes).

**REQ-024.29** The perception processor MUST scan for new inputs since the
last run:
- PDF markdown outputs and their bounding box metadata
- Voice transcripts
- Immich search results (recent screenshots, tagged photos)

**REQ-024.30** The processor MUST produce a structured activity summary in
markdown format, suitable for inclusion in the agent's notes directory.

**REQ-024.31** The activity summary MUST include citations. For PDF-sourced
data, citations MUST reference the source file, page number, and line or
bounding box region. For voice transcripts, citations MUST reference the
audio file and timestamp.

**REQ-024.32** The activity summary MUST be written to the agent's notes
directory (e.g., `notes/perception/YYYY-MM-DD.md`) and synced via the
existing `repo-sync` service.

**REQ-024.33** The processor MAY use the local Ollama instance (if
`keystone.os.services.ollama.enable = true`) to generate natural-language
summaries from structured extraction outputs.

### Configuration

**REQ-024.34** The agent submodule MUST expose options at
`keystone.os.agents.<name>.perception`.

```nix
keystone.os.agents.drago = {
  perception = {
    enable = false;               # Enable perception layer

    pdf = {
      enable = true;              # PDF parsing (requires docling)
      inputDir = null;            # Watch directory (default: ~/documents/inbox)
      outputDir = null;           # Markdown output (default: ~/documents/parsed)
    };

    voice = {
      enable = true;              # Voice transcription (requires whisper.cpp)
      inputDir = null;            # Watch directory (default: ~/voice/inbox)
      outputDir = null;           # Transcript output (default: ~/voice/transcripts)
      model = "base";            # Whisper model size (tiny, base, small, medium, large)
    };

    screenshots = {
      enable = true;              # Screenshot sync to Immich
      syncOnCalendar = "*:0/5";  # Sync interval
    };

    search = {
      enable = true;              # Immich search CLI
    };

    contacts = {
      enable = true;              # Face → contact linking
    };

    processor = {
      enable = true;              # Activity reconstruction
      onCalendar = "*:0/30";     # Processing interval
      useOllama = false;         # Use Ollama for natural-language summaries
    };
  };
};
```

**REQ-024.35** When `perception.enable` is true, the sub-options (`pdf`,
`voice`, `screenshots`, `search`, `contacts`, `processor`) MUST default to
enabled. Individual sub-options MAY be disabled to exclude specific
capabilities.

**REQ-024.36** The terminal module MUST expose a
`keystone.terminal.perception.enable` option that installs the CLI tools
(docling, whisper.cpp, immich-search) into the user's environment.

### Integration

**REQ-024.37** The screenshot-sync service MUST coexist with the existing
screenshot tool (`keystone-screenshot`). Screenshots are produced by the
existing tool; the sync service only handles upload.

**REQ-024.38** The perception-processor MUST coexist with the existing
`agent-{name}-task-loop` service. They are complementary — the task loop
executes tasks, the perception processor ingests media.

**REQ-024.39** The perception module MUST integrate with the existing
`repo-sync` notes service for syncing activity summaries to the notes
repository.

**REQ-024.40** The PDF and voice processing tools MUST be available as
standalone CLI commands so that agents can invoke them from task loop
scripts, not only via the background processor.

### Security

**REQ-024.41** All media processing (PDF parsing, OCR, voice transcription,
image search) MUST run on local hardware. No data MUST be transmitted to
external services.

**REQ-024.42** Immich API keys MUST be stored as agenix secrets and MUST NOT
appear in Nix store paths or configuration files.

**REQ-024.43** The perception processor MUST NOT modify or delete source
files (PDFs, audio recordings, screenshots). It operates read-only on
inputs and write-only to output directories.

**REQ-024.44** The contact linking step MUST NOT create, modify, or delete
CardDAV contacts. It MUST only read contacts for matching purposes.

## Edge Cases

- **Immich offline**: Screenshot sync buffers locally and retries on next
  timer tick. The state file tracks pending uploads.
- **No Ollama available**: The processor falls back to structured extraction
  only — no natural-language summaries. This is the default (`useOllama = false`).
- **Large PDFs**: Docling processes pages sequentially. For PDFs over 100
  pages, the processor SHOULD split into batches to avoid memory pressure.
- **No faces recognized**: Contact linking is a no-op when Immich has no
  face clusters. The processor MUST NOT fail.
- **Agent without desktop**: If `desktop.enable = false`, screenshot sync is
  automatically disabled. PDF and voice processing still function.
- **Multiple agents on same host**: Each agent has its own screenshot
  directory, Immich API key, and processing state. No shared state.
