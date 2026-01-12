use crate::modules::config::JobConfig;
use anyhow::{Context, Result};
use std::path::PathBuf;
use tokio::fs;
use tokio::process::Command;

pub struct SystemdManager {
    user_systemd_dir: PathBuf,
}

impl SystemdManager {
    pub fn new() -> Result<Self> {
        let home = dirs::home_dir().context("Could not find home directory")?;
        let user_systemd_dir = home.join(".config/systemd/user");
        Ok(Self { user_systemd_dir })
    }

    pub async fn install_job(&self, job: &JobConfig, binary_path: &str) -> Result<()> {
        fs::create_dir_all(&self.user_systemd_dir).await?;

        let service_name = format!("keystone-job-{}", job.name);
        let service_file = self.user_systemd_dir.join(format!("{}.service", service_name));
        let timer_file = self.user_systemd_dir.join(format!("{}.timer", service_name));

        // Generate Service Unit
        let service_content = format!(
            "[Unit]\n\
             Description=Keystone Agent Job: {}\n\
             \n\
             [Service]\n\
             Type=oneshot\n\
             ExecStart={} run {}\n\
             StandardOutput=journal\n\
             StandardError=journal\n",
            job.name, binary_path, job.name
        );

        // Generate Timer Unit
        let timer_content = format!(
            "[Unit]\n\
             Description=Timer for Keystone Agent Job: {}\n\
             \n\
             [Timer]\n\
             OnCalendar={}\n\
             Persistent=true\n\
             \n\
             [Install]\n\
             WantedBy=timers.target\n",
            job.name, job.schedule
        );

        fs::write(&service_file, service_content).await?;
        fs::write(&timer_file, timer_content).await?;

        Ok(())
    }

    pub async fn reload_and_enable(&self, job_name: &str) -> Result<()> {
        // systemctl --user daemon-reload
        let status = Command::new("systemctl")
            .arg("--user")
            .arg("daemon-reload")
            .status()
            .await
            .context("Failed to run systemctl daemon-reload")?;

        if !status.success() {
            anyhow::bail!("systemctl daemon-reload failed");
        }

        // systemctl --user enable --now keystone-job-<name>.timer
        let timer_name = format!("keystone-job-{}.timer", job_name);
        let status = Command::new("systemctl")
            .arg("--user")
            .arg("enable")
            .arg("--now")
            .arg(&timer_name)
            .status()
            .await
            .context(format!("Failed to enable timer {}", timer_name))?;

        if !status.success() {
            anyhow::bail!("Failed to enable timer {}", timer_name);
        }

        Ok(())
    }
}
