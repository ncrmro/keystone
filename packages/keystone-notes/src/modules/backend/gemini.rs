use crate::modules::backend::{Backend, mcp::MCPClient};
use anyhow::Result;
use async_trait::async_trait;

pub struct GeminiBackend {
    client: MCPClient,
}

impl GeminiBackend {
    pub fn new(binary_path: Option<String>) -> Self {
        let binary = binary_path.unwrap_or_else(|| "gemini".to_string());
        Self { 
            client: MCPClient::new(binary, vec![]) 
        }
    }
}

#[async_trait]
impl Backend for GeminiBackend {
    async fn generate(&self, prompt: &str) -> Result<String> {
        self.client.call(prompt).await
    }
}
