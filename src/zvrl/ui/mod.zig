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
    const total_remaining: u16 = if (height > status_h) height - status_h else 0;
    const remaining = if (total_remaining > command_display_h) total_remaining - command_display_h else 0;
    const proposed_main: u16 = if (remaining > 0) @max(@as(u16, 5), (remaining * 3) / 10) else 0;
    const main_h: u16 = if (remaining > 0) @min(remaining, proposed_main) else 0;
    const output_h: u16 = if (remaining > main_h) remaining - main_h else 0;

    const min_url_w: u16 = 20;
    const min_history_w: u16 = 20;
    var left_w: u16 = @min(width, @max(@as(u16, 22), width / 4));
    var method_w: u16 = 15;
    var history_w: u16 = @max(min_history_w, width / 5);

    if (width < left_w + method_w + min_url_w + history_w) {
        const needed = left_w + method_w + min_url_w + history_w - width;
        if (left_w > 16) {
            const shrink = @min(needed, left_w - 16);
            left_w -= shrink;
        }
    }
    if (width < left_w + method_w + min_url_w + history_w) {
        const needed = left_w + method_w + min_url_w + history_w - width;
        if (method_w > 10) {
            const shrink = @min(needed, method_w - 10);
            method_w -= shrink;
        }
    }
    if (width < left_w + method_w + min_url_w + history_w) {
        const needed = left_w + method_w + min_url_w + history_w - width;
        if (history_w > min_history_w) {
            const shrink = @min(needed, history_w - min_history_w);
            history_w -= shrink;
        }
    }

    const url_w: u16 = if (width > left_w + method_w + history_w)
        width - left_w - method_w - history_w
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

    const env_border = if (app.ui.left_panel != null and app.ui.left_panel.? == .environments) theme.accent else theme.border;
    const env_h: u16 = if (total_remaining > 6) 6 else total_remaining;
    if (left_w > 0 and env_h > 0) {
        const env_win = win.child(.{
            .x_off = 0,
            .y_off = status_h,
            .width = left_w,
            .height = env_h,
            .border = .{ .where = .all, .style = env_border },
        });
        components.environment_panel.render(allocator, env_win, app, theme);
    }

    const templates_border = if (app.ui.left_panel != null and app.ui.left_panel.? == .templates) theme.accent else theme.border;
    const templates_h: u16 = if (total_remaining > env_h) total_remaining - env_h else 0;
    if (left_w > 0 and templates_h > 0) {
        const templates_win = win.child(.{
            .x_off = 0,
            .y_off = status_h + env_h,
            .width = left_w,
            .height = templates_h,
            .border = .{ .where = .all, .style = templates_border },
        });
        components.templates_panel.render(allocator, templates_win, app, theme);
    }

    if (method_w > 0) {
        const method_selected = app.ui.left_panel == null and switch (app.ui.selected_field) {
            .url => |field| field == .method,
            else => false,
        };
        const method_border = if (method_selected or app.state == .method_dropdown) theme.accent else theme.border;
        const method_win = win.child(.{
            .x_off = left_w,
            .y_off = status_h,
            .width = method_w,
            .height = main_h,
            .border = .{ .where = .all, .style = method_border },
        });
        components.command_builder.render(allocator, method_win, app, theme);
    }

    if (url_w > 0 and main_h > 0) {
        const url_win = win.child(.{
            .x_off = left_w + method_w,
            .y_off = status_h,
            .width = url_w,
            .height = main_h,
        });
        components.url_container.render(allocator, url_win, app, theme);
    }

    if (history_w > 0 and main_h > 0) {
        const history_border = if (app.ui.left_panel != null and app.ui.left_panel.? == .history) theme.accent else theme.border;
        const history_win = win.child(.{
            .x_off = left_w + method_w + url_w,
            .y_off = status_h,
            .width = history_w,
            .height = main_h,
            .border = .{ .where = .all, .style = history_border },
        });
        components.history_panel.render(allocator, history_win, app, theme);
    }

    const command_preview = try app.buildCommandPreview(allocator);

    const command_w: u16 = if (width > left_w) width - left_w else 0;
    if (command_w > 0 and command_display_h > 0) {
        const command_win = win.child(.{
            .x_off = left_w,
            .y_off = status_h + main_h,
            .width = command_w,
            .height = command_display_h,
            .border = .{ .where = .all, .style = theme.border },
        });
        components.command_display.render(command_win, command_preview, theme);
    }

    if (command_w > 0 and output_h > 0) {
        const output_win = win.child(.{
            .x_off = left_w,
            .y_off = status_h + main_h + command_display_h,
            .width = command_w,
            .height = output_h,
            .border = .{ .where = .all, .style = theme.border },
        });
        components.output_panel.render(allocator, output_win, runtime, theme);
    }
}
