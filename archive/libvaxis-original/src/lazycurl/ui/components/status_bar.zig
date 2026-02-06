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
    const line_state = std.fmt.allocPrint(allocator, "State: {s} | Tab: {s}", .{ state, tab }) catch return;
    drawLine(inner, 0, line_state, theme.text);

    const edit_value = editLabel(app);
    var edit_style = theme.text;
    if (app.state == .editing and app.editing_field != null) {
        edit_style.bold = true;
    }
    const line_edit = std.fmt.allocPrint(allocator, "Edit: {s}", .{edit_value}) catch return;
    drawLine(inner, 1, line_edit, edit_style);

    if (baseAvailable(app)) {
        const right = buildBaseShortcutRows(allocator, inner.width);
        const left_lens = [_]u16{
            @intCast(line_state.len),
            @intCast(line_edit.len),
        };
        drawRightLines(inner, right.lines[0..right.len], &left_lens, theme.muted);
    }
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawRightLines(
    win: vaxis.Window,
    lines: []const []const u8,
    left_lens: []const u16,
    style: vaxis.Style,
) void {
    for (lines, 0..) |line, idx| {
        if (idx >= win.height) break;
        if (line.len == 0) continue;
        const right_len: u16 = @intCast(line.len);
        if (win.width < right_len) continue;
        const left_len: u16 = if (idx < left_lens.len) left_lens[idx] else 0;
        const right_col: u16 = win.width - right_len;
        if (right_col <= left_len + 1) continue;
        const segment = vaxis.Segment{ .text = line, .style = style };
        _ = win.print(&.{segment}, .{ .row_offset = @intCast(idx), .col_offset = right_col, .wrap = .none });
    }
}

const BaseShortcutRows = struct {
    lines: [4][]const u8,
    len: usize,
};

fn buildBaseShortcutRows(allocator: std.mem.Allocator, width: u16) BaseShortcutRows {
    const items = [_][]const u8{
        "Ctrl+R/F5: Run",
        "Ctrl+I: Import Swagger",
        "Ctrl+X/F10: Quit",
        "PgUp/PgDn: Scroll Output",
    };
    const left_w: usize = @max(items[0].len, items[2].len);
    const right_w: usize = @max(items[1].len, items[3].len);
    const block_w: u16 = @intCast(left_w + 3 + right_w);
    if (width >= block_w) {
        const left0 = padRight(allocator, items[0], left_w);
        const right0 = padRight(allocator, items[1], right_w);
        const left1 = padRight(allocator, items[2], left_w);
        const right1 = padRight(allocator, items[3], right_w);
        const row0 = std.fmt.allocPrint(allocator, "{s} | {s}", .{ left0, right0 }) catch items[0];
        const row1 = std.fmt.allocPrint(allocator, "{s} | {s}", .{ left1, right1 }) catch items[2];
        return .{
            .lines = .{ row0, row1, "", "" },
            .len = 2,
        };
    }
    return .{
        .lines = .{ items[0], items[1], items[2], items[3] },
        .len = 4,
    };
}

fn padRight(allocator: std.mem.Allocator, value: []const u8, width: usize) []const u8 {
    if (value.len >= width) return value;
    const buffer = allocator.alloc(u8, width) catch return value;
    @memcpy(buffer[0..value.len], value);
    @memset(buffer[value.len..], ' ');
    return buffer;
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

fn baseAvailable(app: *app_mod.App) bool {
    return app.state == .normal;
}
