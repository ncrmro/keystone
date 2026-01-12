use crate::modules::backend::Backend;
use anyhow::{Context, Result};
use async_trait::async_trait;
use serde_json::json;

pub struct OllamaBackend {
    base_url: String,
    model: String,
    client: reqwest::Client,
}

impl OllamaBackend {
    pub fn new(base_url: String, model: String) -> Self {
        Self {
            base_url,
            model,
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl Backend for OllamaBackend {
    async fn generate(&self, prompt: &str) -> Result<String> {
        let url = format!("{}/api/generate", self.base_url);
        let body = json!({
            "model": self.model,
            "prompt": prompt,
            "stream": false
        });

        let res = self.client.post(&url)
            .json(&body)
            .send()
            .await
            .context("Failed to contact Ollama")?;

        if !res.status().is_success() {
            anyhow::bail!("Ollama error: {}", res.status());
        }

        let resp_json: serde_json::Value = res.json().await?;
        let response = resp_json["response"].as_str()
            .context("Invalid response from Ollama")?
            .to_string();

        Ok(response)
    }
}
