const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (win.height == 0) return;
    const focused = app.ui.left_panel != null and app.ui.left_panel.? == .environments;
    var header_style = if (focused) theme.accent else theme.title;
    if (focused) header_style.reverse = true;
    const title = std.fmt.allocPrint(allocator, "Environments ({d})", .{app.environments.items.len}) catch return;
    const border_style = if (focused) theme.accent else theme.border;
    const inner = boxed.begin(allocator, win, title, "", border_style, header_style, theme.muted);

    if (!app.ui.environments_expanded) return;

    const available = inner.height;
    ensureScroll(&app.ui.environments_scroll, app.ui.selected_environment, app.environments.items.len, available);

    var row: u16 = 0;
    var idx: usize = app.ui.environments_scroll;
    var rendered: usize = 0;
    while (idx < app.environments.items.len and row < inner.height and rendered < available) : (idx += 1) {
        const env = app.environments.items[idx];
        const selected = app.ui.selected_environment != null and app.ui.selected_environment.? == idx;
        var style = if (selected and focused) theme.accent else theme.text;
        if (selected and focused) style.reverse = true;
        const marker = if (app.current_environment_index == idx) "*" else " ";
        const prefix = if (selected) ">" else " ";
        const line = std.fmt.allocPrint(allocator, " {s}{s} {s}", .{ marker, prefix, env.name }) catch return;
        drawLine(inner, row, line, style);
        row += 1;
        rendered += 1;
    }
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn ensureScroll(scroll: *usize, selection: ?usize, total: usize, view: usize) void {
    if (total == 0 or view == 0) {
        scroll.* = 0;
        return;
    }
    const idx = selection orelse return;
    if (idx < scroll.*) scroll.* = idx;
    if (idx >= scroll.* + view) scroll.* = idx - view + 1;
    const max_scroll = if (total > view) total - view else 0;
    if (scroll.* > max_scroll) scroll.* = max_scroll;
}
