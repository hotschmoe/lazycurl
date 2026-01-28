const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    const state = stateLabel(app.state);
    const tab = tabLabel(app.ui.active_tab);
    const inner = boxed.begin(allocator, win, "Status", "", theme.border, theme.title, theme.muted);
    drawKeyPair(allocator, inner, 0, "State", state, "Tab", tab, theme);

    const edit_value = editLabel(app);
    var edit_style = theme.text;
    if (app.state == .editing and app.editing_field != null) {
        edit_style.bold = true;
    }
    drawKeyValueStyled(allocator, inner, 1, "Edit", edit_value, edit_style);

    const env_name = currentEnvironmentName(app);
    drawKeyValue(allocator, inner, 2, "Env", env_name, theme);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawKeyValue(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    row: u16,
    key: []const u8,
    value: []const u8,
    theme: theme_mod.Theme,
) void {
    const line = std.fmt.allocPrint(allocator, "{s}: {s}", .{ key, value }) catch return;
    const segments = [_]vaxis.Segment{.{ .text = line, .style = theme.text }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawKeyValueStyled(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    row: u16,
    key: []const u8,
    value: []const u8,
    style: vaxis.Style,
) void {
    const line = std.fmt.allocPrint(allocator, "{s}: {s}", .{ key, value }) catch return;
    const segments = [_]vaxis.Segment{.{ .text = line, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawKeyPair(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    row: u16,
    key_left: []const u8,
    value_left: []const u8,
    key_right: []const u8,
    value_right: []const u8,
    theme: theme_mod.Theme,
) void {
    const line = std.fmt.allocPrint(allocator, "{s}: {s} | {s}: {s}", .{
        key_left,
        value_left,
        key_right,
        value_right,
    }) catch return;
    const segments = [_]vaxis.Segment{.{ .text = line, .style = theme.text }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn stateLabel(state: app_mod.AppState) []const u8 {
    return switch (state) {
        .normal => "normal",
        .editing => "editing",
        .method_dropdown => "method",
        .importing => "import",
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

fn editLabel(app: *app_mod.App) []const u8 {
    if (app.state != .editing or app.editing_field == null) return "none";
    return switch (app.editing_field.?) {
        .url => "url",
        .method => "method",
        .header_key => "header key",
        .header_value => "header value",
        .query_param_key => "query key",
        .query_param_value => "query value",
        .body => if (app.ui.body_mode == .insert) "body (insert)" else "body (normal)",
        .option_value => "option",
        .template_name => "template name",
        .template_folder => "template folder",
    };
}

fn currentEnvironmentName(app: *app_mod.App) []const u8 {
    if (app.environments.items.len == 0) return "none";
    const index = if (app.current_environment_index < app.environments.items.len)
        app.current_environment_index
    else
        0;
    return app.environments.items[index].name;
}
