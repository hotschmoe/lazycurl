# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a fork of [lazycurl](https://github.com/BowTiedCrocodile/lazycurl) (original work by BowTiedCrocodile) that we use as a real-world testbed for [zithril](https://github.com/hotschmoe/zithril), our Zig TUI framework. We're using this project to help mature zithril and find issues in the framework. Issues discovered during this effort are tracked at [hotschmoe/zithril/issues](https://github.com/hotschmoe/zithril/issues).

lazycurl is a terminal-based UI application (written in Zig) for building and executing curl commands visually. It shells out to the system `curl` binary. Data (templates, environments, history) is persisted to `~/.config/lazycurl/`.

**Status:** Pre-alpha, actively developed. Requires Zig 0.15.1+ and curl installed on the system.

## Migration: libvaxis → zithril

The upstream lazycurl uses libvaxis for terminal rendering. This fork is migrating the UI layer to zithril. Key differences:

- **zithril** uses immediate-mode rendering (describe entire UI every frame, no retained widget tree)
- **zithril** has explicit state management (framework never allocates behind your back)
- **zithril** uses a constraint-based layout system (`.length()`, `.flex()`, `.ratio()`)
- **zithril** event loop: Event → Update → View → Render
- Built-in widgets: Text, Paragraph, Block, List, Table, Gauge, Tabs, Scrollbar

When working on this codebase: **use zithril APIs, do not introduce new libvaxis dependencies.**

When you encounter missing features, bugs, or API gaps in zithril during the migration, open an issue at https://github.com/hotschmoe/zithril/issues so the framework can mature alongside this effort.

Files most affected by the migration: `src/main.zig` (event loop), `src/lazycurl/app.zig` (vaxis event types), and everything under `src/lazycurl/ui/` (all rendering code).

## Build & Development Commands

```bash
# Dev helper script (preferred)
./dev.sh run          # Compile and run
./dev.sh test         # Run all unit tests
./dev.sh fmt          # Format Zig sources
./dev.sh fetch        # Download dependencies

# Direct zig commands
zig build run                                    # Run application
zig build test                                   # Run all tests
zig build fmt                                    # Format code
zig build --fetch                                # Fetch dependencies
zig build -Doptimize=ReleaseSafe                 # Release build
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux  # Cross-compile
```

There is no way to run a single test file independently — `zig build test` runs all 6 test modules defined in `build.zig`. Tests are inline Zig `test` blocks within source files.

## Architecture

The build system (`build.zig`) defines 7 internal modules with explicit dependency edges:

```
lazycurl_core          ← models (CurlCommand, Header, QueryParam, Environment, Template), IDs, Swagger import
lazycurl_command       ← depends on core; CommandBuilder generates curl command strings
lazycurl_execution     ← standalone; CommandExecutor spawns curl subprocess, polls stdout/stderr
lazycurl_text_input    ← standalone; text input/cursor handling
lazycurl_persistence   ← depends on core; save/load templates, environments, history to filesystem
lazycurl_app           ← depends on core, command, execution, persistence, text_input, vaxis; central state machine
lazycurl_ui            ← depends on app, text_input, vaxis; component-based terminal rendering
```

**Entry point:** `src/main.zig` — sets up allocator, initializes App + Runtime + TTY, runs the ~30fps event/render loop.

**Central state:** `src/lazycurl/app.zig` (~2900 lines) — contains `App` struct (all application state), `AppState` enum (`normal`, `editing`, `method_dropdown`, `importing`, `exiting`), `UiState` (active tab, selected field, scroll positions, edit buffers), and all keyboard event handling.

**UI layer:** `src/lazycurl/ui/` — `mod.zig` coordinates rendering; `components/` has one file per panel (url_container, command_display, output_panel, templates_panel, etc.). Shared primitives live in `components/lib/` (boxed drawing, floating panes, key-value controls).

## Git Workflow (from AGENTS.md)

- Keep commits atomic — commit only files you touched, listing each path explicitly.
- Never run destructive git operations (`git reset --hard`, `rm`, `git checkout`/`git restore` to older commits) without explicit user instruction.
- Never amend commits without explicit approval.
- Never edit `.env` or environment variable files.
