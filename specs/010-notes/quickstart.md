# Quickstart: Agent Cron Jobs

## Installation

1.  **Install the Keystone Agent**:
    ```bash
    nix profile install .#keystone-notes
    ```

2.  **Initialize your Notes Repo**:
    Create a `.keystone/jobs.toml` file in the root of your notes repository.

    ```toml
    [global]
    backend = "anthropic"

    [[jobs]]
    name = "sync"
    schedule = "*/10 * * * *"
    script = "builtin:sync"
    ```

## Usage

1.  **Trust Scripts**:
    If you have custom scripts, you must allow them first.
    ```bash
    keystone-notes allow .
    ```

2.  **Install Jobs**:
    Register your jobs with the system scheduler.
    ```bash
    keystone-notes install-jobs
    ```

3.  **Manual Run**:
    Test a job immediately.
    ```bash
    keystone-notes run sync
    ```

## Logs

View logs for your jobs via `journalctl`:
```bash
journalctl --user -u keystone-job-*.service
```
