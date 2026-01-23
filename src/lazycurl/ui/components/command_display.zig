const std = @import("std");
const vaxis = @import("vaxis");
const theme_mod = @import("../theme.zig");
const boxed = @import("boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    command_preview: []const u8,
    theme: theme_mod.Theme,
) void {
    const inner = boxed.begin(allocator, win, "Command Preview", "", theme.border, theme.title, theme.muted);
    drawWrapped(inner, 0, command_preview, theme.text);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawWrapped(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .grapheme });
}
