---
title: Walker
description: Desktop launcher and project switcher for Keystone Desktop
---

# Walker

Walker is the quick launcher used by Keystone Desktop.

In Keystone, Walker is not just an application launcher. It is also the main
project switcher for moving between active project workspaces, shells, and
desktop windows.

Keystone Desktop uses two related projects:

- [Walker](https://github.com/abenz1267/walker) for the visible launcher UI
- [Elephant](https://github.com/abenz1267/elephant) for the provider and menu
  backend that powers custom menus and data sources

In practice, Walker is the frontend you open, and Elephant is the backend that
provides custom project menus, clipboard data, files, symbols, and other
searchable sources.

## What it does

Walker is used to:

- launch desktop applications,
- find and switch to project workspaces,
- reopen project terminals when they are not already running, and
- surface project context that comes from Keystone notes.

## Keystone launcher prefixes

Keystone configures Walker with a few high-value prefixes so you can jump
directly into a provider instead of searching the default mixed launcher view.

- `.` opens the `files` provider
- `=` opens the `calc` provider
- `$` opens the `clipboard` provider
- `/` opens the `providerlist` view

These prefixes make Walker usable as a general desktop command surface, not
just an app launcher.

## Project navigation

Keystone integrates Walker with the project model used by
[Projects and pz](../terminal/projects.md).

That means Walker can:

- list projects from the notes index,
- jump to the right Ghostty or Zellij session for a project, and
- act as the desktop side of the same workflow that `pz` provides in the
  terminal.

If your notes are stale, the Walker project menu will also be stale. See
[Notes](../notes.md) for how project notes are synced and used as durable
context.

## How it fits into Keystone Desktop

The intended flow is:

1. Keep project notes up to date
2. Use `pz` in the terminal when you are already working in a shell
3. Use Walker when you want to jump between projects from the desktop

This gives Keystone Desktop a fast project-oriented navigation model instead of
just a flat application launcher.

## Desktop keybindings

The most important launcher-related keybindings are:

- `$mod+Space` opens Walker
- `$mod+D` opens the Keystone project switcher
- `$mod+Ctrl+V` opens the clipboard manager in a terminal
- `$mod+Ctrl+E` opens Walker in symbols mode
- `$mod+K` opens the desktop keybindings menu

See [Desktop keybindings](keybindings.md) for the broader keyboard workflow.

## Related docs

- [Projects and pz](../terminal/projects.md)
- [Notes](../notes.md)
- [Desktop keybindings](keybindings.md)
- [Waybar Configuration](waybar-configuration.md)
