const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("theme.zig");
const components = @import("components/mod.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
) !void {
    const theme = theme_mod.Theme{};
    const width = area.width;
    const height = area.height;

    const status_h: u16 = 6;
    const shortcuts_h: u16 = 1;
    const total_remaining: u16 = if (height > status_h + shortcuts_h) height - status_h - shortcuts_h else 0;
    const min_main_h: u16 = 11;
    const min_output_h: u16 = 4;
    var command_display_h: u16 = 4;
    var main_h: u16 = 0;
    var output_h: u16 = 0;
    if (total_remaining > 0) {
        if (total_remaining <= min_main_h) {
            command_display_h = 0;
            main_h = total_remaining;
        } else {
            if (total_remaining < min_main_h + 2) {
                command_display_h = 1;
            } else if (total_remaining < min_main_h + 4) {
                command_display_h = 2;
            }
            const remaining = if (total_remaining > command_display_h) total_remaining - command_display_h else 0;
            const proposed_main: u16 = @max(min_main_h, (remaining * 6) / 10);
            main_h = @min(remaining, proposed_main);
            output_h = if (remaining > main_h) remaining - main_h else 0;
        }
    }
    if (total_remaining > 0 and total_remaining > command_display_h) {
        const remaining = total_remaining - command_display_h;
        const desired_output = @min(remaining, min_output_h);
        if (output_h < desired_output) {
            output_h = desired_output;
            main_h = if (remaining > output_h) remaining - output_h else 0;
        }
    }

    const min_url_w: u16 = 20;
    const min_history_w: u16 = 16;
    var left_w: u16 = @min(width, @max(@as(u16, 28), width / 3));
    var method_w: u16 = 15;
    var history_w: u16 = @max(min_history_w, width / 8);

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

    if (width > 0 and status_h > 0) {
        const status_area = zithril.Rect.init(area.x, area.y, width, status_h);
        components.status_bar.render(allocator, status_area, buf, app, theme);
    }

    if (width > 0 and shortcuts_h > 0 and height >= shortcuts_h) {
        const shortcuts_area = zithril.Rect.init(area.x, area.y + height - shortcuts_h, width, shortcuts_h);
        components.shortcuts_panel.render(allocator, shortcuts_area, buf, app, theme);
    }

    const env_h: u16 = if (total_remaining > 6) 6 else total_remaining;
    if (left_w > 0 and env_h > 0) {
        const env_area = zithril.Rect.init(area.x, area.y + status_h, left_w, env_h);
        components.environment_panel.render(allocator, env_area, buf, app, theme);
    }

    const templates_h: u16 = if (total_remaining > env_h) total_remaining - env_h else 0;
    if (left_w > 0 and templates_h > 0) {
        const templates_area = zithril.Rect.init(area.x, area.y + status_h + env_h, left_w, templates_h);
        components.templates_panel.render(allocator, templates_area, buf, app, theme);
    }
    if (history_w > 0 and main_h > 0) {
        const history_area = zithril.Rect.init(area.x + left_w + method_w + url_w, area.y + status_h, history_w, main_h);
        components.history_panel.render(allocator, history_area, buf, app, theme);
    }

    if (method_w > 0) {
        const method_area = zithril.Rect.init(area.x + left_w, area.y + status_h, method_w, main_h);
        components.command_builder.render(allocator, method_area, buf, app, theme);
    }

    if (url_w > 0 and main_h > 0) {
        const url_area = zithril.Rect.init(area.x + left_w + method_w, area.y + status_h, url_w, main_h);
        components.url_container.render(allocator, url_area, buf, app, theme);
    }

    const command_preview = try app.buildCommandPreview(allocator);
    app.ui.command_copy_rect = null;

    const command_w: u16 = if (width > left_w) width - left_w else 0;
    if (command_w > 0 and command_display_h > 0) {
        const command_area = zithril.Rect.init(area.x + left_w, area.y + status_h + main_h, command_w, command_display_h);
        components.command_display.render(command_area, buf, app, command_preview, theme);
    }

    if (command_w > 0 and output_h > 0) {
        const output_area = zithril.Rect.init(area.x + left_w, area.y + status_h + main_h + command_display_h, command_w, output_h);
        components.output_panel.render(output_area, buf, app, runtime, theme);
    } else {
        app.ui.output_rect = null;
        app.ui.output_copy_rect = null;
        app.ui.output_format_rect = null;
        app.updateOutputMetrics(0, 0);
    }

    if (app.state == .importing) {
        components.swagger_import_panel.render(allocator, area, buf, app, theme);
    }
}
