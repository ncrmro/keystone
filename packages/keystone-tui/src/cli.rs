//! CLI argument parsing (clap definitions).

use clap::Parser;

/// Keystone TUI — NixOS infrastructure configuration and management.
#[derive(Parser)]
#[command(name = "ks", version, about)]
pub struct Cli {
    /// Generate config from JSON on stdin (legacy alias for `template --json`).
    #[arg(long)]
    pub json: bool,

    /// Render a single screen to stdout as ANSI and exit.
    #[arg(long, value_name = "SCREEN")]
    pub screenshot: Option<String>,

    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(clap::Subcommand)]
pub enum Command {
    /// Generate a new Keystone config from a template.
    Template {
        /// GitHub username — fetches display name and SSH keys.
        #[arg(long)]
        github_username: Option<String>,

        /// Output directory (defaults to hostname).
        #[arg(long, short)]
        output: Option<String>,

        /// JSON mode: read params from stdin, write result to stdout.
        #[arg(long)]
        json: bool,
    },

    /// Build home-manager profiles (or full NixOS systems with --lock).
    Build {
        /// Build full NixOS system closures instead of home-manager profiles.
        #[arg(long)]
        lock: bool,

        /// Comma-separated host names. Defaults to current host.
        hosts: Option<String>,

        /// JSON mode: output structured JSON.
        #[arg(long)]
        json: bool,
    },

    /// Deploy current local state without pull, lock, or push.
    Switch {
        /// Register for next boot instead of switching now.
        #[arg(long)]
        boot: bool,

        /// Comma-separated host names. Defaults to current host.
        hosts: Option<String>,

        /// JSON mode: output structured JSON.
        #[arg(long)]
        json: bool,
    },

    /// Pull, lock, build, push, and deploy.
    Update {
        /// Show warnings from git and nix commands.
        #[arg(long)]
        debug: bool,

        /// Build and deploy the current unlocked checkout (no pull/lock/push).
        #[arg(long)]
        dev: bool,

        /// Register for next boot instead of switching now.
        #[arg(long)]
        boot: bool,

        /// Pull managed repos only; skip build and deploy.
        #[arg(long)]
        pull: bool,

        /// Force lock mode explicitly (default unless --dev is set).
        #[arg(long)]
        lock: bool,

        /// Comma-separated host names. Defaults to current host.
        hosts: Option<String>,

        /// JSON mode: output structured JSON.
        #[arg(long)]
        json: bool,
    },

    /// Generate a system health diagnostic report.
    Doctor {
        /// JSON mode: output structured JSON.
        #[arg(long)]
        json: bool,
    },
}
