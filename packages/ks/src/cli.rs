//! CLI argument parsing (clap definitions).

use clap::{Args, Parser, Subcommand};

use crate::cmd::{photos::PhotosCommand, screenshots::ScreenshotsCommand};

/// Keystone CLI/TUI — NixOS infrastructure configuration and management.
#[derive(Parser)]
#[command(name = "ks", version, about)]
pub struct Cli {
    /// Render a single screen to stdout as ANSI and exit.
    #[arg(long, value_name = "SCREEN")]
    pub screenshot: Option<String>,

    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand)]
pub enum Command {
    /// Generate a new Keystone config from a template.
    Template {
        #[arg(long)]
        github_username: Option<String>,

        #[arg(long, short)]
        output: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Build home-manager profiles (or full NixOS systems with --lock).
    Build {
        #[arg(long)]
        lock: bool,

        #[arg(long)]
        user: Option<String>,

        #[arg(long)]
        all_users: bool,

        hosts: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Deploy current local state without pull, lock, or push.
    Switch {
        #[arg(long)]
        boot: bool,

        hosts: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Pull, lock, build, push, and deploy.
    Update {
        #[arg(long)]
        debug: bool,

        #[arg(long)]
        dev: bool,

        #[arg(long)]
        boot: bool,

        #[arg(long)]
        pull: bool,

        #[arg(long)]
        lock: bool,

        #[arg(long)]
        user: Option<String>,

        #[arg(long)]
        all_users: bool,

        hosts: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Request approval for one allowlisted privileged command.
    Approve(ApproveArgs),

    /// Control autonomous agent task loops.
    Agents(AgentsArgs),

    /// Browse Keystone docs.
    Docs { topic_or_path: Option<String> },

    /// Search Keystone Photos assets.
    Photos {
        #[command(subcommand)]
        command: PhotosCommand,
    },

    /// Diagnose and manage hardware-key integrations.
    HardwareKey {
        #[command(subcommand)]
        command: HardwareKeyCommand,
    },

    /// Manage local screenshots.
    Screenshots {
        #[command(subcommand)]
        command: ScreenshotsCommand,
    },

    /// Refresh generated Keystone agent assets.
    SyncAgentAssets,

    /// Fetch SSH host public keys from live hosts into hosts.nix.
    SyncHostKeys,

    /// Manage checked-in Grafana dashboards.
    Grafana {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Convert markdown files to print-ready PDFs.
    Print {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Launch an AI coding agent with Keystone context.
    Agent(AgentArgs),

    /// Generate a system health diagnostic report.
    Doctor(DoctorArgs),

    /// Run the installer headlessly (no TUI). Requires installer ISO context.
    Install(InstallArgs),
}

#[derive(Args)]
pub struct InstallArgs {
    /// Target host to install (must match an embedded installer target).
    #[arg(long)]
    pub host: String,

    /// Target disk to install to (must match a discovered /dev/disk/by-id path).
    #[arg(long)]
    pub disk: Option<String>,
}

#[derive(Args)]
pub struct ApproveArgs {
    #[arg(long)]
    pub reason: String,

    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub command: Vec<String>,
}

#[derive(Args)]
pub struct AgentsArgs {
    pub action: String,
    pub target: String,
    pub reason: Option<String>,
}

#[derive(Args)]
pub struct AgentArgs {
    #[arg(long, num_args = 0..=1, default_missing_value = "default")]
    pub local: Option<String>,

    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub args: Vec<String>,
}

#[derive(Args)]
pub struct DoctorArgs {
    #[arg(long)]
    pub json: bool,

    #[arg(long, num_args = 0..=1, default_missing_value = "default")]
    pub local: Option<String>,

    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub args: Vec<String>,
}

#[derive(Subcommand)]
pub enum HardwareKeyCommand {
    /// Validate registered hardware-key configuration and local runtime state.
    Doctor {
        /// Optional selector: `user` or `user/key`.
        selector: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// TODO stub for managing agenix secrets from hardware-key metadata.
    Secrets {
        #[arg(long)]
        json: bool,
    },
}
