/// Application state for the Keystone TUI.
pub struct App {
    pub should_quit: bool,
}

impl App {
    pub fn new() -> Self {
        Self {
            should_quit: false,
        }
    }
}
