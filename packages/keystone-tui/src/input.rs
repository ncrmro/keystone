//! Input handling and action dispatch for the Keystone TUI.
//!
//! This module contains all key event handling and action dispatch logic,
//! extracted from main.rs to make it testable.

use crossterm::event::{KeyCode, KeyEvent, KeyEventKind};

use crate::app::{App, AppScreen};
use crate::components;
use crate::nix::HostInfo;

/// Actions that require mutating app-level state (screen transitions).
#[derive(Debug)]
pub enum AppAction {
    WelcomeAction(components::welcome::WelcomeAction),
    CreateConfigAction(components::create_config::CreateConfigAction),
    GoToCreateConfig { repo_name: String },
    GoToHostDetail(HostInfo),
    GoToHosts,
    StartBuild(String),
    BuildIso { host_name: Option<String> },
    IsoTargetUp,
    IsoTargetDown,
    IsoTargetSelect,
    RefreshDashboard,
    InstallHostUp,
    InstallHostDown,
    InstallHostSelect,
    InstallProceed,
    InstallConfirm,
    InstallBack,
    InstallCancel,
    InstallDiskUp,
    InstallDiskDown,
    InstallDiskSelect,
    StartDeploy { host_name: String },
    DeployTargetUp,
    DeployTargetDown,
    DeployTargetSelect,
    DeployManualInput,
    DeploySubmitManual,
    DeployConfirm,
    DeployBack,
    FirstBootStart,
    FirstBootApplyPatch,
    FirstBootSkip,
    FirstBootContinue,
    FirstBootSubmitRemote,
    FirstBootRetry,
    Reboot,
    Quit,
}

/// Dispatch a key event to the appropriate handler based on the current screen.
/// Returns `Some(AppAction)` if the key produced an action, or `None` if it was consumed silently.
pub fn dispatch_key(app: &mut App, key: KeyEvent) -> Option<AppAction> {
    // Only handle key press events, not release
    if key.kind != KeyEventKind::Press {
        return None;
    }

    match &mut app.current_screen {
        AppScreen::Welcome(ref mut welcome) => handle_welcome_input(welcome, key),
        AppScreen::CreateConfig(ref mut create_config) => {
            handle_create_config_input(create_config, key)
        }
        AppScreen::Hosts(ref mut hosts) => handle_hosts_input(hosts, key),
        AppScreen::HostDetail(ref mut detail) => handle_host_detail_input(detail, key),
        AppScreen::Build(ref mut build) => handle_build_input(build, key),
        AppScreen::Iso(ref mut iso) => handle_iso_input(iso, key),
        AppScreen::Deploy(ref mut deploy) => handle_deploy_input(deploy, key),
        AppScreen::Install(ref mut install) => handle_install_input(install, key),
        AppScreen::FirstBoot(ref mut first_boot) => handle_first_boot_input(first_boot, key),
    }
}

/// Handle input for the welcome screen.
pub fn handle_welcome_input(
    welcome: &mut components::welcome::WelcomeScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    use components::welcome::WelcomeState;

    let in_input_state = matches!(
        welcome.state(),
        WelcomeState::InputGitUrl | WelcomeState::InputRepoName
    );

    if in_input_state {
        match key.code {
            KeyCode::Enter => {
                return Some(AppAction::WelcomeAction(welcome.confirm()));
            }
            KeyCode::Esc => {
                welcome.cancel();
            }
            _ => {
                welcome.handle_text_input(key);
            }
        }
    } else {
        match key.code {
            KeyCode::Char('q') => {
                if *welcome.state() == WelcomeState::SelectAction {
                    return Some(AppAction::Quit);
                }
            }
            KeyCode::Esc => {
                if *welcome.state() == WelcomeState::SelectAction {
                    return Some(AppAction::Quit);
                } else {
                    welcome.cancel();
                }
            }
            KeyCode::Up | KeyCode::Char('k') => {
                welcome.previous();
            }
            KeyCode::Down | KeyCode::Char('j') => {
                welcome.next();
            }
            KeyCode::Enter => {
                return Some(AppAction::WelcomeAction(welcome.confirm()));
            }
            _ => {}
        }
    }
    None
}

/// Handle input for the create-config form screen.
pub fn handle_create_config_input(
    create_config: &mut components::create_config::CreateConfigScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    let field = create_config.current_form_field();

    if field.is_text_input() {
        match key.code {
            KeyCode::Tab => {
                create_config.next_field();
            }
            KeyCode::BackTab => {
                create_config.prev_field();
            }
            KeyCode::Enter => {
                return Some(AppAction::CreateConfigAction(create_config.submit()));
            }
            KeyCode::Esc => {
                return Some(AppAction::Quit);
            }
            _ => {
                create_config.handle_text_input(key);
            }
        }
    } else {
        // Selection field (MachineType, StorageType)
        match key.code {
            KeyCode::Tab | KeyCode::Down | KeyCode::Char('j') => {
                create_config.next_field();
            }
            KeyCode::BackTab | KeyCode::Up | KeyCode::Char('k') => {
                create_config.prev_field();
            }
            KeyCode::Left | KeyCode::Char('h') => {
                create_config.cycle_selection_prev();
            }
            KeyCode::Right | KeyCode::Char('l') => {
                create_config.cycle_selection_next();
            }
            KeyCode::Enter => {
                return Some(AppAction::CreateConfigAction(create_config.submit()));
            }
            KeyCode::Esc => {
                return Some(AppAction::Quit);
            }
            _ => {}
        }
    }
    None
}

/// Handle input for the hosts screen.
pub fn handle_hosts_input(
    hosts: &mut components::hosts::HostsScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') | KeyCode::Esc => Some(AppAction::Quit),
        KeyCode::Up | KeyCode::Char('k') => {
            hosts.previous();
            None
        }
        KeyCode::Down | KeyCode::Char('j') => {
            hosts.next();
            None
        }
        KeyCode::Enter => hosts
            .selected_host()
            .map(|host| AppAction::GoToHostDetail(host.clone())),
        KeyCode::Char('i') => {
            let host_name = hosts.selected_host().map(|h| h.name.clone());
            Some(AppAction::BuildIso { host_name })
        }
        KeyCode::Char('d') => hosts.selected_host().map(|h| AppAction::StartDeploy {
            host_name: h.name.clone(),
        }),
        KeyCode::Char('r') => Some(AppAction::RefreshDashboard),
        _ => None,
    }
}

/// Handle input for the host detail screen.
pub fn handle_host_detail_input(
    _detail: &mut components::host_detail::HostDetailScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') => Some(AppAction::Quit),
        KeyCode::Esc => Some(AppAction::GoToHosts),
        KeyCode::Char('b') => {
            let host_name = _detail.host().name.clone();
            Some(AppAction::StartBuild(host_name))
        }
        _ => None,
    }
}

/// Handle input for the build screen.
pub fn handle_build_input(
    build: &mut components::build::BuildScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') => {
            if build.is_finished() {
                Some(AppAction::Quit)
            } else {
                None
            }
        }
        KeyCode::Esc => {
            if build.is_finished() {
                Some(AppAction::GoToHosts)
            } else {
                build.cancel();
                None
            }
        }
        KeyCode::Up | KeyCode::Char('k') => {
            build.scroll_up();
            None
        }
        KeyCode::Down | KeyCode::Char('j') => {
            build.scroll_down();
            None
        }
        _ => None,
    }
}

/// Handle input for the ISO screen.
pub fn handle_iso_input(iso: &mut components::iso::IsoScreen, key: KeyEvent) -> Option<AppAction> {
    use components::iso::IsoPhase;

    match iso.phase() {
        IsoPhase::Building => match key.code {
            KeyCode::Esc | KeyCode::Char('q') => Some(AppAction::GoToHosts),
            KeyCode::Up | KeyCode::Char('k') => {
                iso.scroll_up();
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                iso.scroll_down();
                None
            }
            _ => None,
        },
        IsoPhase::SelectTarget => match key.code {
            KeyCode::Up | KeyCode::Char('k') => Some(AppAction::IsoTargetUp),
            KeyCode::Down | KeyCode::Char('j') => Some(AppAction::IsoTargetDown),
            KeyCode::Enter => Some(AppAction::IsoTargetSelect),
            KeyCode::Esc | KeyCode::Char('q') => Some(AppAction::GoToHosts),
            _ => None,
        },
        IsoPhase::Writing => match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                iso.scroll_up();
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                iso.scroll_down();
                None
            }
            _ => None,
        },
        IsoPhase::Done | IsoPhase::Failed(_) => match key.code {
            KeyCode::Esc => Some(AppAction::GoToHosts),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
    }
}

/// Handle input for the deploy screen.
pub fn handle_deploy_input(
    deploy: &mut components::deploy::DeployScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    use components::deploy::DeployPhase;

    match deploy.phase() {
        DeployPhase::Discovery => match key.code {
            KeyCode::Up | KeyCode::Char('k') => Some(AppAction::DeployTargetUp),
            KeyCode::Down | KeyCode::Char('j') => Some(AppAction::DeployTargetDown),
            KeyCode::Enter => Some(AppAction::DeployTargetSelect),
            KeyCode::Char('m') => Some(AppAction::DeployManualInput),
            KeyCode::Esc | KeyCode::Char('q') => Some(AppAction::GoToHosts),
            _ => None,
        },
        DeployPhase::ManualInput => match key.code {
            KeyCode::Enter => Some(AppAction::DeploySubmitManual),
            KeyCode::Esc => Some(AppAction::DeployBack),
            _ => {
                deploy.handle_text_input(key);
                None
            }
        },
        DeployPhase::Confirm => match key.code {
            KeyCode::Enter => Some(AppAction::DeployConfirm),
            KeyCode::Esc => Some(AppAction::DeployBack),
            _ => None,
        },
        DeployPhase::Deploying => match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                deploy.scroll_up();
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                deploy.scroll_down();
                None
            }
            _ => None,
        },
        DeployPhase::Done | DeployPhase::Failed(_) => match key.code {
            KeyCode::Esc => Some(AppAction::GoToHosts),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
    }
}

/// Handle input for the install screen.
pub fn handle_install_input(
    install: &mut components::install::InstallScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    use components::install::InstallPhase;

    match install.phase() {
        InstallPhase::HostSelection => match key.code {
            KeyCode::Up | KeyCode::Char('k') => Some(AppAction::InstallHostUp),
            KeyCode::Down | KeyCode::Char('j') => Some(AppAction::InstallHostDown),
            KeyCode::Enter => Some(AppAction::InstallHostSelect),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        InstallPhase::Summary => match key.code {
            KeyCode::Enter => Some(AppAction::InstallProceed),
            KeyCode::Esc => Some(AppAction::InstallBack),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        InstallPhase::DiskSelection => match key.code {
            KeyCode::Up | KeyCode::Char('k') => Some(AppAction::InstallDiskUp),
            KeyCode::Down | KeyCode::Char('j') => Some(AppAction::InstallDiskDown),
            KeyCode::Enter => Some(AppAction::InstallDiskSelect),
            KeyCode::Esc => Some(AppAction::InstallBack),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        InstallPhase::Confirm => match key.code {
            KeyCode::Enter => Some(AppAction::InstallConfirm),
            KeyCode::Esc => Some(AppAction::InstallBack),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        InstallPhase::Installing => match key.code {
            KeyCode::Esc => {
                install.cancel();
                None
            }
            KeyCode::Up | KeyCode::Char('k') => {
                install.scroll_up();
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                install.scroll_down();
                None
            }
            _ => None,
        },
        InstallPhase::Done => match key.code {
            KeyCode::Char('r') => Some(AppAction::Reboot),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        InstallPhase::Failed(_) => match key.code {
            KeyCode::Char('q') => Some(AppAction::Quit),
            KeyCode::Up | KeyCode::Char('k') => {
                install.scroll_up();
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                install.scroll_down();
                None
            }
            _ => None,
        },
    }
}

/// Handle input for the first-boot screen.
pub fn handle_first_boot_input(
    first_boot: &mut components::first_boot::FirstBootScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    use components::first_boot::FirstBootPhase;

    match first_boot.phase() {
        FirstBootPhase::Welcome => match key.code {
            KeyCode::Enter => Some(AppAction::FirstBootStart),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        FirstBootPhase::DetectingHardware | FirstBootPhase::GitSetup | FirstBootPhase::Pushing => {
            // No user input during async phases
            None
        }
        FirstBootPhase::ReviewPatch => match key.code {
            KeyCode::Enter => Some(AppAction::FirstBootApplyPatch),
            KeyCode::Char('s') => Some(AppAction::FirstBootSkip),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        FirstBootPhase::ShowSshKey => match key.code {
            KeyCode::Enter => Some(AppAction::FirstBootContinue),
            KeyCode::Char('s') => Some(AppAction::FirstBootSkip),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        FirstBootPhase::RemoteInput => match key.code {
            KeyCode::Enter => Some(AppAction::FirstBootSubmitRemote),
            KeyCode::Esc => Some(AppAction::FirstBootSkip),
            _ => {
                first_boot.handle_text_input(key);
                None
            }
        },
        FirstBootPhase::Done => match key.code {
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
        FirstBootPhase::Failed(_) => match key.code {
            KeyCode::Char('r') => Some(AppAction::FirstBootRetry),
            KeyCode::Char('s') => Some(AppAction::FirstBootSkip),
            KeyCode::Char('q') => Some(AppAction::Quit),
            _ => None,
        },
    }
}

/// Handle actions that require mutating app state.
// TODO: remove allow once migrated to Component trait dispatch
#[allow(clippy::cognitive_complexity)]
pub async fn handle_action(app: &mut App, action: AppAction) {
    match action {
        AppAction::WelcomeAction(wa) => {
            handle_welcome_action(app, wa).await;
        }
        AppAction::CreateConfigAction(ca) => {
            handle_create_config_action(app, ca).await;
        }
        AppAction::GoToCreateConfig { repo_name } => {
            app.current_screen = AppScreen::CreateConfig(
                components::create_config::CreateConfigScreen::new(repo_name),
            );
        }
        AppAction::GoToHostDetail(host) => {
            app.current_screen =
                AppScreen::HostDetail(components::host_detail::HostDetailScreen::new(host));
        }
        AppAction::GoToHosts => {
            // Re-load the hosts screen from the active repo
            app.go_to_hosts(app.active_repo_index.unwrap_or(0)).await;
        }
        AppAction::StartBuild(host_name) => {
            if let Some(repo_path) = app.active_repo_path() {
                app.current_screen =
                    AppScreen::Build(components::build::BuildScreen::new(host_name, repo_path));
            }
        }
        AppAction::BuildIso { host_name } => {
            if let Some(repo_path) = app.active_repo_path() {
                app.current_screen = AppScreen::Iso(components::iso::IsoScreen::new_for_host(
                    repo_path, host_name,
                ));
            }
        }
        AppAction::IsoTargetUp => {
            if let AppScreen::Iso(ref mut iso) = app.current_screen {
                iso.target_up();
            }
        }
        AppAction::IsoTargetDown => {
            if let AppScreen::Iso(ref mut iso) = app.current_screen {
                iso.target_down();
            }
        }
        AppAction::IsoTargetSelect => {
            if let AppScreen::Iso(ref mut iso) = app.current_screen {
                iso.select_target();
            }
        }
        AppAction::RefreshDashboard => {
            // Re-load the hosts screen from the active repo
            app.go_to_hosts(app.active_repo_index.unwrap_or(0)).await;
        }
        AppAction::InstallHostUp => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.host_up();
            }
        }
        AppAction::InstallHostDown => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.host_down();
            }
        }
        AppAction::InstallHostSelect => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.select_host();
            }
        }
        AppAction::InstallProceed => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.proceed_to_confirm();
            }
        }
        AppAction::InstallConfirm => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.start_install();
            }
        }
        AppAction::InstallBack => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.go_back();
            }
        }
        AppAction::InstallCancel => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.cancel();
            }
        }
        AppAction::InstallDiskUp => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.disk_up();
            }
        }
        AppAction::InstallDiskDown => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.disk_down();
            }
        }
        AppAction::InstallDiskSelect => {
            if let AppScreen::Install(ref mut install) = app.current_screen {
                install.select_disk();
            }
        }
        AppAction::StartDeploy { host_name } => {
            if let Some(repo_path) = app.active_repo_path() {
                app.current_screen =
                    AppScreen::Deploy(components::deploy::DeployScreen::new(repo_path, host_name));
            }
        }
        AppAction::DeployTargetUp => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.target_up();
            }
        }
        AppAction::DeployTargetDown => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.target_down();
            }
        }
        AppAction::DeployTargetSelect => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.select_target();
            }
        }
        AppAction::DeployManualInput => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.enter_manual_input();
            }
        }
        AppAction::DeploySubmitManual => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.submit_manual();
            }
        }
        AppAction::DeployConfirm => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.confirm_deploy();
            }
        }
        AppAction::DeployBack => {
            if let AppScreen::Deploy(ref mut deploy) = app.current_screen {
                deploy.go_back();
            }
        }
        AppAction::FirstBootStart => {
            if let AppScreen::FirstBoot(ref mut fb) = app.current_screen {
                fb.start();
            }
        }
        AppAction::FirstBootApplyPatch => {
            if let AppScreen::FirstBoot(ref mut fb) = app.current_screen {
                fb.apply_patch();
            }
        }
        AppAction::FirstBootSkip => {
            if let AppScreen::FirstBoot(ref mut fb) = app.current_screen {
                fb.skip();
            }
        }
        AppAction::FirstBootContinue => {
            if let AppScreen::FirstBoot(ref mut fb) = app.current_screen {
                fb.continue_to_remote();
            }
        }
        AppAction::FirstBootSubmitRemote => {
            if let AppScreen::FirstBoot(ref mut fb) = app.current_screen {
                fb.submit_remote();
            }
        }
        AppAction::FirstBootRetry => {
            if let AppScreen::FirstBoot(ref mut fb) = app.current_screen {
                fb.retry_push();
            }
        }
        AppAction::Reboot => {
            // Attempt to reboot the system
            let _ = std::process::Command::new("systemctl")
                .arg("reboot")
                .spawn();
        }
        AppAction::Quit => {
            app.should_quit = true;
        }
    }
}

/// Handle actions from the welcome screen.
async fn handle_welcome_action(app: &mut App, action: components::welcome::WelcomeAction) {
    use components::welcome::WelcomeAction;

    match action {
        WelcomeAction::ImportRepo { name, git_url } => {
            if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
                match crate::repo::import_repo(name.clone(), git_url).await {
                    Ok(repo) => {
                        app.config.repos.push(repo);
                        welcome
                            .set_success(format!("Repository '{}' imported successfully!", name));
                    }
                    Err(e) => {
                        welcome.set_error(format!("Failed to import repository: {}", e));
                    }
                }
            }
        }
        WelcomeAction::CreateRepo { name } => {
            // Transition to the CreateConfig form instead of directly creating
            app.current_screen =
                AppScreen::CreateConfig(components::create_config::CreateConfigScreen::new(name));
        }
        WelcomeAction::Complete => {
            // User completed the welcome flow - transition to hosts screen
            let repo_index = app.config.repos.len().saturating_sub(1);
            app.go_to_hosts(repo_index).await;
        }
        WelcomeAction::None => {}
    }
}

/// Handle actions from the create-config screen.
async fn handle_create_config_action(
    app: &mut App,
    action: components::create_config::CreateConfigAction,
) {
    use components::create_config::CreateConfigAction;

    match action {
        CreateConfigAction::Complete {
            machine_type,
            hostname,
            storage_type,
            disk_device,
            username,
            password,
            github_username,
        } => {
            // Fetch GitHub SSH keys if a username was provided
            let authorized_keys = if !github_username.is_empty() {
                crate::github::fetch_ssh_keys(&github_username)
                    .await
                    .unwrap_or_default()
            } else {
                Vec::new()
            };

            // Use hostname as repo name
            let repo_name = hostname.clone();

            let gh_username = if github_username.is_empty() {
                None
            } else {
                Some(github_username.clone())
            };

            match crate::repo::create_new_repo_from_config(
                repo_name.clone(),
                machine_type,
                hostname,
                storage_type,
                disk_device,
                username,
                password,
                gh_username,
                authorized_keys,
                None, // time_zone — use default
                None, // state_version — use default
            )
            .await
            {
                Ok(repo) => {
                    app.config.repos.push(repo);
                    // Transition to hosts screen for the new repo
                    let repo_index = app.config.repos.len().saturating_sub(1);
                    app.go_to_hosts(repo_index).await;
                }
                Err(e) => {
                    // Go back to welcome screen with error
                    let mut welcome = components::welcome::WelcomeScreen::new();
                    welcome.set_error(format!("Failed to create configuration: {}", e));
                    app.current_screen = AppScreen::Welcome(welcome);
                }
            }
        }
        CreateConfigAction::None => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyEventState, KeyModifiers};

    /// Helper to create a key press event.
    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent {
            code,
            modifiers: KeyModifiers::NONE,
            kind: KeyEventKind::Press,
            state: KeyEventState::NONE,
        }
    }

    /// Helper to create a key release event.
    fn key_release(code: KeyCode) -> KeyEvent {
        KeyEvent {
            code,
            modifiers: KeyModifiers::NONE,
            kind: KeyEventKind::Release,
            state: KeyEventState::NONE,
        }
    }

    #[test]
    fn test_key_release_events_are_ignored() {
        let mut app = App::new_for_test();
        let result = dispatch_key(&mut app, key_release(KeyCode::Char('q')));
        assert!(result.is_none());
    }

    #[test]
    fn test_q_quits_from_welcome_select() {
        let mut app = App::new_for_test();
        let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
        assert!(matches!(action, Some(AppAction::Quit)));
    }

    #[test]
    fn test_esc_quits_from_welcome_select() {
        let mut app = App::new_for_test();
        let action = dispatch_key(&mut app, key(KeyCode::Esc));
        assert!(matches!(action, Some(AppAction::Quit)));
    }

    #[test]
    fn test_q_quits_from_hosts() {
        let hosts = vec![HostInfo {
            name: "test-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        }];
        let mut app = App::new_for_test();
        app.current_screen = AppScreen::Hosts(components::hosts::HostsScreen::new(
            "test-repo".to_string(),
            hosts,
        ));

        let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
        assert!(matches!(action, Some(AppAction::Quit)));
    }

    #[test]
    fn test_enter_selects_host() {
        let hosts = vec![HostInfo {
            name: "my-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        }];
        let mut app = App::new_for_test();
        app.current_screen = AppScreen::Hosts(components::hosts::HostsScreen::new(
            "test-repo".to_string(),
            hosts,
        ));

        let action = dispatch_key(&mut app, key(KeyCode::Enter));
        assert!(matches!(action, Some(AppAction::GoToHostDetail(_))));
    }

    #[test]
    fn test_b_starts_build_from_detail() {
        let host = HostInfo {
            name: "build-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        };
        let mut app = App::new_for_test();
        app.current_screen =
            AppScreen::HostDetail(components::host_detail::HostDetailScreen::new(host));

        let action = dispatch_key(&mut app, key(KeyCode::Char('b')));
        match action {
            Some(AppAction::StartBuild(name)) => assert_eq!(name, "build-host"),
            other => panic!("Expected StartBuild, got {:?}", other),
        }
    }

    #[test]
    fn test_esc_goes_to_hosts_from_detail() {
        let host = HostInfo {
            name: "test-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        };
        let mut app = App::new_for_test();
        app.current_screen =
            AppScreen::HostDetail(components::host_detail::HostDetailScreen::new(host));

        let action = dispatch_key(&mut app, key(KeyCode::Esc));
        assert!(matches!(action, Some(AppAction::GoToHosts)));
    }

    #[test]
    fn test_hosts_i_builds_iso() {
        let hosts = vec![HostInfo {
            name: "test-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        }];
        let mut app = App::new_for_test();
        app.current_screen = AppScreen::Hosts(components::hosts::HostsScreen::new(
            "test-repo".to_string(),
            hosts,
        ));

        let action = dispatch_key(&mut app, key(KeyCode::Char('i')));
        assert!(matches!(action, Some(AppAction::BuildIso { .. })));
    }

    #[test]
    fn test_hosts_r_refreshes() {
        let hosts = vec![HostInfo {
            name: "test-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        }];
        let mut app = App::new_for_test();
        app.current_screen = AppScreen::Hosts(components::hosts::HostsScreen::new(
            "test-repo".to_string(),
            hosts,
        ));

        let action = dispatch_key(&mut app, key(KeyCode::Char('r')));
        assert!(matches!(action, Some(AppAction::RefreshDashboard)));
    }

    #[test]
    fn test_q_quits_from_host_detail() {
        let host = HostInfo {
            name: "test-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        };
        let mut app = App::new_for_test();
        app.current_screen =
            AppScreen::HostDetail(components::host_detail::HostDetailScreen::new(host));

        let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
        assert!(matches!(action, Some(AppAction::Quit)));
    }
}
