const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("boxed.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (win.height == 0) return;
    const focused = app.ui.left_panel != null and app.ui.left_panel.? == .templates;
    var header_style = if (focused) theme.accent else theme.title;
    if (focused) header_style.reverse = true;
    const title = std.fmt.allocPrint(allocator, "Templates ({d})", .{app.templates.items.len}) catch return;
    const border_style = if (focused) theme.accent else theme.border;
    const inner = boxed.begin(allocator, win, title, "", border_style, header_style, theme.muted);

    if (!app.ui.templates_expanded) return;

    const available = if (inner.height > 1) inner.height - 1 else 0;
    const columns = columnLayout(inner.width);
    drawColumnsHeader(allocator, inner, 0, columns, theme);
    _ = renderTemplateList(allocator, inner, 1, app, theme, available, columns);
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

const Columns = struct {
    method_w: usize,
    url_w: usize,
    name_w: usize,
};

fn columnLayout(width: u16) Columns {
    const total: usize = width;
    if (total <= 10) {
        return .{ .method_w = total, .url_w = 0, .name_w = 0 };
    }
    const method_w: usize = 8;
    const min_url: usize = 20;
    const min_name: usize = 12;
    var url_w: usize = @min(@max(min_url, (total * 5) / 10), total - method_w - 2);
    var name_w: usize = if (total > method_w + url_w + 2) total - method_w - url_w - 2 else 0;
    if (name_w < min_name and url_w > min_url) {
        const needed = min_name - name_w;
        const shrink = @min(needed, url_w - min_url);
        url_w -= shrink;
        name_w = if (total > method_w + url_w + 2) total - method_w - url_w - 2 else 0;
    }
    return .{ .method_w = method_w, .url_w = url_w, .name_w = name_w };
}

fn drawColumnsHeader(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    row: u16,
    columns: Columns,
    theme: theme_mod.Theme,
) void {
    if (row >= win.height) return;
    if (columns.url_w == 0 or columns.name_w == 0) return;
    const method_label = padOrTrim(allocator, "METHOD", columns.method_w);
    const url_label = padOrTrim(allocator, "URL", columns.url_w);
    const name_label = padOrTrim(allocator, "NAME", columns.name_w);
    const sep = " | ";
    const segments = [_]vaxis.Segment{
        .{ .text = "  ", .style = theme.muted },
        .{ .text = method_label, .style = theme.muted },
        .{ .text = sep, .style = theme.muted },
        .{ .text = url_label, .style = theme.muted },
        .{ .text = sep, .style = theme.muted },
        .{ .text = name_label, .style = theme.muted },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .wrap = .none });
}

fn renderTemplateList(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    start_row: u16,
    app: *app_mod.App,
    theme: theme_mod.Theme,
    max_rows: usize,
    columns: Columns,
) u16 {
    if (start_row >= win.height) return start_row;
    if (app.templates.items.len == 0) {
        drawLine(win, start_row, "  (none)", theme.muted);
        return start_row + 1;
    }

    var row = start_row;
    const focus = app.ui.left_panel != null and app.ui.left_panel.? == .templates;
    var rows = app.buildTemplateRows(allocator) catch return row;
    defer rows.deinit(allocator);

    ensureRowScroll(&app.ui.templates_scroll, app.ui.selected_template_row, rows.items.len, max_rows);

    const scroll = app.ui.templates_scroll;
    var list_row: usize = 0;
    var rendered: usize = 0;

    for (rows.items) |item| {
        if (list_row >= scroll and rendered < max_rows and row < win.height) {
            const selected = app.ui.selected_template_row != null and app.ui.selected_template_row.? == list_row;
            if (item.kind == .folder) {
                var style = if (selected and focus) theme.accent else theme.title;
                if (selected and focus) style.reverse = true;
                const marker = if (item.collapsed) "[+]" else "[-]";
                const is_editing_folder = app.state == .editing and app.editing_field != null and app.editing_field.? == .template_folder;
                if (selected and is_editing_folder) {
                    var cursor_style = style;
                    cursor_style.reverse = !style.reverse;
                    const prefix = std.fmt.allocPrint(allocator, "{s} ", .{ marker }) catch return row;
                    drawInputWithCursor(
                        win,
                        row,
                        app.ui.edit_input.slice(),
                        app.ui.edit_input.cursor,
                        style,
                        cursor_style,
                        app.ui.cursor_visible,
                        prefix,
                    );
                } else {
                    const line = std.fmt.allocPrint(allocator, "{s} {s}", .{ marker, item.category }) catch return row;
                    drawLine(win, row, line, style);
                }
            } else if (item.template_index) |idx| {
                const template = app.templates.items[idx];
                const method = template.command.method orelse .get;
                const method_label = methodLabel(method);
                const url_label = template.command.url;
                const name_label = template.name;
                const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .template_name and selected and app.ui.editing_template_index == idx;
                if (is_editing) {
                    const prefix = std.fmt.allocPrint(allocator, "{s}  {s} | {s} | ", .{
                        if (selected) ">" else " ",
                        padOrTrim(allocator, method_label, columns.method_w),
                        padOrTrim(allocator, truncate(allocator, url_label, columns.url_w), columns.url_w),
                    }) catch return row;
                    var cursor_style = theme.accent;
                    cursor_style.reverse = !theme.accent.reverse;
                    drawInputWithCursor(
                        win,
                        row,
                        app.ui.edit_input.slice(),
                        app.ui.edit_input.cursor,
                        theme.text,
                        cursor_style,
                        app.ui.cursor_visible,
                        prefix,
                    );
                } else {
                    drawTemplateRow(
                        allocator,
                        win,
                        row,
                        columns,
                        method_label,
                        url_label,
                        name_label,
                        selected,
                        focus,
                        theme,
                    );
                }
            }
            row += 1;
            rendered += 1;
        }
        list_row += 1;
    }
    return row;
}

fn ensureRowScroll(scroll: *usize, selection: ?usize, total: usize, view: usize) void {
    if (total == 0 or view == 0) {
        scroll.* = 0;
        return;
    }
    const idx = selection orelse return;
    if (idx < scroll.*) scroll.* = idx;
    if (idx >= scroll.* + view) scroll.* = idx - view + 1;
    const max_scroll = if (total > view) total - view else 0;
    if (scroll.* > max_scroll) scroll.* = max_scroll;
}

fn truncate(allocator: std.mem.Allocator, value: []const u8, width: usize) []const u8 {
    if (width == 0) return "";
    if (value.len <= width) return value;
    if (width <= 3) return value[0..width];
    return std.fmt.allocPrint(allocator, "{s}...", .{value[0..width - 3]}) catch "";
}

fn padOrTrim(allocator: std.mem.Allocator, value: []const u8, width: usize) []const u8 {
    if (width == 0) return "";
    if (value.len == width) return value;
    if (value.len > width) return value[0..width];
    const buffer = allocator.alloc(u8, width) catch return value;
    @memcpy(buffer[0..value.len], value);
    @memset(buffer[value.len..], ' ');
    return buffer;
}

fn methodLabel(method: anytype) []const u8 {
    return method.asString();
}

fn drawTemplateRow(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    row: u16,
    columns: Columns,
    method_label: []const u8,
    url_label: []const u8,
    name_label: []const u8,
    selected: bool,
    focused: bool,
    theme: theme_mod.Theme,
) void {
    if (row >= win.height) return;
    const indicator = if (selected) ">" else " ";
    const prefix = std.fmt.allocPrint(allocator, "{s}  ", .{indicator}) catch return;
    const method_text = padOrTrim(allocator, method_label, columns.method_w);
    const url_text = padOrTrim(allocator, truncate(allocator, url_label, columns.url_w), columns.url_w);
    const name_text = padOrTrim(allocator, truncate(allocator, name_label, columns.name_w), columns.name_w);

    var method_style = theme.accent;
    var url_style = theme.text;
    var name_style = theme.text;
    var prefix_style = theme.text;
    var sep_style = theme.muted;
    if (selected and focused) {
        method_style.reverse = true;
        url_style.reverse = true;
        name_style.reverse = true;
        prefix_style.reverse = true;
        sep_style.reverse = true;
    }

    const sep = " | ";
    const segments = [_]vaxis.Segment{
        .{ .text = prefix, .style = prefix_style },
        .{ .text = method_text, .style = method_style },
        .{ .text = sep, .style = sep_style },
        .{ .text = url_text, .style = url_style },
        .{ .text = sep, .style = sep_style },
        .{ .text = name_text, .style = name_style },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .wrap = .none });
}

fn drawInputWithCursor(
    win: vaxis.Window,
    row: u16,
    value: []const u8,
    cursor: usize,
    style: vaxis.Style,
    cursor_style: vaxis.Style,
    cursor_visible: bool,
    prefix: []const u8,
) void {
    if (row >= win.height) return;
    const prefix_len: usize = prefix.len;
    const win_width: usize = win.width;
    if (win_width <= prefix_len) {
        const clipped = prefix[0..@min(prefix_len, win_width)];
        const segments = [_]vaxis.Segment{.{ .text = clipped, .style = style }};
        _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
        return;
    }

    const available = win_width - prefix_len;
    const safe_cursor = @min(cursor, value.len);
    var start: usize = 0;
    if (safe_cursor >= available) {
        start = safe_cursor - available + 1;
    }
    const end = @min(value.len, start + available);
    const visible = value[start..end];
    const cursor_pos = safe_cursor - start;
    const before = visible[0..@min(cursor_pos, visible.len)];
    const cursor_char = if (cursor_pos < visible.len) visible[cursor_pos .. cursor_pos + 1] else " ";
    const after = if (cursor_pos < visible.len) visible[cursor_pos + 1 ..] else "";

    var segments: [4]vaxis.Segment = .{
        .{ .text = prefix, .style = style },
        .{ .text = before, .style = style },
        .{ .text = cursor_char, .style = if (cursor_visible) cursor_style else style },
        .{ .text = after, .style = style },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .wrap = .none });
}
