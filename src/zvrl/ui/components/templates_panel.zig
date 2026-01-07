const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const theme_mod = @import("../theme.zig");

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
    drawLine(win, 0, title, header_style);

    if (!app.ui.templates_expanded) return;

    const available = if (win.height > 2) win.height - 2 else 0;
    const columns = columnLayout(win.width);
    drawColumnsHeader(allocator, win, 1, columns, theme);
    _ = renderTemplateList(allocator, win, 2, app, theme, available, columns);
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
    const method_w: usize = 7;
    const url_w: usize = @min(@max(@as(usize, 12), total / 3), total - method_w - 2);
    const name_w: usize = if (total > method_w + url_w + 2) total - method_w - url_w - 2 else 0;
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
    const line = std.fmt.allocPrint(allocator, "{s} {s} {s}", .{
        padOrTrim(allocator, "METHOD", columns.method_w),
        padOrTrim(allocator, "URL", columns.url_w),
        padOrTrim(allocator, "NAME", columns.name_w),
    }) catch return;
    drawLine(win, row, line, theme.muted);
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
    var categories = collectCategories(allocator, app.templates.items) catch return row;
    defer categories.deinit(allocator);

    const selected_row = selectedRowForTemplate(app, categories.items);
    ensureRowScroll(&app.ui.templates_scroll, selected_row, totalRowCount(app, categories.items), max_rows);

    const scroll = app.ui.templates_scroll;
    var list_row: usize = 0;
    var rendered: usize = 0;

    for (categories.items) |category| {
        if (list_row >= scroll and rendered < max_rows and row < win.height) {
            const folder_line = std.fmt.allocPrint(allocator, "[{s}]", .{ category }) catch return row;
            drawLine(win, row, folder_line, theme.title);
            row += 1;
            rendered += 1;
        }
        list_row += 1;

        for (app.templates.items, 0..) |template, idx| {
            if (!std.mem.eql(u8, templateCategory(template), category)) continue;
            if (list_row >= scroll and rendered < max_rows and row < win.height) {
                const selected = app.ui.selected_template != null and app.ui.selected_template.? == idx;
                var style = if (selected and focus) theme.accent else theme.text;
                if (selected and focus) style.reverse = true;
                const method = template.command.method orelse .get;
                const method_label = methodLabel(method);
                const url_label = template.command.url;
                const name_label = template.name;
                const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .template_name and selected;
                if (is_editing) {
                    const prefix = std.fmt.allocPrint(allocator, "{s} {s} {s} ", .{
                        if (selected) ">" else " ",
                        padOrTrim(allocator, method_label, columns.method_w),
                        padOrTrim(allocator, truncate(allocator, url_label, columns.url_w), columns.url_w),
                    }) catch return row;
                    var cursor_style = style;
                    cursor_style.reverse = true;
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
                    const line = std.fmt.allocPrint(allocator, "{s} {s} {s} {s}", .{
                        if (selected) ">" else " ",
                        padOrTrim(allocator, method_label, columns.method_w),
                        padOrTrim(allocator, truncate(allocator, url_label, columns.url_w), columns.url_w),
                        truncate(allocator, name_label, columns.name_w),
                    }) catch return row;
                    drawLine(win, row, line, style);
                }
                row += 1;
                rendered += 1;
            }
            list_row += 1;
        }
    }
    return row;
}

fn templateCategory(template: anytype) []const u8 {
    return template.category orelse "Ungrouped";
}

fn collectCategories(
    allocator: std.mem.Allocator,
    templates: anytype,
) !std.ArrayList([]const u8) {
    var categories = try std.ArrayList([]const u8).initCapacity(allocator, 4);
    for (templates) |template| {
        const category = templateCategory(template);
        var exists = false;
        for (categories.items) |existing| {
            if (std.mem.eql(u8, existing, category)) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            try categories.append(allocator, category);
        }
    }
    return categories;
}

fn totalRowCount(
    app: *app_mod.App,
    categories: []const []const u8,
) usize {
    var rows: usize = 0;
    for (categories) |category| {
        rows += 1;
        for (app.templates.items) |template| {
            if (std.mem.eql(u8, templateCategory(template), category)) {
                rows += 1;
            }
        }
    }
    return rows;
}

fn selectedRowForTemplate(
    app: *app_mod.App,
    categories: []const []const u8,
) ?usize {
    const selected = app.ui.selected_template orelse return null;
    var row: usize = 0;
    for (categories) |category| {
        row += 1;
        for (app.templates.items, 0..) |template, idx| {
            if (!std.mem.eql(u8, templateCategory(template), category)) continue;
            if (idx == selected) return row;
            row += 1;
        }
    }
    return null;
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
