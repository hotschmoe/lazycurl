const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    command_preview: []const u8,
    theme: theme_mod.Theme,
) void {
    const inner = boxed.begin(allocator, win, "Command Preview", "[Copy]", theme.border, theme.title, theme.accent);
    app.ui.command_copy_rect = copyRect(win, "[Copy]");
    drawWrapped(inner, 0, command_preview, theme.text);
}

fn copyRect(win: vaxis.Window, label: []const u8) ?app_mod.PanelRect {
    const label_len = label.len;
    if (label_len == 0 or win.width == 0) return null;
    const padded = label_len + 4 < win.width;
    const width: u16 = @intCast(if (padded) label_len + 2 else label_len);
    const col: u16 = @intCast(@max(@as(usize, 1), win.width - 1 - width));
    return .{
        .x = win.x_off + @as(i17, @intCast(col)),
        .y = win.y_off,
        .width = width,
        .height = 1,
    };
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawWrapped(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .grapheme });
}
