const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("../theme.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    var row: u16 = 0;
    const templates_focus = app.ui.left_panel != null and app.ui.left_panel.? == .templates;
    row = renderSectionHeader(allocator, win, row, "Templates", app.ui.templates_expanded, templates_focus, app.templates.items.len, theme);
    if (app.ui.templates_expanded) {
        row = renderTemplateList(allocator, win, row, app, theme);
    }

    const env_focus = app.ui.left_panel != null and app.ui.left_panel.? == .environments;
    row = renderSectionHeader(allocator, win, row, "Environments", app.ui.environments_expanded, env_focus, app.environments.items.len, theme);
    if (app.ui.environments_expanded) {
        row = renderEnvironmentList(allocator, win, row, app, theme);
    }

    const history_focus = app.ui.left_panel != null and app.ui.left_panel.? == .history;
    row = renderSectionHeader(allocator, win, row, "History", app.ui.history_expanded, history_focus, app.history.items.len, theme);
    if (app.ui.history_expanded) {
        _ = renderHistoryList(allocator, win, row, app, theme);
    }
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn renderSectionHeader(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    row: u16,
    title: []const u8,
    expanded: bool,
    focused: bool,
    count: usize,
    theme: theme_mod.Theme,
) u16 {
    if (row >= win.height) return row;
    const indicator = if (expanded) "v" else ">";
    const line = std.fmt.allocPrint(allocator, "{s} {s} ({d})", .{ indicator, title, count }) catch return row;
    var style = theme.title;
    if (focused) {
        style = theme.accent;
        style.reverse = true;
    }
    drawLine(win, row, line, style);
    return row + 1;
}

fn renderTemplateList(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    start_row: u16,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) u16 {
    if (start_row >= win.height) return start_row;
    if (app.templates.items.len == 0) {
        drawLine(win, start_row, "  (none)", theme.muted);
        return start_row + 1;
    }

    var row = start_row;
    const focus = app.ui.left_panel != null and app.ui.left_panel.? == .templates;
    var idx: usize = app.ui.templates_scroll;
    while (idx < app.templates.items.len and row < win.height) : (idx += 1) {
        const template = app.templates.items[idx];
        const selected = app.ui.selected_template != null and app.ui.selected_template.? == idx;
        var style = if (selected and focus) theme.accent else theme.text;
        if (selected and focus) style.reverse = true;
        const prefix = if (selected) ">" else " ";
        const line = std.fmt.allocPrint(allocator, " {s} {s}", .{ prefix, template.name }) catch return row;
        drawLine(win, row, line, style);
        row += 1;
    }
    return row;
}

fn renderEnvironmentList(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    start_row: u16,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) u16 {
    if (start_row >= win.height) return start_row;
    if (app.environments.items.len == 0) {
        drawLine(win, start_row, "  (none)", theme.muted);
        return start_row + 1;
    }

    var row = start_row;
    const focus = app.ui.left_panel != null and app.ui.left_panel.? == .environments;
    var idx: usize = app.ui.environments_scroll;
    while (idx < app.environments.items.len and row < win.height) : (idx += 1) {
        const env = app.environments.items[idx];
        const selected = app.ui.selected_environment != null and app.ui.selected_environment.? == idx;
        var style = if (selected and focus) theme.accent else theme.text;
        if (selected and focus) style.reverse = true;
        const marker = if (app.current_environment_index == idx) "*" else " ";
        const prefix = if (selected) ">" else " ";
        const line = std.fmt.allocPrint(allocator, " {s}{s} {s}", .{ marker, prefix, env.name }) catch return row;
        drawLine(win, row, line, style);
        row += 1;
    }
    return row;
}

fn renderHistoryList(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    start_row: u16,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) u16 {
    if (start_row >= win.height) return start_row;
    if (app.history.items.len == 0) {
        drawLine(win, start_row, "  (none)", theme.muted);
        return start_row + 1;
    }

    var row = start_row;
    const focus = app.ui.left_panel != null and app.ui.left_panel.? == .history;
    var idx: usize = app.ui.history_scroll;
    while (idx < app.history.items.len and row < win.height) : (idx += 1) {
        const command = app.history.items[idx];
        const selected = app.ui.selected_history != null and app.ui.selected_history.? == idx;
        var style = if (selected and focus) theme.accent else theme.text;
        if (selected and focus) style.reverse = true;
        const prefix = if (selected) ">" else " ";
        const line = std.fmt.allocPrint(allocator, " {s} {s}", .{ prefix, command.name }) catch return row;
        drawLine(win, row, line, style);
        row += 1;
    }
    return row;
}
