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
}