const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");
const draw = @import("lib/draw.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (area.height == 0) return;
    const focused = app.ui.left_panel != null and app.ui.left_panel.? == .environments;
    const header_style = if (focused) theme.accent.reverse() else theme.title;
    const title = std.fmt.allocPrint(allocator, "Environments ({d})", .{app.environments.items.len}) catch return;
    const border_style = if (focused) theme.accent else theme.border;
    const inner = boxed.begin(area, buf, title, "", border_style, header_style, theme.muted);

    if (!app.ui.environments_expanded) return;

    const available = inner.height;
    draw.ensureScroll(&app.ui.environments_scroll, app.ui.selected_environment, app.environments.items.len, available);

    var row: u16 = 0;
    var idx: usize = app.ui.environments_scroll;
    var rendered: usize = 0;
    while (idx < app.environments.items.len and row < inner.height and rendered < available) : (idx += 1) {
        const env = app.environments.items[idx];
        const selected = app.ui.selected_environment != null and app.ui.selected_environment.? == idx;
        const style = if (selected and focused) theme.accent.reverse() else theme.text;
        const marker = if (app.current_environment_index == idx) "*" else " ";
        const prefix = if (selected) ">" else " ";
        const line = std.fmt.allocPrint(allocator, " {s}{s} {s}", .{ marker, prefix, env.name }) catch return;
        draw.line(inner, buf, row, line, style);
        row += 1;
        rendered += 1;
    }
}
