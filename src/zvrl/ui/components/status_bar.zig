const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("../theme.zig");

pub fn render(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    const title = "Status";
    const state = stateLabel(app.state);
    const tab = tabLabel(app.ui.active_tab);

    drawLine(win, 0, title, theme.title);
    drawKeyValue(win, 1, "State", state, theme);
    drawKeyValue(win, 2, "Tab", tab, theme);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawKeyValue(win: vaxis.Window, row: u16, key: []const u8, value: []const u8, theme: theme_mod.Theme) void {
    var buffer: [128]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "{s}: {s}", .{ key, value }) catch return;
    const segments = [_]vaxis.Segment{.{ .text = line, .style = theme.text }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn stateLabel(state: app_mod.AppState) []const u8 {
    return switch (state) {
        .normal => "normal",
        .editing => "editing",
        .method_dropdown => "method",
        .exiting => "exiting",
    };
}

fn tabLabel(tab: app_mod.Tab) []const u8 {
    return switch (tab) {
        .url => "url",
        .headers => "headers",
        .body => "body",
        .options => "options",
    };
}
