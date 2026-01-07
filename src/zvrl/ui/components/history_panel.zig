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
    if (win.height == 0) return;
    const focused = app.ui.left_panel != null and app.ui.left_panel.? == .history;
    var header_style = if (focused) theme.accent else theme.title;
    if (focused) header_style.reverse = true;
    const title = std.fmt.allocPrint(allocator, "History ({d})", .{app.history.items.len}) catch return;
    drawLine(win, 0, title, header_style);

    if (!app.ui.history_expanded) return;

    const available = if (win.height > 1) win.height - 1 else 0;
    ensureScroll(&app.ui.history_scroll, app.ui.selected_history, app.history.items.len, available);

    var row: u16 = 1;
    var idx: usize = app.ui.history_scroll;
    var rendered: usize = 0;
    while (idx < app.history.items.len and row < win.height and rendered < available) : (idx += 1) {
        const command = app.history.items[idx];
        const selected = app.ui.selected_history != null and app.ui.selected_history.? == idx;
        var style = if (selected and focused) theme.accent else theme.text;
        if (selected and focused) style.reverse = true;
        const prefix = if (selected) ">" else " ";
        const label = historyLabel(allocator, command) catch return;
        const line = std.fmt.allocPrint(allocator, " {s} {s}", .{ prefix, label }) catch return;
        drawLine(win, row, line, style);
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

fn historyLabel(allocator: std.mem.Allocator, command: anytype) ![]const u8 {
    const method = command.method orelse .get;
    const default_name = "New Command";
    const label = if (command.name.len > 0 and !std.mem.eql(u8, command.name, default_name))
        command.name
    else
        command.url;
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ methodLabel(method), label });
}

fn methodLabel(method: anytype) []const u8 {
    return switch (method) {
        .get => "GET",
        .post => "POST",
        .put => "PUT",
        .delete => "DELETE",
        .patch => "PATCH",
        .head => "HEAD",
        .options => "OPTIONS",
        .trace => "TRACE",
        .connect => "CONNECT",
    };
}
