const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("../theme.zig");

pub fn render(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    drawLine(win, 0, "Templates", theme.title);
    const count = app.templates.items.len;
    const selected = app.ui.selected_template;

    var buffer: [128]u8 = undefined;
    const info = std.fmt.bufPrint(&buffer, "Count: {d}", .{count}) catch return;
    drawLine(win, 1, info, theme.muted);

    if (selected) |idx| {
        const sel = std.fmt.bufPrint(&buffer, "Selected: {d}", .{idx + 1}) catch return;
        drawLine(win, 2, sel, theme.accent);
    } else {
        drawLine(win, 2, "Selected: none", theme.muted);
    }
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}
