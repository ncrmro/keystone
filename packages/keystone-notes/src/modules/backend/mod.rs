use anyhow::Result;
use async_trait::async_trait;

#[async_trait]
pub trait Backend: Send + Sync {
    async fn generate(&self, prompt: &str) -> Result<String>;
}

pub mod mcp;
pub mod claude;
pub mod gemini;
pub mod ollama;