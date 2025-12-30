const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("../theme.zig");

pub fn render(win: vaxis.Window, runtime: *app_mod.Runtime, theme: theme_mod.Theme) void {
    drawLine(win, 0, "Output", theme.title);

    if (runtime.active_job != null) {
        drawLine(win, 1, "Status: running", theme.accent);
    } else if (runtime.last_result != null) {
        drawLine(win, 1, "Status: complete", theme.text);
    } else {
        drawLine(win, 1, "Status: idle", theme.muted);
    }

    var buffer: [128]u8 = undefined;
    const stdout_line = std.fmt.bufPrint(&buffer, "Stdout: {d} bytes", .{runtime.stream_stdout.items.len}) catch return;
    drawLine(win, 2, stdout_line, theme.text);
    const stderr_line = std.fmt.bufPrint(&buffer, "Stderr: {d} bytes", .{runtime.stream_stderr.items.len}) catch return;
    drawLine(win, 3, stderr_line, theme.text);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}
