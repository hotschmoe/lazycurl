const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");

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

    drawHeader(win, runtime, theme, app);

    const status_line = if (runtime.active_job != null)
        "Status: running"
    else if (runtime.last_result != null)
        "Status: complete"
    else
        "Status: idle";

    const status_style = if (runtime.active_job != null) theme.accent else if (runtime.last_result != null) theme.text else theme.muted;
    drawLine(win, 1, status_line, status_style);

    var row: u16 = 2;
    if (runtime.last_result) |result| {
        const exit_line = if (result.exit_code) |code|
            std.fmt.allocPrint(allocator, "Exit: {d}", .{code}) catch return
        else
            std.fmt.allocPrint(allocator, "Exit: unknown", .{}) catch return;
        const exit_style = if (result.exit_code != null and result.exit_code.? == 0) theme.success else theme.error_style;
        drawLine(win, row, exit_line, exit_style);
        row += 1;

        const duration_ms = result.duration_ns / std.time.ns_per_ms;
        const dur_line = std.fmt.allocPrint(allocator, "Time: {d} ms", .{duration_ms}) catch return;
        drawLine(win, row, dur_line, theme.muted);
        row += 1;
    }

    const body_start = row;
    const body_height: u16 = if (win.height > body_start) win.height - body_start else 0;
    const stdout_text = runtimeOutput(runtime, .stdout);
    const stderr_text = runtimeOutput(runtime, .stderr);
    const total_lines = countLines(stdout_text) + countLines(stderr_text) + 2;
    app.updateOutputMetrics(total_lines, body_height);

    if (body_height > 0) {
        _ = drawOutputBody(
            win,
            body_start,
            body_height,
            stdout_text,
            stderr_text,
            app.ui.output_scroll,
            theme,
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

fn drawHeader(win: vaxis.Window, runtime: *app_mod.Runtime, theme: theme_mod.Theme, app: *app_mod.App) void {
    drawLine(win, 0, "Output", theme.title);
    const now_ms = std.time.milliTimestamp();
    const copied = now_ms <= app.ui.output_copy_until_ms;
    const label = if (copied) "[Copied]" else "[Copy]";
    const col = copyLabelCol(win.width, label.len) orelse return;
    const has_output = runtime.outputBody().len > 0 or runtime.outputError().len > 0;
    const style = if (!has_output) theme.muted else if (copied) theme.success else theme.accent;
    const segment = vaxis.Segment{ .text = label, .style = style };
    _ = win.print(&.{segment}, .{ .row_offset = 0, .col_offset = col, .wrap = .none });
    app.ui.output_copy_rect = .{
        .x = win.x_off + @as(i17, @intCast(col)),
        .y = win.y_off,
        .width = @intCast(label.len),
        .height = 1,
    };
}

fn copyLabelCol(width: u16, label_len: usize) ?u16 {
    const needed: u16 = @intCast(label_len + 1);
    if (width <= needed) return null;
    return width - needed;
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
) u16 {
    var row = start_row;
    var skip = scroll;
    const max_row = start_row + height;

    row = drawSection(win, row, max_row, "Stdout:", theme.muted, stdout_text, theme.text, &skip);
    if (row < max_row) {
        row = drawSection(win, row, max_row, "Stderr:", theme.muted, stderr_text, theme.error_style, &skip);
    }
    return row;
}

fn drawSection(
    win: vaxis.Window,
    start_row: u16,
    max_row: u16,
    label: []const u8,
    label_style: vaxis.Style,
    text: []const u8,
    text_style: vaxis.Style,
    skip: *usize,
) u16 {
    var row = start_row;
    if (row >= max_row) return row;

    if (skip.* == 0) {
        drawLine(win, row, label, label_style);
        row += 1;
    } else {
        skip.* -= 1;
    }

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (row >= max_row) break;
        if (skip.* > 0) {
            skip.* -= 1;
            continue;
        }
        drawLine(win, row, line, text_style);
        row += 1;
    }
    return row;
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}
