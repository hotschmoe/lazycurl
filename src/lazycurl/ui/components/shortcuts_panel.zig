const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");

pub fn render(allocator: std.mem.Allocator, win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (win.height == 0) return;
    const line = buildShortcutLine(allocator, app) catch return;
    if (line.len == 0) return;
    drawLine(win, 0, line, theme.muted);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn buildShortcutLine(allocator: std.mem.Allocator, app: *app_mod.App) ![]const u8 {
    const context = shortcutLines(app);
    const base = if (baseAvailable(app)) baseLines() else &[_][]const u8{};
    return joinLineGroups(allocator, base, context);
}

fn joinLineGroups(
    allocator: std.mem.Allocator,
    first: []const []const u8,
    second: []const []const u8,
) ![]const u8 {
    const total = first.len + second.len;
    if (total == 0) return "";
    var joined = try std.ArrayList(u8).initCapacity(allocator, 0);
    try joined.ensureTotalCapacity(allocator, 64);
    var idx: usize = 0;
    for (first) |entry| {
        if (idx > 0) try joined.appendSlice(allocator, " | ");
        try joined.appendSlice(allocator, entry);
        idx += 1;
    }
    for (second) |entry| {
        if (idx > 0) try joined.appendSlice(allocator, " | ");
        try joined.appendSlice(allocator, entry);
        idx += 1;
    }
    return joined.toOwnedSlice(allocator);
}

fn baseLines() []const []const u8 {
    return &[_][]const u8{
        "Ctrl+R/F5: Run",
        "Ctrl+X/F10: Quit",
        "Ctrl+I: Import Swagger",
        "PgUp/PgDn: Scroll Output",
    };
}

const nav_method = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Change",
    "Tab/Shift+Tab: Switch",
};

const nav_url = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Edit",
    "Tab/Shift+Tab: Switch",
};

const nav_headers = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Edit",
    "Space: Toggle",
    "Tab/Shift+Tab: Switch",
};

const nav_body = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Edit",
    "Tab/Shift+Tab: Switch",
};

const nav_options = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Edit",
    "Tab/Shift+Tab: Switch",
};

const nav_templates = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Load",
    "F2: Rename",
    "F3: Save Template",
    "F4: New Folder",
    "Delete: Remove",
    "Ctrl+Z: Undo Delete",
    "Ctrl+D: Duplicate",
};

const nav_environments = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Select",
};

const nav_history = &[_][]const u8{
    "↑↓←→: Navigate",
    "Enter: Load",
};

const edit_single = &[_][]const u8{
    "Enter: Save",
    "Esc: Cancel",
};

const edit_body_insert = &[_][]const u8{
    "Ctrl+S/F2: Save",
    "Esc: Normal",
    "Enter: Newline",
};

const edit_body_normal = &[_][]const u8{
    "i/a: Insert",
    "h/j/k/l: Move",
    "w/b: Word",
    "0/$: Line",
    "x: Delete",
    "o/O: Newline",
    "Esc: Exit",
};

const method_dropdown = &[_][]const u8{
    "↑↓: Select",
    "Enter: Apply",
    "Esc: Cancel",
};

const import_source = &[_][]const u8{
    "←→: Source",
    "↑↓: Focus",
    "Tab: Next",
    "Ctrl+Enter: Import",
    "Esc: Cancel",
};

const import_input_paste = &[_][]const u8{
    "PgUp/PgDn: Scroll",
    "Tab: Next",
    "Ctrl+Enter: Import",
    "Esc: Cancel",
};

const import_input_line = &[_][]const u8{
    "↑↓: Focus",
    "Tab: Next",
    "Ctrl+Enter: Import",
    "Esc: Cancel",
};

const import_folder = &[_][]const u8{
    "←→: Folder",
    "↑↓: Focus",
    "Tab: Next",
    "Ctrl+Enter: Import",
    "Esc: Cancel",
};

const import_actions = &[_][]const u8{
    "←→: Select",
    "↑↓: Focus",
    "Enter: Apply",
    "Ctrl+Enter: Import",
    "Esc: Cancel",
};

fn shortcutLines(app: *app_mod.App) []const []const u8 {
    return switch (app.state) {
        .importing => importLines(app),
        .editing => editingLines(app),
        .method_dropdown => method_dropdown,
        .normal => navLines(app),
        .exiting => &[_][]const u8{},
    };
}

fn navLines(app: *app_mod.App) []const []const u8 {
    return switch (app.navBox()) {
        .method => nav_method,
        .url => nav_url,
        .headers => nav_headers,
        .body => nav_body,
        .options => nav_options,
        .templates => nav_templates,
        .environments => nav_environments,
        .history => nav_history,
    };
}

fn editingLines(app: *app_mod.App) []const []const u8 {
    if (app.editing_field == .body) {
        return switch (app.ui.body_mode) {
            .insert => edit_body_insert,
            .normal => edit_body_normal,
        };
    }
    if (app.editing_field == null) return &[_][]const u8{};
    return edit_single;
}

fn importLines(app: *app_mod.App) []const []const u8 {
    return switch (app.ui.import_focus) {
        .source => import_source,
        .input => switch (app.ui.import_source) {
            .paste => import_input_paste,
            .file, .url => import_input_line,
        },
        .folder => import_folder,
        .actions => import_actions,
    };
}

fn baseAvailable(app: *app_mod.App) bool {
    return app.state == .normal;
}
