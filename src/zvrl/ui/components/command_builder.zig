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
    drawLine(win, 0, "Method", theme.title);

    if (app.state == .method_dropdown) {
        renderDropdown(win, app, theme);
        return;
    }

    const method = app.current_command.method orelse .get;
    const is_selected = isMethodSelected(app);
    var style = if (is_selected) theme.accent else theme.text;
    if (is_selected) style.reverse = true;

    const line = std.fmt.allocPrint(allocator, "{s} v", .{method.asString()}) catch return;
    drawLine(win, 1, line, style);
    drawLine(win, 2, "Enter to change", theme.muted);
}

fn renderDropdown(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    const methods = methodLabels();
    var row: u16 = 1;
    for (methods, 0..) |method, idx| {
        if (row >= win.height) break;
        var style = if (idx == app.ui.method_dropdown_index) theme.accent else theme.text;
        if (idx == app.ui.method_dropdown_index) style.reverse = true;
        drawLine(win, row, method, style);
        row += 1;
    }

    if (row < win.height) {
        drawLine(win, row, "Esc to cancel", theme.muted);
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
