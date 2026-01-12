use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "keystone-notes")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
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
