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
    drawLine(win, 0, "Curl Options", theme.title);

    if (app.current_command.options.items.len == 0) {
        drawLine(win, 1, "No options", theme.muted);
        return;
    }

    var row: u16 = 1;
    for (app.current_command.options.items, 0..) |option, idx| {
        if (row >= win.height) break;
        const enabled = if (option.enabled) "[x]" else "[ ]";
        const is_selected = isOptionSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .option_value and is_selected;
        var style = if (is_selected) theme.accent else theme.text;
        if (is_selected) style.reverse = true;

        if (is_editing) {
            const prefix = std.fmt.allocPrint(allocator, "{s} {s} ", .{ enabled, option.flag }) catch return;
            var cursor_style = style;
            cursor_style.reverse = true;
            drawInputWithCursor(win, row, app.ui.edit_input.slice(), app.ui.edit_input.cursor, style, cursor_style, app.ui.cursor_visible, prefix);
        } else {
            const line = if (option.value) |value|
                std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ enabled, option.flag, value }) catch return
            else
                std.fmt.allocPrint(allocator, "{s} {s}", .{ enabled, option.flag }) catch return;

            drawLine(win, row, line, style);
        }
        row += 1;
    }
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawInputWithCursor(
    win: vaxis.Window,
    row: u16,
    value: []const u8,
    cursor: usize,
    style: vaxis.Style,
    cursor_style: vaxis.Style,
    cursor_visible: bool,
    prefix: []const u8,
) void {
    if (row >= win.height) return;
    const prefix_len: usize = prefix.len;
    const win_width: usize = win.width;
    if (win_width <= prefix_len) {
        const clipped = prefix[0..@min(prefix_len, win_width)];
        const segments = [_]vaxis.Segment{.{ .text = clipped, .style = style }};
        _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
        return;
    }

    const available = win_width - prefix_len;
    const safe_cursor = @min(cursor, value.len);
    var start: usize = 0;
    if (safe_cursor >= available) {
        start = safe_cursor - available + 1;
    }
    const end = @min(value.len, start + available);
    const visible = value[start..end];
    const cursor_pos = safe_cursor - start;
    const before = visible[0..@min(cursor_pos, visible.len)];
    const cursor_char = if (cursor_pos < visible.len) visible[cursor_pos .. cursor_pos + 1] else " ";
    const after = if (cursor_pos < visible.len) visible[cursor_pos + 1 ..] else "";

    var segments: [4]vaxis.Segment = .{
        .{ .text = prefix, .style = style },
        .{ .text = before, .style = style },
        .{ .text = cursor_char, .style = if (cursor_visible) cursor_style else style },
        .{ .text = after, .style = style },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .wrap = .none });
}

fn isOptionSelected(app: *app_mod.App, idx: usize) bool {
    if (app.ui.selected_template != null) return false;
    return switch (app.ui.selected_field) {
        .options => |sel| sel == idx,
        else => false,
    };
}
