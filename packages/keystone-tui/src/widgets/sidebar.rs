//! Navigation sidebar widget — stateless rendering primitive.

use ratatui::{
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem},
    Frame,
};

/// A sidebar navigation entry.
pub struct SidebarItem {
    pub label: &'static str,
}

/// The standard navigation sections.
pub const NAV_ITEMS: &[SidebarItem] = &[
    SidebarItem { label: "Hosts" },
    SidebarItem { label: "Services" },
    SidebarItem { label: "Secrets" },
    SidebarItem { label: "Security" },
    SidebarItem { label: "Installer" },
];

/// Render the navigation sidebar. `active_index` highlights the current section.
pub fn render(frame: &mut Frame, area: Rect, active_index: usize) {
    let items: Vec<ListItem> = NAV_ITEMS
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let style = if i == active_index {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::DarkGray)
            };
            ListItem::new(Line::from(Span::styled(format!(" {}", item.label), style)))
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::RIGHT)
            .border_style(Style::default().fg(Color::DarkGray)),
    );
    frame.render_widget(list, area);
}
