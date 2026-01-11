# Data Model: Notes Agent (Rust)

## Configuration Schema (`.keystone/jobs.toml`)

The `jobs.toml` file is the source of truth for all scheduled agent tasks.

```toml
# Global settings
[global]
backend = "claude-code" # Default backend
model = "claude-3-5-sonnet-latest"
use_mcp = true

# Backend configuration
[backends.claude-code]
binary_path = "claude"

[backends.ollama]
base_url = "http://localhost:11434"
model = "llama3"

# Job Definitions
[[jobs]]
name = "daily-summary"
schedule = "0 8 * * *" # Cron expression
script = "scripts/summarize.sh"
backend = "claude-code"
context_mode = "diff" # "diff" or "files"
context_lookback = "24h" # Duration string or "commits:5"
```

## Rust Structs

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct Config {
    pub global: GlobalConfig,
    pub backends: Option<HashMap<String, BackendConfig>>,
    #[serde(default)]
    pub jobs: Vec<JobConfig>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct GlobalConfig {
    pub backend: String,
    pub model: Option<String>,
    #[serde(default)]
    pub use_mcp: bool,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(tag = "type")]
pub enum BackendConfig {
    #[serde(rename = "claude-code")]
    ClaudeCode { binary_path: Option<String> },
    #[serde(rename = "ollama")]
    Ollama { base_url: String, model: String },
    // ...
}

#[derive(Debug, Deserialize, Serialize)]
pub struct JobConfig {
    pub name: String,
    pub schedule: String,
    pub script: String,
    pub backend: Option<String>,
    pub context_mode: Option<ContextMode>,
    pub context_lookback: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ContextMode {
    Diff,
    Files,
}

// Trust Store (~/.local/share/keystone/script_allowlist.json)
#[derive(Debug, Deserialize, Serialize)]
pub struct TrustStore {
    pub scripts: HashMap<String, TrustEntry>, // Key: Absolute Path
}

#[derive(Debug, Deserialize, Serialize)]
pub struct TrustEntry {
    pub hash: String, // SHA-256
    pub allowed_at: DateTime<Utc>,
}
```

## CLI Commands (`clap`)

```rust
#[derive(Parser)]
#[command(name = "keystone-notes")]
pub enum Cli {
    /// Install/Update systemd user units from jobs.toml
    InstallJobs {
        #[arg(short, long, default_value = ".")]
        path: PathBuf,
    },
    /// Run a specific job manually
    Run {
        job_name: String,
    },
    /// Approve a script or all scripts in a directory
    Allow {
        path: PathBuf,
    },
    /// Run git sync (pull --rebase -> commit -> push)
    Sync,
    /// Open today's daily note in $EDITOR
    Daily,
    /// Launch the TUI dashboard
    Tui,
}
```

## File Locations

- **Config**: `.keystone/jobs.toml` (in user repo)
- **Allowlist**: `~/.local/share/keystone/script_allowlist.json`
- **Systemd Units**: `~/.config/systemd/user/keystone-job-<slug>.service`
- **Logs**: `~/.local/share/keystone/agent.log`