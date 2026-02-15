/// Application state for the Keystone TUI.
#[derive(Default)]
pub struct App {
    pub should_quit: bool,
}

impl App {
    pub fn new() -> Self {
        Self::default()
    }
}
