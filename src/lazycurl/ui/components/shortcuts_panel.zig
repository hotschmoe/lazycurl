const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");

pub fn render(allocator: std.mem.Allocator, win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (win.height == 0) return;
    if (isBodyEditing(app)) {
        const left = buildBaseLine(allocator) catch return;
        const right = buildBodyLine(allocator, app) catch return;
        const left_len: u16 = @intCast(left.len);
        const right_len: u16 = @intCast(right.len);
        if (right_len > 0 and win.width > right_len and win.width > left_len) {
            const right_col: u16 = win.width - right_len;
            if (right_col > left_len + 1) {
                drawLine(win, 0, left, theme.muted);
                const segment = vaxis.Segment{ .text = right, .style = theme.muted };
                _ = win.print(&.{segment}, .{ .row_offset = 0, .col_offset = right_col, .wrap = .none });
                return;
            }
        }
    }
    const line = buildShortcutLine(allocator, app) catch return;
    drawLine(win, 0, line, theme.muted);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn contextLines(app: *app_mod.App) []const []const u8 {
    if (app.state == .importing) {
        return &[_][]const u8{
            "Tab Next",
            "Esc Cancel",
            "Left/Right Source",
            "Up/Down Folder",
            "PgUp/PgDn Scroll",
            "Ctrl+Enter Import",
        };
    }
    if (app.state == .editing) {
        if (app.editing_field == .body) {
            if (app.ui.body_mode == .insert) {
                return &[_][]const u8{
                    "Ctrl+S/F2 Save",
                    "Enter Newline",
                    "Esc Normal",
                };
            }
            return &[_][]const u8{
                "i/a Insert",
                "h/j/k/l Move",
                "w/b Word",
                "0/$ Line",
                "x Delete",
                "o/O Newline",
                "Esc Exit",
            };
        }
        return &[_][]const u8{
            "Enter Save",
            "Esc Cancel",
        };
    }
    if (app.state == .method_dropdown) {
        return &[_][]const u8{
            "Up/Down Select",
            "Enter Apply",
            "Esc Cancel",
        };
    }
    if (app.ui.left_panel) |panel| {
        return switch (panel) {
            .templates => &[_][]const u8{
                "Enter Load/Toggle",
                "F2 Rename",
                "F3 Save Template",
                "F4 New Folder",
                "F6 Delete Folder",
            },
            .environments => &[_][]const u8{
                "Enter Select",
            },
            .history => &[_][]const u8{
                "Enter Load",
            },
        };
    }
    return &[_][]const u8{
        "Arrows Navigate",
        "Tab/Shift+Tab Switch",
    };
}

fn baseLines() []const []const u8 {
    return &[_][]const u8{
        "Ctrl+R/F5 Run",
        "Ctrl+I Import Swagger",
        "Ctrl+X/F10 Quit",
        "PgUp/PgDn Scroll Output",
    };
}

fn buildBaseLine(allocator: std.mem.Allocator) ![]const u8 {
    return joinLines(allocator, baseLines());
}

fn buildBodyLine(allocator: std.mem.Allocator, app: *app_mod.App) ![]const u8 {
    const context = contextLines(app);
    return joinLines(allocator, context);
}

fn buildShortcutLine(allocator: std.mem.Allocator, app: *app_mod.App) ![]const u8 {
    const base = baseLines();
    const context = contextLines(app);
    const total = base.len + context.len;
    if (total == 0) return "";

    var joined = try std.ArrayList(u8).initCapacity(allocator, 0);
    try joined.ensureTotalCapacity(allocator, 64);
    var idx: usize = 0;
    for (base) |entry| {
        if (idx > 0) try joined.appendSlice(allocator, " | ");
        try joined.appendSlice(allocator, entry);
        idx += 1;
    }
    for (context) |entry| {
        if (idx > 0) try joined.appendSlice(allocator, " | ");
        try joined.appendSlice(allocator, entry);
        idx += 1;
    }
    return joined.toOwnedSlice(allocator);
}

fn joinLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]const u8 {
    if (lines.len == 0) return "";
    var joined = try std.ArrayList(u8).initCapacity(allocator, 0);
    try joined.ensureTotalCapacity(allocator, 64);
    var idx: usize = 0;
    for (lines) |entry| {
        if (idx > 0) try joined.appendSlice(allocator, " | ");
        try joined.appendSlice(allocator, entry);
        idx += 1;
    }
    return joined.toOwnedSlice(allocator);
}

fn isBodyEditing(app: *app_mod.App) bool {
    return app.state == .editing and app.editing_field != null and app.editing_field.? == .body;
}
