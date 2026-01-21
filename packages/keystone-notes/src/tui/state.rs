use crate::modules::config::{Config, JobConfig};
use anyhow::Result;

pub struct AppState {
    pub jobs: Vec<JobConfig>,
    pub selected_index: usize,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            jobs: Vec::new(),
            selected_index: 0,
        }
    }

    pub async fn load_jobs(&mut self) -> Result<()> {
        let config_path = std::path::Path::new(".keystone/jobs.toml");
        if config_path.exists() {
            let config = Config::load(config_path).await?;
            self.jobs = config.jobs;
        }
        Ok(())
    }
}
