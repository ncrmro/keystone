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
    pub icon: &'static str,
}

/// The standard navigation sections.
pub const NAV_ITEMS: &[SidebarItem] = &[
    SidebarItem {
        label: "Hosts",
        icon: "",
    },
    SidebarItem {
        label: "Services",
        icon: "",
    },
    SidebarItem {
        label: "Secrets",
        icon: "",
    },
    SidebarItem {
        label: "Security",
        icon: "",
    },
    SidebarItem {
        label: "Installer",
        icon: "",
    },
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
            let prefix = if i == active_index { " " } else { "  " };
            ListItem::new(Line::from(Span::styled(
                format!("{}{}", prefix, item.label),
                style,
            )))
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::RIGHT)
            .border_style(Style::default().fg(Color::DarkGray)),
    );
    frame.render_widget(list, area);
}
