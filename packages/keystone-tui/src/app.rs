use crate::config::AppConfig;
use crate::screens::welcome::WelcomeScreen; // Assuming a welcome screen

/// Represents the different screens/views in the TUI.
pub enum AppScreen {
    Welcome(WelcomeScreen),
    // Add other screens here
}

/// Application state for the Keystone TUI.
pub struct App {
    pub should_quit: bool,
    pub config: AppConfig,
    pub current_screen: AppScreen,
}

impl App {
    pub async fn new() -> Self {
        let config = AppConfig::load().await.unwrap_or_else(|e| {
            eprintln!("Failed to load config: {:?}", e);
            AppConfig::default()
        });
        
        let current_screen = if config.repos.is_empty() {
            AppScreen::Welcome(WelcomeScreen::new())
        } else {
            // For now, if repos exist, just show the welcome screen
            // Later, this will go to a main screen displaying repos
            AppScreen::Welcome(WelcomeScreen::new()) 
        };

        Self {
            should_quit: false,
            config,
            current_screen,
        }
    }

    pub async fn save_config(&self) {
        if let Err(e) = self.config.save().await {
            eprintln!("Failed to save config: {:?}", e);
        }
    }
}


