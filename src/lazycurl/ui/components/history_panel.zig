const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");
const draw = @import("lib/draw.zig");

const TimestampMode = enum {
    full,
    compact,
    time_only,
};

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (area.height == 0) return;
    const focused = app.ui.left_panel != null and app.ui.left_panel.? == .history;
    const header_style = if (focused) theme.accent.reverse() else theme.title;
    const title = std.fmt.allocPrint(allocator, "History ({d})", .{app.history.items.len}) catch return;
    const border_style = if (focused) theme.accent else theme.border;
    const inner = boxed.begin(area, buf, title, "", border_style, header_style, theme.muted);

    if (!app.ui.history_expanded) return;

    const available = inner.height;
    draw.ensureScroll(&app.ui.history_scroll, app.ui.selected_history, app.history.items.len, available);

    var row: u16 = 0;
    var idx: usize = app.ui.history_scroll;
    var rendered: usize = 0;
    const timestamp_mode = pickTimestampMode(inner.width);
    while (idx < app.history.items.len and row < inner.height and rendered < available) : (idx += 1) {
        const command = app.history.items[idx];
        const selected = app.ui.selected_history != null and app.ui.selected_history.? == idx;
        const style = if (selected and focused) theme.accent.reverse() else theme.text;
        const prefix = if (selected) ">" else " ";
        const label = historyLabel(allocator, command) catch return;
        const timestamp = formatTimestamp(allocator, command.updated_at, timestamp_mode) catch return;
        const max_label = maxLabelWidth(inner.width, timestamp.len);
        const label_trimmed = if (label.len > max_label) label[0..max_label] else label;
        const line = std.fmt.allocPrint(allocator, " {s} {s} {s}", .{ prefix, timestamp, label_trimmed }) catch return;
        draw.line(inner, buf, row, line, style);
        row += 1;
        rendered += 1;
    }
}

fn historyLabel(allocator: std.mem.Allocator, command: anytype) ![]const u8 {
    const method = command.method orelse .get;
    const default_name = "New Command";
    const label = if (command.name.len > 0 and !std.mem.eql(u8, command.name, default_name))
        command.name
    else
        command.url;
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ methodLabel(method), label });
}

fn methodLabel(method: anytype) []const u8 {
    return switch (method) {
        .get => "GET",
        .post => "POST",
        .put => "PUT",
        .delete => "DELETE",
        .patch => "PATCH",
        .head => "HEAD",
        .options => "OPTIONS",
        .trace => "TRACE",
        .connect => "CONNECT",
    };
}

fn pickTimestampMode(width: u16) TimestampMode {
    if (width >= 26) return .full;
    if (width >= 22) return .compact;
    return .time_only;
}

fn maxLabelWidth(total_width: u16, timestamp_len: usize) usize {
    const base: usize = 4 + timestamp_len;
    const width_usize: usize = total_width;
    return if (width_usize > base) width_usize - base else 0;
}

fn formatTimestamp(
    allocator: std.mem.Allocator,
    timestamp: i64,
    mode: TimestampMode,
) ![]const u8 {
    if (timestamp <= 0) {
        return switch (mode) {
            .full => "---- -- -- --:--",
            .compact => "-- -- --:--",
            .time_only => "--:--",
        };
    }

    const seconds: u64 = @intCast(timestamp);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year: u16 = year_day.year;
    const month: u8 = @intCast(month_day.month.numeric());
    const day: u8 = @intCast(month_day.day_index + 1);
    const hour: u8 = @intCast(day_seconds.getHoursIntoDay());
    const minute: u8 = @intCast(day_seconds.getMinutesIntoHour());

    return switch (mode) {
        .full => std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{
            year,
            month,
            day,
            hour,
            minute,
        }),
        .compact => std.fmt.allocPrint(allocator, "{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{
            month,
            day,
            hour,
            minute,
        }),
        .time_only => std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}", .{ hour, minute }),
    };
}
