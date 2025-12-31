const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("theme.zig");
const components = @import("components/mod.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
) !void {
    const theme = theme_mod.Theme{};
    const width = win.width;
    const height = win.height;

    const status_h: u16 = 5;
    const command_display_h: u16 = 4;
    const remaining = if (height > status_h + command_display_h) height - status_h - command_display_h else 0;
    const proposed_main: u16 = if (remaining > 0) @max(@as(u16, 5), (remaining * 3) / 10) else 0;
    const main_h: u16 = if (remaining > 0) @min(remaining, proposed_main) else 0;
    const output_h: u16 = if (remaining > main_h) remaining - main_h else 0;

    const min_url_w: u16 = 20;
    var templates_w: u16 = @min(width, @max(@as(u16, 20), width / 5));
    var method_w: u16 = 15;

    if (width < templates_w + method_w + min_url_w) {
        const needed = templates_w + method_w + min_url_w - width;
        if (templates_w > 12) {
            const shrink = @min(needed, templates_w - 12);
            templates_w -= shrink;
        }
    }
    if (width < templates_w + method_w + min_url_w) {
        const needed = templates_w + method_w + min_url_w - width;
        if (method_w > 10) {
            const shrink = @min(needed, method_w - 10);
            method_w -= shrink;
        }
    }

    const url_w: u16 = if (width > templates_w + method_w)
        width - templates_w - method_w
    else
        0;

    const status_win = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = width,
        .height = status_h,
        .border = .{ .where = .all, .style = theme.border },
    });
    components.status_bar.render(allocator, status_win, app, theme);

    const templates_border = if (app.ui.left_panel != null and app.ui.left_panel.? == .templates) theme.accent else theme.border;
    const templates_win = win.child(.{
        .x_off = 0,
        .y_off = status_h,
        .width = templates_w,
        .height = main_h,
        .border = .{ .where = .all, .style = templates_border },
    });
    components.templates_panel.render(allocator, templates_win, app, theme);

    if (method_w > 0) {
        const method_selected = app.ui.left_panel == null and switch (app.ui.selected_field) {
            .url => |field| field == .method,
            else => false,
        };
        const method_border = if (method_selected or app.state == .method_dropdown) theme.accent else theme.border;
        const method_win = win.child(.{
            .x_off = templates_w,
            .y_off = status_h,
            .width = method_w,
            .height = main_h,
            .border = .{ .where = .all, .style = method_border },
        });
        components.command_builder.render(allocator, method_win, app, theme);
    }

    if (url_w > 0) {
        const url_win = win.child(.{
            .x_off = templates_w + method_w,
            .y_off = status_h,
            .width = url_w,
            .height = main_h,
        });
        components.url_container.render(allocator, url_win, app, theme);
    }

    const command_preview = try app.buildCommandPreview(allocator);

    const command_win = win.child(.{
        .x_off = 0,
        .y_off = status_h + main_h,
        .width = width,
        .height = command_display_h,
        .border = .{ .where = .all, .style = theme.border },
    });
    components.command_display.render(command_win, command_preview, theme);

    const output_win = win.child(.{
        .x_off = 0,
        .y_off = status_h + main_h + command_display_h,
        .width = width,
        .height = output_h,
        .border = .{ .where = .all, .style = theme.border },
    });
    components.output_panel.render(allocator, output_win, runtime, theme);
}
