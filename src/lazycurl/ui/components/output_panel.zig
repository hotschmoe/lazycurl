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

    const copy_style = copyLabelStyle(runtime, app, theme);
    const copy_label = if (app.ui.output_copy_until_ms > std.time.milliTimestamp()) "[Copied]" else "[Copy]";
    const stdout_raw = runtimeOutput(runtime, .stdout);
    const stderr_raw = runtimeOutput(runtime, .stderr);
    const stdout_text = sanitizeOutput(allocator, stdout_raw);
    const stderr_text = sanitizeOutput(allocator, stderr_raw);
    defer releaseSanitized(allocator, stdout_text);
    defer releaseSanitized(allocator, stderr_text);

    const stdout_filtered = stripStatusMarker(allocator, stdout_text.text);
    const stderr_filtered = stripStatusMarker(allocator, stderr_text.text);
    defer releaseStatusFiltered(allocator, stdout_filtered);
    defer releaseStatusFiltered(allocator, stderr_filtered);

    const status_code = stdout_filtered.code orelse stderr_filtered.code orelse
        parseLastHttpCode(stdout_filtered.text) orelse parseLastHttpCode(stderr_filtered.text);
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

    const body_start: u16 = 0;
    const body_height: u16 = inner.height;
    const total_lines = countLines(stdout_filtered.text) + countLines(stderr_filtered.text) + 1;
    const content_width: u16 = inner.width;
    app.updateOutputMetrics(total_lines, body_height);
    if (body_height > 0 and content_width > 0) {

        _ = drawOutputBody(
            inner,
            body_start,
            body_height,
            stdout_filtered.text,
            stderr_filtered.text,
            app.ui.output_scroll,
            theme,
            content_width,
        );
    }
}

const OutputKind = enum { stdout, stderr };

const status_marker_prefix = "__LAZYCURL_HTTP_STATUS__";

const StatusFilteredText = struct {
    text: []const u8,
    owned: ?[]u8 = null,
    code: ?u16 = null,
};

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

fn releaseStatusFiltered(allocator: std.mem.Allocator, filtered: StatusFilteredText) void {
    if (filtered.owned) |buf| allocator.free(buf);
}

fn stripStatusMarker(allocator: std.mem.Allocator, text: []const u8) StatusFilteredText {
    if (!hasStatusMarkerLine(text, status_marker_prefix)) return .{ .text = text };

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var last_code: ?u16 = null;
    var first = true;

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, status_marker_prefix)) {
            if (parseStatusMarkerLine(line)) |code| last_code = code;
            continue;
        }
        if (!first) {
            _ = out.append(allocator, '\n') catch return .{ .text = text, .code = last_code };
        } else {
            first = false;
        }
        _ = out.appendSlice(allocator, line) catch return .{ .text = text, .code = last_code };
    }

    const owned = out.toOwnedSlice(allocator) catch return .{ .text = text, .code = last_code };
    return .{ .text = owned, .owned = owned, .code = last_code };
}

fn hasStatusMarkerLine(text: []const u8, marker: []const u8) bool {
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, text, idx, marker)) |pos| {
        if (pos == 0 or text[pos - 1] == '\n') return true;
        idx = pos + marker.len;
    }
    return false;
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

const SanitizedText = struct {
    text: []const u8,
    owned: ?[]u8 = null,
};

fn releaseSanitized(allocator: std.mem.Allocator, sanitized: SanitizedText) void {
    if (sanitized.owned) |buf| allocator.free(buf);
}

fn sanitizeOutput(allocator: std.mem.Allocator, text: []const u8) SanitizedText {
    var needs = false;
    for (text) |byte| {
        if (byte == 0x1b or byte == '\r' or (byte < 0x20 and byte != '\n' and byte != '\t')) {
            needs = true;
            break;
        }
    }
    if (!needs) return .{ .text = text };

    var out = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < text.len) {
        const byte = text[i];
        if (byte == 0x1b) {
            if (i + 1 < text.len and text[i + 1] == '[') {
                i += 2;
                while (i < text.len) : (i += 1) {
                    const b = text[i];
                    if (b >= 0x40 and b <= 0x7e) {
                        i += 1;
                        break;
                    }
                }
                continue;
            }
            if (i + 1 < text.len and text[i + 1] == ']') {
                i += 2;
                while (i < text.len) : (i += 1) {
                    const b = text[i];
                    if (b == 0x07) {
                        i += 1;
                        break;
                    }
                    if (b == 0x1b and i + 1 < text.len and text[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                }
                continue;
            }
            i += 1;
            continue;
        }
        if (byte == '\r') {
            _ = out.append(allocator, '\n') catch return .{ .text = text };
            i += 1;
            continue;
        }
        if (byte < 0x20 and byte != '\n' and byte != '\t') {
            i += 1;
            continue;
        }
        _ = out.append(allocator, byte) catch return .{ .text = text };
        i += 1;
    }
    const owned = out.toOwnedSlice(allocator) catch return .{ .text = text };
    return .{ .text = owned, .owned = owned };
}
