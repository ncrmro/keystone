//! CLI argument parsing (clap definitions).

use clap::Parser;

/// Keystone TUI — NixOS infrastructure configuration and management.
#[derive(Parser)]
#[command(name = "keystone-tui", version, about)]
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
}
