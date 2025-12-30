const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("theme.zig");
const components = @import("components/mod.zig");

pub fn render(
    win: vaxis.Window,
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
) !void {
    const theme = theme_mod.Theme{};
    const width = win.width;
    const height = win.height;

    const status_h: u16 = 4;
    const command_display_h: u16 = 4;
    const remaining = if (height > status_h) height - status_h else 0;
    const output_h: u16 = if (remaining > command_display_h) remaining / 3 else 0;
    const main_h: u16 = if (remaining > command_display_h + output_h) remaining - command_display_h - output_h else 0;

    const templates_w: u16 = @max(20, width / 4);
    const builder_w: u16 = if (width > templates_w) width - templates_w else width;

    const status_win = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = width,
        .height = status_h,
        .border = .{ .where = .all, .style = theme.border },
    });
    components.status_bar.render(status_win, app, theme);

    const templates_win = win.child(.{
        .x_off = 0,
        .y_off = status_h,
        .width = templates_w,
        .height = main_h,
        .border = .{ .where = .all, .style = theme.border },
    });
    components.templates_panel.render(templates_win, app, theme);

    const builder_win = win.child(.{
        .x_off = templates_w,
        .y_off = status_h,
        .width = builder_w,
        .height = main_h,
        .border = .{ .where = .all, .style = theme.border },
    });
    components.command_builder.render(builder_win, app, theme);

    const command_preview = try app.executeCommand();
    defer app.allocator.free(command_preview);

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
    components.output_panel.render(output_win, runtime, theme);
}
