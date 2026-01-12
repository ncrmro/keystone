pub struct AppState {
    pub jobs: Vec<String>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            jobs: vec!["Job 1: Sync (Scheduled)".to_string(), "Job 2: Daily Summary (Scheduled)".to_string()],
        }
    }
}
