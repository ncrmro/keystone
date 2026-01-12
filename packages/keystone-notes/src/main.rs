use clap::Parser;
use tracing::{info, Level};
use tracing_appender::rolling;

mod cli;
mod commands;
mod modules;
mod tui;

use cli::{Cli, Commands};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Setup logging
    let home = dirs::home_dir().expect("Could not find home directory");
    let log_dir = home.join(".local/share/keystone");
    std::fs::create_dir_all(&log_dir)?;
    
    let file_appender = rolling::daily(&log_dir, "agent.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

    tracing_subscriber::fmt()
        .with_writer(non_blocking)
        .with_max_level(Level::INFO)
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::InstallJobs { path } => {
            info!("Installing jobs from {:?}", path);
            commands::install::run(path).await?;
        }
        Commands::Run { job_name } => {
            info!("Running job: {}", job_name);
            commands::run::run(job_name).await?;
        }
        Commands::Allow { path } => {
            info!("Allowing scripts in {:?}", path);
            commands::allow::run(path).await?;
        }
        Commands::Sync => {
            info!("Syncing notes");
            modules::git::sync().await?;
        }
        Commands::Daily => {
            info!("Opening daily note");
            commands::daily::run().await?;
        }
        Commands::Tui => {
            info!("Launching TUI");
            commands::tui::run().await?;
        }
    }

    Ok(())
}
