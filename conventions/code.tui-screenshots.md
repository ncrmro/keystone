<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: TUI Screenshots (code.tui-screenshots)

Standards for capturing reproducible screenshots and demo recordings of ratatui-based TUI applications. Screenshots serve as both PR review artifacts and long-term documentation assets.

## Screenshot Mode

1. TUI binaries MUST support a `--screenshot <screen>` CLI flag that renders a single named screen to stdout as ANSI without entering alternate screen or raw mode.
2. The `--screenshot` mode MUST call `terminal.clear()` before drawing to force ratatui to write every cell, ensuring sparse screens render fully for capture tools.
3. The `--screenshot` mode MUST exit after rendering — it MUST NOT enter the event loop.
4. Every user-facing screen SHOULD be registered as a valid `--screenshot` target.

## VHS Tape Files

5. Each screenshot MUST have a corresponding vhs tape file in `docs/tapes/<screen>.tape`.
6. Tape files MUST declare `Require <binary>` to fail fast if the TUI binary is not on `$PATH`.
7. Tape files MUST set consistent visual parameters: `Set FontSize 14`, `Set Width 1200`, `Set Height 600`, `Set Theme "Catppuccin Mocha"`, `Set Padding 20`, `Set WindowBar Colorful`.
8. Tape files MUST use `Set TypingSpeed 0` to eliminate recording delays.
9. Tape files MUST use `Screenshot docs/screenshots/<screen>.png` to write output to the canonical location.
10. Tape files SHOULD include a regeneration comment at the top: `# Regenerate: nix run nixpkgs#vhs -- docs/tapes/<screen>.tape`.

## Screenshot Artifacts

11. Screenshots MUST be stored in `docs/screenshots/` as PNG files.
12. Screenshot filenames MUST match the screen name used by `--screenshot` (e.g., `--screenshot hosts` produces `docs/screenshots/hosts.png`).
13. Screenshots SHOULD be committed to git and updated in place when the UI changes — they serve as living documentation.
14. Screenshots MUST be regenerated before marking a PR ready for review if the PR changes any TUI screen rendering.

## Dev Shell

15. `vhs` SHOULD be included in the project's Nix devshell for screenshot generation.
16. A `make screenshots` target SHOULD be provided that regenerates all screenshots by running all tape files in `docs/tapes/`.

## Known Limitations

17. vhs MUST NOT be used to capture screens rendered in crossterm's alternate screen buffer — the `--screenshot` flag exists specifically to work around this limitation.
18. Screens that produce sparse ANSI output (few positioned cells) MAY fail with vhs's `Screenshot` command. In such cases, the tape file SHOULD document the limitation and offer a `GIF` Output as fallback.

## Golden Example

End-to-end workflow for adding a screenshot of a new TUI screen:

```bash
# 1. Add --screenshot support for the new screen in main.rs
#    (inside the run_screenshot_mode match block)
"my-screen" => {
    let mut screen = MyScreen::new();
    terminal.draw(|frame| {
        screen.render(frame, frame.area());
    })?;
}

# 2. Create the tape file
cat > docs/tapes/my-screen.tape << 'TAPE'
# My screen — description of what it shows
#
# Regenerate: nix run nixpkgs#vhs -- docs/tapes/my-screen.tape

Require keystone-tui

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 20
Set WindowBar Colorful
Set TypingSpeed 0

Type "keystone-tui --screenshot my-screen"
Enter
Sleep 2s
Screenshot docs/screenshots/my-screen.png
TAPE

# 3. Build the binary and run the tape
cargo build --release
PATH="$PWD/target/release:$PATH" nix run nixpkgs#vhs -- docs/tapes/my-screen.tape

# 4. Verify the screenshot
ls -la docs/screenshots/my-screen.png

# 5. Commit the tape file and screenshot
git add docs/tapes/my-screen.tape docs/screenshots/my-screen.png
git commit -m "docs(tui): add my-screen screenshot"
```
