const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
    theme: theme_mod.Theme,
) void {
    app.ui.output_rect = .{
        .x = win.x_off,
        .y = win.y_off,
        .width = win.width,
        .height = win.height,
    };
    app.ui.output_copy_rect = null;

    const status_style = httpStatusStyle(runtime, theme);
    const copy_style = copyLabelStyle(runtime, app, theme);
    const copy_label = if (app.ui.output_copy_until_ms > std.time.milliTimestamp()) "[Copied]" else "[Copy]";
    var status_buf: [64]u8 = undefined;
    const status_label = httpStatusLabel(runtime, &status_buf);
    const inner = boxed.beginWithBottomLabel(
        allocator,
        win,
        "Output",
        status_label,
        copy_label,
        theme.border,
        theme.title,
        status_style,
        copy_style,
    );
    app.ui.output_copy_rect = bottomLabelRect(win, copy_label);

    const status_line = if (runtime.active_job != null)
        "Status: running"
    else if (runtime.last_result != null)
        "Status: complete"
    else
        "Status: idle";

    var meta_lines: [3]MetaLine = undefined;
    var meta_count: usize = 0;
    meta_lines[meta_count] = .{ .text = status_line, .style = status_style, .row = 0 };
    meta_count += 1;

    if (runtime.last_result) |result| {
        const exit_line = if (result.exit_code) |code|
            std.fmt.allocPrint(allocator, "Exit: {d}", .{code}) catch return
        else
            std.fmt.allocPrint(allocator, "Exit: unknown", .{}) catch return;
        const exit_style = if (result.exit_code != null and result.exit_code.? == 0) theme.success else theme.error_style;
        meta_lines[meta_count] = .{ .text = exit_line, .style = exit_style, .row = 1 };
        meta_count += 1;

        const duration_ms = result.duration_ns / std.time.ns_per_ms;
        const dur_line = std.fmt.allocPrint(allocator, "Time: {d} ms", .{duration_ms}) catch return;
        meta_lines[meta_count] = .{ .text = dur_line, .style = theme.muted, .row = 2 };
        meta_count += 1;
    }

    const reserved_width = maxMetaWidth(meta_lines[0..meta_count], inner.height);
    drawMetaLines(inner, meta_lines[0..meta_count], inner.height);

    const body_start: u16 = 0;
    const body_height: u16 = inner.height;
    const stdout_text = runtimeOutput(runtime, .stdout);
    const stderr_text = runtimeOutput(runtime, .stderr);
    const total_lines = countLines(stdout_text) + countLines(stderr_text) + 1;
    const content_width: u16 = if (inner.width > reserved_width) inner.width - reserved_width else 0;
    app.updateOutputMetrics(total_lines, body_height);
    if (body_height > 0 and content_width > 0) {

        _ = drawOutputBody(
            inner,
            body_start,
            body_height,
            stdout_text,
            stderr_text,
            app.ui.output_scroll,
            theme,
            content_width,
        );
    }
}

const OutputKind = enum { stdout, stderr };

fn runtimeOutput(runtime: *app_mod.Runtime, kind: OutputKind) []const u8 {
    if (runtime.active_job != null) {
        return switch (kind) {
            .stdout => runtime.stream_stdout.items,
            .stderr => runtime.stream_stderr.items,
        };
    }
    if (runtime.last_result) |result| {
        return switch (kind) {
            .stdout => result.stdout,
            .stderr => result.stderr,
        };
    }
    return "";
}

fn bottomLabelRect(win: vaxis.Window, label: []const u8) ?app_mod.PanelRect {
    if (label.len == 0 or win.width == 0 or win.height == 0) return null;
    const padded = label.len + 4 < win.width;
    const label_width: u16 = @intCast(if (padded) label.len + 2 else label.len);
    if (1 + label_width >= win.width) return null;
    const row: u16 = win.height - 1;
    return .{
        .x = win.x_off + 1,
        .y = win.y_off + @as(i17, @intCast(row)),
        .width = label_width,
        .height = 1,
    };
}

fn copyLabelStyle(runtime: *app_mod.Runtime, app: *app_mod.App, theme: theme_mod.Theme) vaxis.Style {
    const now_ms = std.time.milliTimestamp();
    const copied = now_ms <= app.ui.output_copy_until_ms;
    const has_output = runtime.outputBody().len > 0 or runtime.outputError().len > 0;
    return if (!has_output) theme.muted else if (copied) theme.success else theme.accent;
}

fn httpStatusLabel(runtime: *app_mod.Runtime, buf: []u8) []const u8 {
    if (runtime.active_job != null) return "";
    if (runtime.last_result == null) return "";
    const stdout_text = runtime.last_result.?.stdout;
    const stderr_text = runtime.last_result.?.stderr;
    if (parseLastHttpStatus(stdout_text, buf)) |label| return label;
    if (parseLastHttpStatus(stderr_text, buf)) |label| return label;
    return "";
}

fn parseLastHttpStatus(text: []const u8, buf: []u8) ?[]const u8 {
    var last_code: ?u16 = null;
    var last_reason: []const u8 = "";
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (!std.mem.startsWith(u8, line, "HTTP/")) continue;
        const space_idx = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        var idx = space_idx + 1;
        while (idx < line.len and line[idx] == ' ') : (idx += 1) {}
        const start = idx;
        while (idx < line.len and std.ascii.isDigit(line[idx])) : (idx += 1) {}
        if (start == idx) continue;
        const code = std.fmt.parseInt(u16, line[start..idx], 10) catch continue;
        var reason = line[idx..];
        reason = std.mem.trim(u8, reason, " ");
        last_code = code;
        last_reason = reason;
    }
    if (last_code == null) return null;
    const reason_trim = if (last_reason.len > 24) last_reason[0..24] else last_reason;
    if (reason_trim.len > 0) {
        return std.fmt.bufPrint(buf, "HTTP {d} {s}", .{ last_code.?, reason_trim }) catch null;
    }
    return std.fmt.bufPrint(buf, "HTTP {d}", .{last_code.?}) catch null;
}

fn httpStatusStyle(runtime: *app_mod.Runtime, theme: theme_mod.Theme) vaxis.Style {
    if (runtime.active_job != null) return theme.accent;
    if (runtime.last_result == null) return theme.muted;
    const stdout_text = runtime.last_result.?.stdout;
    const stderr_text = runtime.last_result.?.stderr;
    if (parseLastHttpCode(stdout_text)) |code| return statusStyleForCode(code, theme);
    if (parseLastHttpCode(stderr_text)) |code| return statusStyleForCode(code, theme);
    return theme.text;
}

fn parseLastHttpCode(text: []const u8) ?u16 {
    var last_code: ?u16 = null;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (!std.mem.startsWith(u8, line, "HTTP/")) continue;
        const space_idx = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        var idx = space_idx + 1;
        while (idx < line.len and line[idx] == ' ') : (idx += 1) {}
        const start = idx;
        while (idx < line.len and std.ascii.isDigit(line[idx])) : (idx += 1) {}
        if (start == idx) continue;
        last_code = std.fmt.parseInt(u16, line[start..idx], 10) catch continue;
    }
    return last_code;
}

fn statusStyleForCode(code: u16, theme: theme_mod.Theme) vaxis.Style {
    return switch (code / 100) {
        2 => theme.success,
        4 => theme.warning,
        5 => theme.error_style,
        else => theme.text,
    };
}

const MetaLine = struct {
    text: []const u8,
    style: vaxis.Style,
    row: u16,
};

fn drawMetaLines(win: vaxis.Window, lines: []const MetaLine, height: u16) void {
    for (lines) |line| {
        if (line.row >= height) continue;
        const col = rightJustifyCol(win.width, line.text.len);
        const segment = vaxis.Segment{ .text = line.text, .style = line.style };
        _ = win.print(&.{segment}, .{ .row_offset = line.row, .col_offset = col, .wrap = .none });
    }
}

fn rightJustifyCol(width: u16, text_len: usize) u16 {
    if (text_len >= width) return 0;
    return width - @as(u16, @intCast(text_len));
}

fn maxMetaWidth(lines: []const MetaLine, height: u16) u16 {
    var max_len: usize = 0;
    for (lines) |line| {
        if (line.row >= height) continue;
        if (line.text.len > max_len) max_len = line.text.len;
    }
    if (max_len == 0) return 0;
    return @as(u16, @intCast(max_len + 1));
}

fn countLines(text: []const u8) usize {
    if (text.len == 0) return 0;
    var count: usize = 1;
    for (text) |byte| {
        if (byte == '\n') count += 1;
    }
    return count;
}

fn drawOutputBody(
    win: vaxis.Window,
    start_row: u16,
    height: u16,
    stdout_text: []const u8,
    stderr_text: []const u8,
    scroll: usize,
    theme: theme_mod.Theme,
    content_width: u16,
) u16 {
    var row = start_row;
    var skip = scroll;
    const max_row = start_row + height;

    row = drawSection(win, row, max_row, null, theme.muted, stdout_text, theme.text, &skip, content_width);
    if (row < max_row) {
        row = drawSection(win, row, max_row, "Stderr:", theme.muted, stderr_text, theme.error_style, &skip, content_width);
    }
    return row;
}

fn drawSection(
    win: vaxis.Window,
    start_row: u16,
    max_row: u16,
    label: ?[]const u8,
    label_style: vaxis.Style,
    text: []const u8,
    text_style: vaxis.Style,
    skip: *usize,
    content_width: u16,
) u16 {
    var row = start_row;
    if (row >= max_row) return row;

    if (label) |actual| {
        if (skip.* == 0) {
            drawLineClipped(win, row, actual, label_style, content_width);
            row += 1;
        } else {
            skip.* -= 1;
        }
    }

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (row >= max_row) break;
        if (skip.* > 0) {
            skip.* -= 1;
            continue;
        }
        drawLineClipped(win, row, line, text_style, content_width);
        row += 1;
    }
    return row;
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawLineClipped(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style, max_width: u16) void {
    if (max_width == 0) return;
    const limit: usize = @intCast(max_width);
    const slice = if (text.len > limit) text[0..limit] else text;
    drawLine(win, row, slice, style);
}
