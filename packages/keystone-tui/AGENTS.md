# Keystone TUI — Agent Conventions

## Architecture

This crate is a **TUI + CLI + JSON** tool following the **ratatui Component
Architecture**. The same binary serves three modes:

- **TUI mode** (default): Full-screen ratatui terminal interface
- **CLI mode** (`ks <subcommand>`): Line-based interactive prompts
- **JSON mode** (`ks <subcommand> --json`): Structured stdin/stdout for
  scripting and desktop menu integration (Walker, Elephant)

### Component Architecture

Each feature is a **component** implementing the `Component` trait:

```rust
pub trait Component {
    fn init(&mut self) -> Result<()>;
    fn handle_events(&mut self, event: &Event) -> Result<Option<Action>>;
    fn update(&mut self, action: &Action) -> Result<Option<Action>>;
    fn draw(&mut self, frame: &mut Frame, area: Rect) -> Result<()>;
}
```

Components own their state and colocate event handling, state updates, and
rendering. Cross-component communication flows through a single global
`Action` enum in `action.rs`.

### File Layout

```
src/
├── main.rs              # Entry point: CLI dispatch or TUI event loop
├── app.rs               # App struct, component registry, transitions
├── action.rs            # Single global Action enum
├── component.rs         # Component trait definition
├── tui.rs               # Terminal setup/teardown/panic hook
├── cli.rs               # Clap subcommand definitions
│
├── components/          # Feature components
│   ├── welcome.rs       # Simple component (single file)
│   ├── template/        # Complex component (directory)
│   │   ├── mod.rs       # Component impl (state + draw + events)
│   │   ├── types.rs     # Shared serde types (JSON/CLI/TUI)
│   │   └── run.rs       # Execution logic (shared by all modes)
│   ├── hosts/           # Nested sub-components
│   │   ├── mod.rs
│   │   ├── detail.rs
│   │   ├── build.rs
│   │   └── ...
│   └── ...
│
├── widgets/             # Stateless rendering primitives
│   ├── text_input.rs
│   └── select_menu.rs
│
├── nix.rs               # Flake parsing, config version detection
├── template.rs          # Nix file generation (pure functions)
└── ...                  # github.rs, ssh_keys.rs, disk.rs, system.rs, etc.
```

**Rules:**
- Simple components are a single `.rs` file.
- Complex components with CLI/JSON shared logic get a directory with `types.rs`
  (serde params/result) and `run.rs` (execution logic).
- Internal component actions (scroll, select, toggle) stay inside
  `handle_events()` — only navigation and cross-component effects go in
  `Action`.
- `widgets/` holds stateless rendering primitives reused across components.

### Adding a New Component

1. Create `src/components/<name>.rs` (simple) or `src/components/<name>/mod.rs`
   (complex).
2. Implement `Component` trait.
3. Add the component's navigation variant to `Screen` in `action.rs`.
4. Register the component in `components/mod.rs`.
5. If the component has a CLI subcommand, add it to `cli.rs` and wire
   `types.rs` + `run.rs` in `main.rs`.

## Clippy Configuration

The crate enables strict clippy lint groups:

- `clippy::correctness`, `clippy::suspicious`, `clippy::complexity`,
  `clippy::perf`, `clippy::style`
- `clippy::cognitive_complexity` with threshold **15** (via `clippy.toml`)

## Pre-Push Checklist

Before pushing any changes, run **all** of the following locally:

```bash
# 1. Formatting (must pass with zero diff)
cargo fmt --check

# 2. Clippy with ALL targets — warnings are errors
cargo clippy --all-targets --all-features -- -D warnings

# 3. Tests
cargo test
```

**Key detail**: Always use `--all-targets` with clippy. Plain `cargo clippy`
silently skips test files under `tests/`.
