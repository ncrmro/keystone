#[cfg(test)]
mod tests {
    use crate::modules::config::Config;
    use crate::modules::trust::TrustManager;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[tokio::test]
    async fn test_config_load_happy_path() -> anyhow::Result<()> {
        let mut temp_file = NamedTempFile::new()?;
        let config_content = r#"
            [global]
            backend = "claude-code"
            
            [[jobs]]
            name = "test-job"
            schedule = "0 8 * * *"
            script = "scripts/test.sh"
        "#;
        
        write!(temp_file, "{}", config_content)?;
        
        let config = Config::load(temp_file.path()).await?;
        
        assert_eq!(config.global.backend, "claude-code");
        assert_eq!(config.jobs.len(), 1);
        assert_eq!(config.jobs[0].name, "test-job");
        assert_eq!(config.jobs[0].schedule, "0 8 * * *");
        
        Ok(())
    }

    #[tokio::test]
    async fn test_trust_manager_approve_happy_path() -> anyhow::Result<()> {
        // Create a temporary "trust store" file
        let trust_store_file = NamedTempFile::new()?;
        let trust_store_path = trust_store_file.path().to_path_buf();
        
        // Create a temporary "script" file to approve
        let mut script_file = NamedTempFile::new()?;
        write!(script_file, "echo 'hello world'")?;
        let script_path = script_file.path().to_path_buf();
        
        // Initialize TrustManager with temp store path
        let mut trust_manager = TrustManager::with_path(trust_store_path.clone()).await?;
        
        // Initially should NOT be allowed
        assert!(!trust_manager.is_allowed(&script_path).await?);
        
        // Approve script
        trust_manager.approve(&script_path).await?;
        
        // Should now be allowed
        assert!(trust_manager.is_allowed(&script_path).await?);
        
        // Verify persistence: create new manager instance pointing to same store
        let trust_manager_2 = TrustManager::with_path(trust_store_path).await?;
        assert!(trust_manager_2.is_allowed(&script_path).await?);
        
        Ok(())
    }

    struct MockBackend;
    #[async_trait::async_trait]
    impl crate::modules::backend::Backend for MockBackend {
        async fn generate(&self, _prompt: &str) -> anyhow::Result<String> {
            Ok("Mock Result".to_string())
        }
    }

    #[tokio::test]
    async fn test_runner_output_handling() -> anyhow::Result<()> {
        let temp_dir = tempfile::tempdir()?;
        let output_file = temp_dir.path().join("output.txt");
        
        let job = crate::modules::config::JobConfig {
            name: "test-job".to_string(),
            schedule: "0 8 * * *".to_string(),
            script: "builtin:test".to_string(),
            backend: None,
            context_mode: None,
            context_lookback: None,
            output_path: Some(output_file.to_str().unwrap().to_string()),
            output_mode: Some(crate::modules::config::OutputMode::Overwrite),
        };
        
        let runner = crate::modules::runner::AgentRunner::new(Box::new(MockBackend));
        runner.run_job(&job).await?;
        
        let content = std::fs::read_to_string(output_file)?;
        assert_eq!(content, "Mock Result");
        
        Ok(())
    }
}