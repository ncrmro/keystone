//! GitHub API integration for fetching SSH public keys.

use anyhow::Result;

/// Fetch SSH public keys for a GitHub user.
///
/// Calls `https://github.com/{username}.keys` which returns newline-separated
/// SSH public keys. Returns an empty vec if the user is not found (404).
pub async fn fetch_ssh_keys(username: &str) -> Result<Vec<String>> {
    let url = format!("https://github.com/{}.keys", username);

    let response = reqwest::Client::new()
        .get(&url)
        .header("User-Agent", "keystone-tui")
        .send()
        .await?;

    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(Vec::new());
    }

    let body = response.error_for_status()?.text().await?;

    let keys: Vec<String> = body
        .lines()
        .map(|line| line.trim().to_string())
        .filter(|line| line.starts_with("ssh-") || line.starts_with("ecdsa-"))
        .collect();

    Ok(keys)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires network access
    async fn test_fetch_ssh_keys_real_user() {
        let keys = fetch_ssh_keys("ncrmro").await.unwrap();
        assert!(!keys.is_empty(), "ncrmro should have at least one SSH key");
        for key in &keys {
            assert!(
                key.starts_with("ssh-") || key.starts_with("ecdsa-"),
                "Key should start with ssh- or ecdsa-: {}",
                key
            );
        }
    }

    #[tokio::test]
    #[ignore] // Requires network access
    async fn test_fetch_ssh_keys_nonexistent_user() {
        let keys = fetch_ssh_keys("this-user-definitely-does-not-exist-on-github-12345678")
            .await
            .unwrap();
        assert!(keys.is_empty());
    }
}
