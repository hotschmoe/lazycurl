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
    const method_selected = isMethodSelected(app) or app.state == .method_dropdown;
    const border_style = if (method_selected) theme.accent else theme.border;
    const inner = boxed.begin(allocator, win, "Method", "", border_style, theme.title, theme.muted);
    renderMethodList(allocator, inner, app, theme);
}

fn renderMethodList(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    const methods = methodLabels();
    const current = app.current_command.method orelse .get;
    const is_editing = app.state == .method_dropdown;
    const focused = isMethodSelected(app) or is_editing;
    const selected_index: usize = if (is_editing)
        app.ui.method_dropdown_index
    else
        findMethodIndex(methods, current.asString());

    var row: u16 = 0;
    for (methods, 0..) |method, idx| {
        if (row >= win.height) break;
        const is_current = methodMatches(method, current.asString());
        const selected = idx == selected_index;
        var style = if (is_current) theme.accent else theme.text;
        if (focused and selected) style.reverse = true;

        const marker = if (selected) ">" else " ";
        const current_marker = if (is_current and !selected) "*" else " ";
        const line = std.fmt.allocPrint(allocator, "{s}{s} {s}", .{ marker, current_marker, method }) catch return;
        drawLine(win, row, line, style);
        row += 1;
    }

    if (row < win.height) {
        const hint = if (is_editing) "Enter to select" else "Enter to change";
        drawLine(win, row, hint, theme.muted);
    }
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn isMethodSelected(app: *app_mod.App) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .url => |field| field == .method,
        else => false,
    };
}

fn methodLabels() []const []const u8 {
    return &[_][]const u8{
        "GET",
        "POST",
        "PUT",
        "DELETE",
        "PATCH",
        "HEAD",
        "OPTIONS",
        "TRACE",
        "CONNECT",
    };
}

fn methodMatches(label: []const u8, current: []const u8) bool {
    return std.mem.eql(u8, label, current);
}

fn findMethodIndex(methods: []const []const u8, current: []const u8) usize {
    for (methods, 0..) |label, idx| {
        if (std.mem.eql(u8, label, current)) return idx;
    }
    return 0;
}
