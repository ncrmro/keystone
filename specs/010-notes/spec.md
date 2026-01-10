# Feature Specification: Notes

**Feature Branch**: `010-notes`
**Created**: 2026-01-10
**Status**: Draft
**Input**: User description: "A a user I have a git repo of notes, I would like to run various cron jobs such as pulling/pushing/syncing etc. I would like to be able to run claude/gemini-cli cron taks via shell scripts that perform certain tasks (get the status of other git repo projects etc) before calling the agent to do something with tasks, eg what was completed yesterday, next tasks etc, status updates for specific projects. Another example might be choosing a movies to watch based on an api that shows vailabl emovies etc, with a summery of why they are interesting. Preferably this runs on a local opensource model"

## Clarifications

### Session 2026-01-10

- Q: Where should the `AgentJob` definitions be stored and managed? → A: Configuration file in the notes repository (e.g., `.keystone/jobs.toml`).
- Q: How should the system select which notes/data to send to the agent to avoid context overflow? → A: Send content from the last X commits and pull requests matching a regex pattern.
- Q: How should the system handle the security risk of executing scripts or accessing URLs defined in the user's notes repo? → A: Allow scripts in notes repo but require a manual "allowlist" approval step (like direnv).

## User Scenarios & Testing

### User Story 1 - Automated Note Synchronization (Priority: P1)

The user wants their notes repository to stay in sync across devices without manual intervention.

**Why this priority**: Foundation for all other tasks; ensures the agent operates on the latest data and results are shared.

**Independent Test**: Can be tested by making a change on a remote and verifying it appears locally automatically, and vice versa.

**Acceptance Scenarios**:

1. **Given** a notes repository with remote changes, **When** the sync job runs, **Then** the local repository is updated (pulled) successfully.
2. **Given** local changes in the notes repository, **When** the sync job runs, **Then** the changes are committed and pushed to the remote.
3. **Given** conflicting changes, **When** the sync job runs, **Then** the system attempts a safe merge/rebase or notifies the user (fail-safe).

---

### User Story 2 - Daily Task Analysis & Summary (Priority: P1)

The user wants an AI agent to review their recent notes/tasks and generate a summary of progress and upcoming priorities.

**Why this priority**: Delivers the core "smart agent" value proposition described in the request.

**Independent Test**: Can be tested by creating a dummy "Yesterday" note and verifying a "Today" summary is generated.

**Acceptance Scenarios**:

1. **Given** a set of notes describing completed tasks from yesterday, **When** the daily summary job runs, **Then** a new note section is created summarizing what was achieved.
2. **Given** a list of outstanding tasks, **When** the job runs, **Then** a "Next Steps" list is generated/updated.
3. **Given** status updates in other project repos, **When** the job runs, **Then** these updates are aggregated into the daily summary.

---

### User Story 3 - Extensible Data Feeds (Movies Example) (Priority: P2)

The user wants to inject external data (like movie availability) into their notes, summarized by an agent.

**Why this priority**: Demonstrates the extensibility of the system to arbitrary APIs and data sources.

**Independent Test**: Can be tested by mocking an external API response and verifying the agent generates a recommendation note.

**Acceptance Scenarios**:

1. **Given** an external source of data (e.g., a movie list API), **When** the "Movie Night" job runs, **Then** the agent fetches the data, selects interesting items based on criteria, and writes a summary to the notes.

---

### User Story 4 - Local Model Execution (Priority: P2)

The user prefers to run these agent tasks using a local open-source model for privacy and cost control.

**Why this priority**: Explicit user preference/constraint ("Preferably this runs on a local opensource model").

**Independent Test**: Can be tested by disconnecting internet (simulating local-only) or configuring the system to use a local endpoint and verifying tasks still complete.

**Acceptance Scenarios**:

1. **Given** a configured local model (e.g., via Ollama/LocalAI), **When** an agent job runs, **Then** the inference is performed locally without calling external APIs (Claude/Gemini).
2. **Given** the local model is unavailable, **When** a job runs, **Then** the system fails gracefully or falls back to a configured cloud provider (if allowed).

### Edge Cases

- What happens when the internet is down during a sync/fetch? (Job should retry or fail silently without corruption).
- How does the system handle an API failure (e.g., Movie DB down)? (Agent should report the error in the note or skip the section).
- What happens if the local model runs out of memory? (Job failure should be logged).
- What if the notes repo is in a "dirty" state (uncommitted changes) when a job runs? (Sync job handles it, other jobs might need to stash or work on top).

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide a mechanism to schedule shell scripts to run at defined intervals (cron/timers).
- **FR-002**: System MUST provide a robust "sync" script for Git repositories that handles pull, commit, and push operations.
- **FR-003**: System MUST support defining "Agent Jobs" which consist of:
    1.  Data gathering (shell script/API call).
    2.  Prompt construction (combining data + instructions).
    3.  Agent execution (sending prompt to model).
    4.  Result handling (appending/writing to notes).
- **FR-004**: System MUST support multiple AI backends, specifically:
    1.  Cloud: Anthropic (Claude), Google (Gemini).
    2.  Local: Generic OpenAI-compatible local endpoint (e.g., Ollama, LocalAI).
- **FR-005**: System MUST allow users to configure which model/backend to use per job or globally.
- **FR-006**: System MUST allow jobs to access other git repositories (read-only) to gather status context.
- **FR-007**: System MUST load job configurations from a `.keystone/jobs.toml` file located in the root of the notes repository.
- **FR-008**: System MUST filter agent context by including content only from the last X commits and pull requests matching a user-defined regex pattern.
- **FR-009**: System MUST implement a trust mechanism for job scripts; scripts defined in the notes repository MUST be manually authorized by the user before execution (similar to `direnv allow`).

### Key Entities

- **AgentJob**: Configuration for a scheduled task (Script Path, Schedule, Model Config, Context Filters, Trust Status).
- **NoteRepo**: The target repository for reading context and writing summaries.
- **BackendConfig**: Connection details for AI models (API Key/Endpoint URL).

## Success Criteria

### Measurable Outcomes

- **SC-001**: "Sync" job successfully synchronizes changes within 1 minute of scheduled time in 99% of runs.
- **SC-002**: Daily summary is generated and present in notes every morning (e.g., by 8 AM) without user action.
- **SC-003**: System supports switching between Cloud and Local models by changing a single configuration value.
- **SC-004**: Adding a new type of job (e.g., "Weather Report") requires only adding a script and schedule entry, no core code changes.
