const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    command_preview: []const u8,
    theme: theme_mod.Theme,
) void {
    const inner = boxed.begin(allocator, area, buf, "Command Preview", "[Copy]", theme.border, theme.title, theme.accent);
    app.ui.command_copy_rect = copyRect(area, "[Copy]");
    drawWrapped(inner, buf, 0, command_preview, theme.text);
}

fn copyRect(area: zithril.Rect, label: []const u8) ?app_mod.PanelRect {
    const label_len = label.len;
    if (label_len == 0 or area.width == 0) return null;
    const padded = label_len + 4 < area.width;
    const width: u16 = @intCast(if (padded) label_len + 2 else label_len);
    const col: u16 = @intCast(@max(@as(usize, 1), area.width - 1 - width));
    return .{
        .x = area.x + @as(i17, @intCast(col)),
        .y = area.y,
        .width = width,
        .height = 1,
    };
}

fn drawWrapped(area: zithril.Rect, buf: *zithril.Buffer, start_row: u16, text: []const u8, style: zithril.Style) void {
    if (area.height == 0 or area.width == 0 or text.len == 0) return;
    var row = start_row;
    var remaining = text;
    while (remaining.len > 0 and row < area.height) {
        const line_len = @min(remaining.len, @as(usize, area.width));
        buf.setString(area.x, area.y + row, remaining[0..line_len], style);
        remaining = remaining[line_len..];
        row += 1;
    }
}
