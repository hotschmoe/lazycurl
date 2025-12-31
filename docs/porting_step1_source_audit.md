# Step 1 – Source Audit & Feature Checklist

## Modules and Responsibilities (Zig)
- `src/main.zig`: Vaxis bootstrapper that toggles raw mode/alternate screen, owns the event loop, and drives rendering.
- `src/zvrl/app.zig`: Master application state machine – tabs, selection logic, cursor blinking, templates/env/history toggles, and command execution triggers.
- `src/zvrl/command/*`: Curl command builder (`builder.zig`) and env-var substitution helpers.
- `src/zvrl/execution/*`: Executor wrapping `std.process.Child`, streaming output + error messages.
- `src/zvrl/core/models/*`: Data definitions for `CurlCommand`, `RequestBody`, headers, query params, templates, and environments (timestamps + IDs).
- `src/zvrl/persistence/*`: Storage paths and stubbed JSON persistence.
- `src/zvrl/ui/*`: libvaxis theme, layout, and composable widgets (`components/`).
- Docs: `docs/tvrl_design_document.md`, `README.md`, `AGENTS.md`, and `dev.sh` (development workflow helper).

## User-Visible Feature Inventory
- **Layout**: Status bar (app state, messages), left templates tree, method dropdown, URL editor with tabs (URL/Headers/Body/Curl Options), command preview, and output pane.
- **Navigation**: Tab cycling via Tab/Shift+Tab or Ctrl+Right/Left; arrow key navigation inside lists; Ctrl+Q exit; F1 help view; Esc cancels edit dialogs.
- **Templates & History**: Expand/collapse panels, select template to load, maintain execution history list, toggle with Ctrl+T/E/H.
- **Command Builder**: Method picker, URL + query params, headers table with enable/disable, body textarea supporting raw/form/binary, categorized curl option palette (command-line options vs active ones).
- **Environment Handling**: Named environments with variable substitution syntax `{{key[:default]}}`, secrets flag, editing mode.
- **Command Execution**: Build command string in real time, copy to clipboard (Ctrl+C), execute via F5/Ctrl+R, stream stdout/stderr, show exit code/time/errors, store history entry.
- **Keyboard Shortcuts**: Now documented in `README.md` (shortcuts section) – navigation, toggles, creation (`Ctrl+N`), save template (`Ctrl+S`), etc.
- **Persistence Expectations**: Templates, environments, and history survive restarts; secrets encrypted; default templates/environments seeded on first run.

## Rust Dependencies Requiring Zig Replacements
Retired – legacy Rust crates and replacements are no longer active in this repo.

## Migration Acceptance Checklist
- [ ] Zig binary exposes identical panes/layout proportions as described above.
- [ ] All keyboard shortcuts in `README.md` (shortcuts section) behave the same, including template/history toggles and help modal.
- [ ] Command preview updates in real time with identical quoting/ordering logic to the reference command builder.
- [ ] Environment variable substitution accepts `{{var}}` and `{{var:default}}` forms everywhere (URL, headers, body, options).
- [ ] Curl execution pipeline spawns system `curl`, streams stdout/stderr, and surfaces exit code + friendly error text.
- [ ] Templates, environments, and history persist between sessions with initial seed data matching the seeded defaults.
- [ ] Secrets remain masked in UI and encrypted on disk.
- [ ] Body editor supports raw text, form-data, and binary modes with navigation consistent with the intended textarea behavior.
- [ ] UI components (status bar, tabs, option categories, output panel) render with theming equivalent to `Theme::new`.
- [ ] Tests exist for Zig models, command builder, and key App state transitions mirroring the expected coverage.
