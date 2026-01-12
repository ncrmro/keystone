use crate::modules::trust::TrustManager;
use anyhow::Result;
use std::path::PathBuf;
use tokio::fs;

pub async fn run(path: PathBuf) -> Result<()> {
    let mut trust = TrustManager::new().await?;
    
    if path.is_file() {
        println!("Allowing script: {:?}", path);
        trust.approve(&path).await?;
    } else if path.is_dir() {
        println!("Scanning directory: {:?}", path);
        let mut entries = fs::read_dir(path).await?;
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            if path.is_file() {
                println!("Allowing script: {:?}", path);
                trust.approve(&path).await?;
            }
        }
    } else {
        println!("Path not found: {:?}", path);
    }
    
    println!("Done.");
    Ok(())
}
