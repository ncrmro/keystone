//! Hosts dashboard screen — split-panel view with live system monitoring.

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Gauge, List, ListItem, ListState, Paragraph, Sparkline},
    Frame,
};

use tokio::sync::mpsc;

use crate::nix::HostInfo;
use crate::system::{CpuHistory, DashboardMessage, HostStatus, SystemMetrics, TailscaleStatus};

/// Screen for the hosts dashboard with live system metrics.
pub struct HostsScreen {
    repo_name: String,
    statuses: Vec<HostStatus>,
    list_state: ListState,
    /// Channel for receiving async dashboard updates.
    rx: Option<mpsc::UnboundedReceiver<DashboardMessage>>,
    /// Latest tailscale status for online counting.
    tailscale_available: bool,
    /// Accumulated CPU history across metric updates.
    cpu_history: CpuHistory,
}

impl HostsScreen {
    pub fn new(repo_name: String, hosts: Vec<HostInfo>) -> Self {
        let statuses: Vec<HostStatus> = hosts
            .into_iter()
            .map(|h| HostStatus {
                host_info: h,
                tailscale: None,
                metrics: None,
                is_local: false,
            })
            .collect();

        let mut list_state = ListState::default();
        if !statuses.is_empty() {
            list_state.select(Some(0));
        }

        Self {
            repo_name,
            statuses,
            list_state,
            rx: None,
            tailscale_available: false,
            cpu_history: CpuHistory::new(60),
        }
    }

    /// Create a dashboard from pre-built HostStatus entries.
    pub fn new_with_statuses(repo_name: String, statuses: Vec<HostStatus>) -> Self {
        let mut list_state = ListState::default();
        if !statuses.is_empty() {
            list_state.select(Some(0));
        }

        Self {
            repo_name,
            statuses,
            list_state,
            rx: None,
            tailscale_available: false,
            cpu_history: CpuHistory::new(60),
        }
    }

    /// Attach a channel for receiving dashboard messages.
    pub fn set_channel(&mut self, rx: mpsc::UnboundedReceiver<DashboardMessage>) {
        self.rx = Some(rx);
    }

    /// Create with a pre-built channel (for testing).
    pub fn new_with_channel(
        repo_name: String,
        statuses: Vec<HostStatus>,
        rx: mpsc::UnboundedReceiver<DashboardMessage>,
    ) -> Self {
        let mut screen = Self::new_with_statuses(repo_name, statuses);
        screen.rx = Some(rx);
        screen
    }

    pub fn hosts(&self) -> Vec<&HostInfo> {
        self.statuses.iter().map(|s| &s.host_info).collect()
    }

    pub fn statuses(&self) -> &[HostStatus] {
        &self.statuses
    }

    pub fn selected_host(&self) -> Option<&HostInfo> {
        self.list_state
            .selected()
            .and_then(|i| self.statuses.get(i))
            .map(|s| &s.host_info)
    }

    pub fn selected_status(&self) -> Option<&HostStatus> {
        self.list_state
            .selected()
            .and_then(|i| self.statuses.get(i))
    }

    /// Count of hosts that are online via Tailscale.
    pub fn online_count(&self) -> usize {
        self.statuses
            .iter()
            .filter(|s| s.tailscale.as_ref().is_some_and(|t| t.online))
            .count()
    }

    pub fn next(&mut self) {
        if self.statuses.is_empty() {
            return;
        }
        let i = match self.list_state.selected() {
            Some(i) => (i + 1) % self.statuses.len(),
            None => 0,
        };
        self.list_state.select(Some(i));
    }

    pub fn previous(&mut self) {
        if self.statuses.is_empty() {
            return;
        }
        let i = match self.list_state.selected() {
            Some(i) => {
                if i == 0 {
                    self.statuses.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.list_state.select(Some(i));
    }

    /// Poll for dashboard messages (non-blocking, mirrors BuildScreen::poll).
    pub fn poll(&mut self) {
        // Take the receiver out to avoid borrowing self mutably twice
        let mut rx = match self.rx.take() {
            Some(rx) => rx,
            None => return,
        };

        // Collect all pending messages
        let mut messages = Vec::new();
        while let Ok(msg) = rx.try_recv() {
            messages.push(msg);
        }

        // Put the receiver back
        self.rx = Some(rx);

        // Process messages
        for msg in messages {
            match msg {
                DashboardMessage::TailscaleUpdate(ts) => {
                    self.tailscale_available = true;
                    self.apply_tailscale_update(&ts);
                }
                DashboardMessage::MetricsUpdate(metrics) => {
                    self.cpu_history.push(metrics.cpu_usage);
                    self.apply_metrics_update(metrics);
                }
                DashboardMessage::TailscaleUnavailable => {
                    self.tailscale_available = false;
                }
            }
        }
    }

    fn apply_tailscale_update(&mut self, ts: &TailscaleStatus) {
        for status in &mut self.statuses {
            status.tailscale = ts
                .peers
                .values()
                .find(|p| p.hostname.eq_ignore_ascii_case(&status.host_info.name))
                .cloned();
        }
    }

    fn apply_metrics_update(&mut self, metrics: SystemMetrics) {
        // Apply metrics to the local host
        for status in &mut self.statuses {
            if status.is_local {
                status.metrics = Some(metrics.clone());
            }
        }
        // If no local host was found, apply to the first host (fallback for single-host repos)
        if !self.statuses.iter().any(|s| s.is_local) {
            if let Some(first) = self.statuses.first_mut() {
                first.metrics = Some(metrics);
            }
        }
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title bar
                Constraint::Min(5),    // Main content
                Constraint::Length(1), // Help bar
            ])
            .split(area);

        self.render_title(frame, chunks[0]);
        self.render_main(frame, chunks[1]);
        self.render_help(frame, chunks[2]);
    }

    fn render_title(&self, frame: &mut Frame, area: Rect) {
        let online = self.online_count();
        let total = self.statuses.len();

        let subtitle = if self.tailscale_available {
            format!("{}/{} hosts online via Tailscale", online, total)
        } else if total > 0 {
            format!("{} hosts", total)
        } else {
            String::new()
        };

        let title_line = Line::from(vec![
            Span::styled(
                format!("Hosts Dashboard - {}", self.repo_name),
                Style::default().bold().yellow(),
            ),
            Span::raw("  "),
            Span::styled(subtitle, Style::default().fg(Color::DarkGray)),
        ]);

        let title = Paragraph::new(title_line)
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, area);
    }

    fn render_main(&mut self, frame: &mut Frame, area: Rect) {
        if self.statuses.is_empty() {
            let empty_msg = Paragraph::new(Text::styled(
                "No hosts found in flake.nix\n\nPress 'a' to add a new host",
                Style::default().fg(Color::DarkGray),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(empty_msg, area);
            return;
        }

        // Split: left 40% host list, right 60% metrics panel
        let panels = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(40), Constraint::Percentage(60)])
            .split(area);

        self.render_host_list(frame, panels[0]);
        self.render_metrics_panel(frame, panels[1]);
    }

    fn render_host_list(&mut self, frame: &mut Frame, area: Rect) {
        let items: Vec<ListItem> = self
            .statuses
            .iter()
            .map(|status| {
                let system_suffix = status
                    .host_info
                    .system
                    .as_deref()
                    .map(|s| format!(" ({})", s))
                    .unwrap_or_default();

                let (indicator, indicator_style) = match &status.tailscale {
                    Some(peer) if peer.online => ("●", Style::default().fg(Color::Green)),
                    Some(_) => ("○", Style::default().fg(Color::Red)),
                    None => ("", Style::default()),
                };

                let ip_text = status
                    .tailscale
                    .as_ref()
                    .and_then(|p| p.tailscale_ips.first())
                    .map(|ip| format!("  {}", ip))
                    .unwrap_or_default();

                let last_seen = match &status.tailscale {
                    Some(p) if !p.online && !p.last_seen.is_empty() => {
                        format!("  {}", format_last_seen(&p.last_seen))
                    }
                    _ => String::new(),
                };

                let line = Line::from(vec![
                    Span::styled(format!(" {} ", indicator), indicator_style),
                    Span::styled(
                        format!("{}{}", status.host_info.name, system_suffix),
                        Style::default(),
                    ),
                    Span::styled(ip_text, Style::default().fg(Color::DarkGray)),
                    Span::styled(last_seen, Style::default().fg(Color::DarkGray)),
                ]);

                ListItem::new(line)
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .borders(Borders::RIGHT)
                    .border_style(Style::default().fg(Color::DarkGray)),
            )
            .highlight_style(
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD),
            )
            .highlight_symbol("> ");

        frame.render_stateful_widget(list, area, &mut self.list_state);
    }

    fn render_metrics_panel(&self, frame: &mut Frame, area: Rect) {
        let selected = match self.selected_status() {
            Some(s) => s,
            None => return,
        };

        match &selected.metrics {
            Some(metrics) => self.render_live_metrics(frame, area, metrics),
            None => {
                // Remote host or no metrics yet
                let msg = if selected.is_local {
                    "Collecting metrics..."
                } else {
                    "Remote metrics via Prometheus — coming soon"
                };
                let placeholder =
                    Paragraph::new(Text::styled(msg, Style::default().fg(Color::DarkGray)))
                        .alignment(Alignment::Center)
                        .block(Block::default().borders(Borders::NONE));
                frame.render_widget(placeholder, area);
            }
        }
    }

    fn render_live_metrics(&self, frame: &mut Frame, area: Rect, metrics: &SystemMetrics) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(2), // CPU gauge
                Constraint::Length(2), // MEM gauge
                Constraint::Length(2), // SWAP gauge
                Constraint::Length(1), // spacer
                Constraint::Min(3),    // Disks
                Constraint::Length(3), // CPU sparkline
                Constraint::Length(2), // Temps
            ])
            .split(area);

        // CPU gauge
        let cpu_pct = metrics.cpu_usage / 100.0;
        let cpu_gauge = Gauge::default()
            .block(Block::default())
            .gauge_style(Style::default().fg(Color::Cyan))
            .label(format!("CPU  {:5.1}%", metrics.cpu_usage))
            .ratio(cpu_pct.clamp(0.0, 1.0));
        frame.render_widget(cpu_gauge, chunks[0]);

        // Memory gauge
        let mem_pct = if metrics.memory_total > 0 {
            metrics.memory_used as f64 / metrics.memory_total as f64
        } else {
            0.0
        };
        let mem_label = format!(
            "MEM  {}/{}",
            format_bytes(metrics.memory_used),
            format_bytes(metrics.memory_total)
        );
        let mem_gauge = Gauge::default()
            .block(Block::default())
            .gauge_style(Style::default().fg(Color::Green))
            .label(mem_label)
            .ratio(mem_pct.clamp(0.0, 1.0));
        frame.render_widget(mem_gauge, chunks[1]);

        // Swap gauge
        let swap_pct = if metrics.swap_total > 0 {
            metrics.swap_used as f64 / metrics.swap_total as f64
        } else {
            0.0
        };
        let swap_label = format!(
            "SWAP {}/{}",
            format_bytes(metrics.swap_used),
            format_bytes(metrics.swap_total)
        );
        let swap_gauge = Gauge::default()
            .block(Block::default())
            .gauge_style(Style::default().fg(Color::Yellow))
            .label(swap_label)
            .ratio(swap_pct.clamp(0.0, 1.0));
        frame.render_widget(swap_gauge, chunks[2]);

        // Disks
        let disk_lines: Vec<Line> = metrics
            .disks
            .iter()
            .take(4) // limit to 4 disks
            .map(|d| {
                let pct = d.usage_percent();
                let bar_width = 12;
                let filled = ((pct / 100.0) * bar_width as f64) as usize;
                let empty = bar_width - filled;
                Line::from(vec![
                    Span::styled(
                        format!("  {:8} ", truncate_str(&d.mount_point, 8)),
                        Style::default().fg(Color::DarkGray),
                    ),
                    Span::styled(
                        format!("[{}{}]", "█".repeat(filled), "░".repeat(empty)),
                        Style::default().fg(if pct > 90.0 { Color::Red } else { Color::Blue }),
                    ),
                    Span::raw(format!(" {:4.0}%", pct)),
                ])
            })
            .collect();

        if !disk_lines.is_empty() {
            let disk_text = Paragraph::new(disk_lines);
            frame.render_widget(disk_text, chunks[4]);
        }

        // CPU sparkline
        let spark_data: Vec<u64> = self
            .cpu_history
            .samples()
            .iter()
            .map(|v| *v as u64)
            .collect();
        if !spark_data.is_empty() {
            let sparkline = Sparkline::default()
                .block(Block::default().title("CPU "))
                .data(&spark_data)
                .max(100)
                .style(Style::default().fg(Color::Cyan));
            frame.render_widget(sparkline, chunks[5]);
        }

        // Temperatures
        if !metrics.temperatures.is_empty() {
            let temp_spans: Vec<Span> = metrics
                .temperatures
                .iter()
                .take(4)
                .map(|t| {
                    let color = if t.is_critical() {
                        Color::Red
                    } else if t.current > 70.0 {
                        Color::Yellow
                    } else {
                        Color::Green
                    };
                    Span::styled(
                        format!("  {} {:.0}°C", truncate_str(&t.label, 6), t.current),
                        Style::default().fg(color),
                    )
                })
                .collect();

            let temp_line = Line::from(temp_spans);
            let temps_p = Paragraph::new(temp_line);
            frame.render_widget(temps_p, chunks[6]);
        }
    }

    fn render_help(&self, frame: &mut Frame, area: Rect) {
        let help_text = if self.statuses.is_empty() {
            "a: add host • q: quit"
        } else {
            "↑/↓: navigate • Enter: details • b: build • i: ISO • r: refresh • q: quit"
        };
        let help = Paragraph::new(Text::styled(
            help_text,
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, area);
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn format_bytes(bytes: u64) -> String {
    const GB: u64 = 1_073_741_824;
    const MB: u64 = 1_048_576;
    if bytes >= GB {
        format!("{:.1}G", bytes as f64 / GB as f64)
    } else {
        format!("{:.0}M", bytes as f64 / MB as f64)
    }
}

fn truncate_str(s: &str, max: usize) -> String {
    let char_count = s.chars().count();
    if char_count <= max {
        s.to_string()
    } else {
        format!("{}…", s.chars().take(max - 1).collect::<String>())
    }
}

fn format_last_seen(ts: &str) -> String {
    // Simple: just show the timestamp. A real implementation would compute "2h ago" etc.
    if ts.len() > 16 {
        ts[..16].to_string()
    } else {
        ts.to_string()
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::system::{DiskInfo, TailscalePeer, TempReading};
    use std::collections::HashMap;

    fn sample_statuses() -> Vec<HostStatus> {
        vec![
            HostStatus {
                host_info: HostInfo {
                    name: "laptop".to_string(),
                    system: Some("x86_64-linux".to_string()),
                    keystone_modules: vec!["operating-system".to_string()],
                    config_files: vec![],
                },
                tailscale: Some(TailscalePeer {
                    hostname: "laptop".to_string(),
                    tailscale_ips: vec!["100.64.0.1".to_string()],
                    online: true,
                    last_seen: String::new(),
                    os: "linux".to_string(),
                }),
                metrics: None,
                is_local: true,
            },
            HostStatus {
                host_info: HostInfo {
                    name: "server".to_string(),
                    system: Some("x86_64-linux".to_string()),
                    keystone_modules: vec![],
                    config_files: vec![],
                },
                tailscale: Some(TailscalePeer {
                    hostname: "server".to_string(),
                    tailscale_ips: vec!["100.64.0.2".to_string()],
                    online: true,
                    last_seen: String::new(),
                    os: "linux".to_string(),
                }),
                metrics: None,
                is_local: false,
            },
            HostStatus {
                host_info: HostInfo {
                    name: "rpi".to_string(),
                    system: Some("aarch64-linux".to_string()),
                    keystone_modules: vec![],
                    config_files: vec![],
                },
                tailscale: Some(TailscalePeer {
                    hostname: "rpi".to_string(),
                    tailscale_ips: vec!["100.64.0.3".to_string()],
                    online: false,
                    last_seen: "2026-03-12T08:00:00Z".to_string(),
                    os: "linux".to_string(),
                }),
                metrics: None,
                is_local: false,
            },
        ]
    }

    fn sample_metrics() -> SystemMetrics {
        SystemMetrics {
            cpu_usage: 45.2,
            cpu_history: CpuHistory::new(60),
            memory_used: 8_589_934_592,   // 8 GB
            memory_total: 17_179_869_184, // 16 GB
            swap_used: 536_870_912,       // 0.5 GB
            swap_total: 4_294_967_296,    // 4 GB
            disks: vec![
                DiskInfo {
                    name: "nvme0n1p2".to_string(),
                    mount_point: "/".to_string(),
                    total_bytes: 500_000_000_000,
                    available_bytes: 110_000_000_000,
                    filesystem: "ext4".to_string(),
                },
                DiskInfo {
                    name: "nvme0n1p3".to_string(),
                    mount_point: "/nix".to_string(),
                    total_bytes: 500_000_000_000,
                    available_bytes: 180_000_000_000,
                    filesystem: "ext4".to_string(),
                },
            ],
            temperatures: vec![
                TempReading {
                    label: "CPU".to_string(),
                    current: 52.0,
                    critical: Some(100.0),
                },
                TempReading {
                    label: "GPU".to_string(),
                    current: 48.0,
                    critical: Some(95.0),
                },
            ],
        }
    }

    // -- T14: constructor with statuses --
    #[test]
    fn test_dashboard_new_with_statuses() {
        let statuses = sample_statuses();
        let screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
        assert_eq!(screen.statuses().len(), 3);
        assert_eq!(screen.selected_status().unwrap().host_info.name, "laptop");
    }

    // -- T15: navigation returns correct status --
    #[test]
    fn test_dashboard_selected_status() {
        let statuses = sample_statuses();
        let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
        screen.next(); // move to server
        assert_eq!(screen.selected_status().unwrap().host_info.name, "server");
    }

    // -- T16: poll metrics via channel --
    #[test]
    fn test_dashboard_poll_metrics() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut statuses = sample_statuses();
        statuses[0].is_local = true; // laptop is local
        let mut screen = HostsScreen::new_with_channel("test".to_string(), statuses, rx);

        let metrics = sample_metrics();
        tx.send(DashboardMessage::MetricsUpdate(metrics)).unwrap();
        screen.poll();

        // Local host (laptop) should have metrics
        assert!(screen.statuses()[0].metrics.is_some());
        let m = screen.statuses()[0].metrics.as_ref().unwrap();
        assert!((m.cpu_usage - 45.2).abs() < 0.1);
    }

    // -- T17: poll tailscale via channel --
    #[test]
    fn test_dashboard_poll_tailscale() {
        let (tx, rx) = mpsc::unbounded_channel();
        // Start without any tailscale data
        let statuses = vec![HostStatus {
            host_info: HostInfo {
                name: "laptop".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
            },
            tailscale: None,
            metrics: None,
            is_local: false,
        }];
        let mut screen = HostsScreen::new_with_channel("test".to_string(), statuses, rx);

        // Send tailscale update
        let mut peers = HashMap::new();
        peers.insert(
            "nodekey:a".to_string(),
            TailscalePeer {
                hostname: "laptop".to_string(),
                tailscale_ips: vec!["100.64.0.1".to_string()],
                online: true,
                last_seen: String::new(),
                os: "linux".to_string(),
            },
        );
        let ts = TailscaleStatus {
            self_hostname: "laptop".to_string(),
            peers,
        };
        tx.send(DashboardMessage::TailscaleUpdate(ts)).unwrap();
        screen.poll();

        assert!(screen.statuses()[0].tailscale.is_some());
        assert!(screen.statuses()[0].tailscale.as_ref().unwrap().online);
    }

    // -- T18: online count --
    #[test]
    fn test_dashboard_online_count() {
        let statuses = sample_statuses(); // 2 online, 1 offline
        let screen = HostsScreen::new_with_statuses("test".to_string(), statuses);
        assert_eq!(screen.online_count(), 2);
    }

    // -- Existing tests (preserved) --

    #[test]
    fn test_initial_selection() {
        let hosts = vec![HostInfo {
            name: "laptop".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
        }];
        let screen = HostsScreen::new("repo".to_string(), hosts);
        assert_eq!(screen.selected_host().unwrap().name, "laptop");
    }

    #[test]
    fn test_next_wraps() {
        let hosts = vec![
            HostInfo {
                name: "a".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
            },
            HostInfo {
                name: "b".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
            },
            HostInfo {
                name: "c".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
            },
        ];
        let mut screen = HostsScreen::new("repo".to_string(), hosts);
        screen.next(); // b
        screen.next(); // c
        screen.next(); // wraps to a
        assert_eq!(screen.selected_host().unwrap().name, "a");
    }

    #[test]
    fn test_previous_wraps() {
        let hosts = vec![
            HostInfo {
                name: "a".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
            },
            HostInfo {
                name: "b".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
            },
        ];
        let mut screen = HostsScreen::new("repo".to_string(), hosts);
        screen.previous(); // wraps to b
        assert_eq!(screen.selected_host().unwrap().name, "b");
    }

    #[test]
    fn test_empty_hosts() {
        let mut screen = HostsScreen::new("repo".to_string(), Vec::new());
        assert!(screen.selected_host().is_none());
        screen.next();
        screen.previous();
        assert!(screen.selected_host().is_none());
    }

    #[test]
    fn test_truncate_str_ascii_no_truncation() {
        assert_eq!(truncate_str("hello", 10), "hello");
        assert_eq!(truncate_str("hello", 5), "hello");
    }

    #[test]
    fn test_truncate_str_ascii_truncated() {
        let result = truncate_str("hello world", 6);
        assert_eq!(result, "hello…");
    }

    #[test]
    fn test_truncate_str_multibyte_no_truncation() {
        // "日本語" = 3 chars, each 3 bytes
        assert_eq!(truncate_str("日本語", 10), "日本語");
        assert_eq!(truncate_str("日本語", 3), "日本語");
    }

    #[test]
    fn test_truncate_str_multibyte_truncated() {
        // "日本語テスト" = 6 chars; truncate at max=4 → take 3 chars + ellipsis
        let result = truncate_str("日本語テスト", 4);
        assert_eq!(result, "日本語…");
    }

    #[test]
    fn test_truncate_str_emoji_truncated() {
        // Each emoji is >1 byte but 1 char
        let result = truncate_str("😀😁😂😃😄", 3);
        assert_eq!(result, "😀😁…");
    }
}
