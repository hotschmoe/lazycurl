const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const draw = @import("lib/draw.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (app.current_command.options.items.len == 0) {
        draw.line(area, buf, 0, "No options", theme.muted);
        return;
    }

    var row: u16 = 0;
    for (app.current_command.options.items, 0..) |option, idx| {
        if (row >= area.height) break;
        const enabled = if (option.enabled) "[x]" else "[ ]";
        const is_selected = isOptionSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .option_value and is_selected;
        const style = if (is_selected) theme.accent.reverse() else theme.text;

        if (is_editing) {
            const prefix = std.fmt.allocPrint(allocator, "{s} {s} ", .{ enabled, option.flag }) catch return;
            const cursor_style = style.notReverse();
            draw.inputWithCursor(area, buf, row, app.ui.edit_input.slice(), app.ui.edit_input.cursor, style, cursor_style, app.ui.cursor_visible, prefix);
        } else {
            const line = if (option.value) |value|
                std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ enabled, option.flag, value }) catch return
            else
                std.fmt.allocPrint(allocator, "{s} {s}", .{ enabled, option.flag }) catch return;

            draw.line(area, buf, row, line, style);
        }
        row += 1;
    }
}

fn isOptionSelected(app: *app_mod.App, idx: usize) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .options => |sel| sel == idx,
        else => false,
    };
}
