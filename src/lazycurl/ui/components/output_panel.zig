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
    app.ui.output_format_rect = null;

    const copy_style = copyLabelStyle(runtime, app, theme);
    const copy_label = if (app.ui.output_copy_until_ms > std.time.milliTimestamp()) "[Copied]" else "[Copy]";
    const stdout_raw = runtimeOutput(runtime, .stdout);
    const stdout_text = app.ui.output_override orelse stdout_raw;

    const status_code = parseStatusMarkerInText(stdout_raw) orelse parseLastHttpCode(stdout_raw);
    var status_buf: [32]u8 = undefined;
    const status_label = statusBorderLabel(runtime, status_code, &status_buf);
    const status_style = httpStatusStyleFromCode(status_code, theme, runtime.active_job != null);
    var time_buf: [32]u8 = undefined;
    const time_label = timeBorderLabel(runtime, &time_buf);
    var right_labels_buf: [2]boxed.RightLabel = undefined;
    var right_count: usize = 0;
    if (status_label.len > 0) {
        right_labels_buf[right_count] = .{ .text = status_label, .style = status_style };
        right_count += 1;
    }
    if (time_label.len > 0) {
        right_labels_buf[right_count] = .{ .text = time_label, .style = theme.muted };
        right_count += 1;
    }
    const inner = boxed.beginWithBottomLabelRightLabels(
        allocator,
        win,
        "Output",
        right_labels_buf[0..right_count],
        copy_label,
        theme.border,
        theme.title,
        copy_style,
    );
    app.ui.output_copy_rect = bottomLabelRect(win, copy_label);
    const format_enabled = stdout_text.len > 0;
    const format_style = if (format_enabled) theme.accent else theme.muted;
    app.ui.output_format_rect = if (format_enabled)
        formatLabelRect(win, copy_label, "[JSON]", format_style, theme.border)
    else
        null;

    const body_start: u16 = 0;
    const body_height: u16 = inner.height;
    const total_lines = countLines(stdout_text);
    const content_width: u16 = inner.width;
    app.updateOutputMetrics(total_lines, body_height);
    if (body_height > 0 and content_width > 0) {

        _ = drawOutputBody(
            inner,
            body_start,
            body_height,
            stdout_text,
            app.ui.output_scroll,
            theme,
            content_width,
        );
    }
}

const OutputKind = enum { stdout, stderr };

const status_marker_prefix = "__LAZYCURL_HTTP_STATUS__";

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

fn formatLabelRect(
    win: vaxis.Window,
    left_label: []const u8,
    label: []const u8,
    text_style: vaxis.Style,
    border_style: vaxis.Style,
) ?app_mod.PanelRect {
    if (label.len == 0 or win.width == 0 or win.height == 0) return null;
    const padded_left = left_label.len + 4 < win.width;
    const left_width: u16 = @intCast(if (padded_left) left_label.len + 2 else left_label.len);
    if (left_width == 0 or 1 + left_width >= win.width) return null;
    const start_col: u16 = 1 + left_width + 1;
    if (start_col >= win.width) return null;
    const padded = label.len + 4 < win.width;
    const label_width: u16 = @intCast(if (padded) label.len + 2 else label.len);
    if (label_width == 0) return null;
    if (start_col + label_width >= win.width) return null;
    drawBottomLabel(win, start_col, label, text_style, border_style, padded);
    const row: u16 = win.height - 1;
    return .{
        .x = win.x_off + @as(i17, @intCast(start_col)),
        .y = win.y_off + @as(i17, @intCast(row)),
        .width = label_width,
        .height = 1,
    };
}

fn drawBottomLabel(
    win: vaxis.Window,
    col: u16,
    text: []const u8,
    text_style: vaxis.Style,
    border_style: vaxis.Style,
    padded: bool,
) void {
    if (text.len == 0 or col >= win.width or win.height == 0) return;
    const row: u16 = win.height - 1;
    if (padded) {
        const segments = [_]vaxis.Segment{
            .{ .text = " ", .style = border_style },
            .{ .text = text, .style = text_style },
            .{ .text = " ", .style = border_style },
        };
        _ = win.print(segments[0..], .{ .row_offset = row, .col_offset = col, .wrap = .none });
        return;
    }
    const segments = [_]vaxis.Segment{
        .{ .text = text, .style = text_style },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .col_offset = col, .wrap = .none });
}

fn copyLabelStyle(runtime: *app_mod.Runtime, app: *app_mod.App, theme: theme_mod.Theme) vaxis.Style {
    const now_ms = std.time.milliTimestamp();
    const copied = now_ms <= app.ui.output_copy_until_ms;
    const has_output = runtime.outputBody().len > 0;
    return if (!has_output) theme.muted else if (copied) theme.success else theme.accent;
}

fn parseStatusMarkerInText(text: []const u8) ?u16 {
    var last_code: ?u16 = null;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (parseStatusMarkerLine(line)) |code| last_code = code;
    }
    return last_code;
}

fn parseStatusMarkerLine(line: []const u8) ?u16 {
    if (!std.mem.startsWith(u8, line, status_marker_prefix)) return null;
    const rest = std.mem.trim(u8, line[status_marker_prefix.len..], " \t\r");
    var idx: usize = 0;
    while (idx < rest.len and std.ascii.isDigit(rest[idx])) : (idx += 1) {}
    if (idx == 0) return null;
    return std.fmt.parseInt(u16, rest[0..idx], 10) catch null;
}

fn httpStatusLabelFromCode(code: ?u16, buf: []u8) []const u8 {
    if (code) |value| {
        return std.fmt.bufPrint(buf, "HTTP {d}", .{value}) catch "";
    }
    return "";
}

fn statusBorderLabel(runtime: *app_mod.Runtime, code: ?u16, buf: []u8) []const u8 {
    if (code != null) return httpStatusLabelFromCode(code, buf);
    if (runtime.active_job != null) return "Status: running";
    if (runtime.last_result != null) return "Status: complete";
    return "";
}

fn timeBorderLabel(runtime: *app_mod.Runtime, buf: []u8) []const u8 {
    if (runtime.active_job != null) return "";
    const result = runtime.last_result orelse return "";
    const duration_ms = result.duration_ns / std.time.ns_per_ms;
    return std.fmt.bufPrint(buf, "Time: {d} ms", .{duration_ms}) catch "";
}

fn httpStatusStyleFromCode(code: ?u16, theme: theme_mod.Theme, active: bool) vaxis.Style {
    if (active) return theme.accent;
    if (code) |value| return statusStyleForCode(value, theme);
    return theme.muted;
}

fn parseLastHttpCode(text: []const u8) ?u16 {
    var last_code: ?u16 = null;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        const parsed = parseHttpStatusLine(line) orelse continue;
        last_code = parsed.code;
    }
    return last_code;
}

const ParsedHttpStatus = struct {
    code: u16,
    reason: []const u8,
};

fn parseHttpStatusLine(line: []const u8) ?ParsedHttpStatus {
    const start_idx = std.mem.indexOf(u8, line, "HTTP/") orelse return null;
    const view = line[start_idx..];
    const space_idx = std.mem.indexOfScalar(u8, view, ' ') orelse return null;
    var idx = space_idx + 1;
    while (idx < view.len and view[idx] == ' ') : (idx += 1) {}
    const start = idx;
    while (idx < view.len and std.ascii.isDigit(view[idx])) : (idx += 1) {}
    if (start == idx) return null;
    const code = std.fmt.parseInt(u16, view[start..idx], 10) catch return null;
    var reason = view[idx..];
    reason = std.mem.trim(u8, reason, " ");
    return .{ .code = code, .reason = reason };
}

fn statusStyleForCode(code: u16, theme: theme_mod.Theme) vaxis.Style {
    return switch (code / 100) {
        2 => theme.success,
        4 => theme.warning,
        5 => theme.error_style,
        else => theme.text,
    };
}

fn countLines(text: []const u8) usize {
    if (text.len == 0) return 0;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (std.mem.startsWith(u8, line, status_marker_prefix)) continue;
        count += 1;
    }
    return count;
}

fn drawOutputBody(
    win: vaxis.Window,
    start_row: u16,
    height: u16,
    stdout_text: []const u8,
    scroll: usize,
    theme: theme_mod.Theme,
    content_width: u16,
) u16 {
    var row = start_row;
    var skip = scroll;
    const max_row = start_row + height;

    row = drawSection(win, row, max_row, null, theme.muted, stdout_text, theme.text, &skip, content_width);
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
    while (it.next()) |line_raw| {
        if (row >= max_row) break;
        const line = std.mem.trim(u8, line_raw, "\r");
        if (std.mem.startsWith(u8, line, status_marker_prefix)) continue;
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
