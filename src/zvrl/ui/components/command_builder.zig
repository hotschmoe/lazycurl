const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("../theme.zig");

pub fn render(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    drawLine(win, 0, "Command Builder", theme.title);

    const method = app.current_command.method orelse .get;
    var buffer: [128]u8 = undefined;
    const method_line = std.fmt.bufPrint(&buffer, "Method: {s}", .{method.asString()}) catch return;
    drawLine(win, 1, method_line, theme.text);

    drawLine(win, 2, "URL:", theme.muted);
    drawLine(win, 3, app.current_command.url, theme.text);

    const tab = tabLabel(app.ui.active_tab);
    const tab_line = std.fmt.bufPrint(&buffer, "Active Tab: {s}", .{tab}) catch return;
    drawLine(win, 5, tab_line, theme.muted);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn tabLabel(tab: app_mod.Tab) []const u8 {
    return switch (tab) {
        .url => "url",
        .headers => "headers",
        .body => "body",
        .options => "options",
    };
}
