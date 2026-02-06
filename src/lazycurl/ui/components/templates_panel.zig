const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");
const draw = @import("lib/draw.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (area.height == 0) return;
    const focused = app.ui.left_panel != null and app.ui.left_panel.? == .templates;
    const header_style = if (focused) theme.accent.reverse() else theme.title;
    const title = std.fmt.allocPrint(allocator, "Templates ({d})", .{app.templates.items.len}) catch return;
    const border_style = if (focused) theme.accent else theme.border;
    const inner = boxed.begin(area, buf, title, "", border_style, header_style, theme.muted);

    if (!app.ui.templates_expanded) return;

    const available = if (inner.height > 1) inner.height - 1 else 0;
    const columns = columnLayout(inner.width);
    drawColumnsHeader(allocator, inner, buf, 0, columns, theme);
    _ = renderTemplateList(allocator, inner, buf, 1, app, theme, available, columns);
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
    area: zithril.Rect,
    buf: *zithril.Buffer,
    row: u16,
    columns: Columns,
    theme: theme_mod.Theme,
) void {
    if (row >= area.height) return;
    if (columns.url_w == 0 or columns.name_w == 0) return;
    const method_label = padOrTrim(allocator, "METHOD", columns.method_w);
    const url_label = padOrTrim(allocator, "URL", columns.url_w);
    const name_label = padOrTrim(allocator, "NAME", columns.name_w);
    const sep = " | ";

    var x: u16 = area.x;
    const y = area.y + row;
    buf.setString(x, y, "  ", theme.muted);
    x += 2;
    buf.setString(x, y, method_label, theme.muted);
    x += @intCast(method_label.len);
    buf.setString(x, y, sep, theme.muted);
    x += @intCast(sep.len);
    buf.setString(x, y, url_label, theme.muted);
    x += @intCast(url_label.len);
    buf.setString(x, y, sep, theme.muted);
    x += @intCast(sep.len);
    buf.setString(x, y, name_label, theme.muted);
}

fn renderTemplateList(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    start_row: u16,
    app: *app_mod.App,
    theme: theme_mod.Theme,
    max_rows: usize,
    columns: Columns,
) u16 {
    if (start_row >= area.height) return start_row;
    if (app.templates.items.len == 0) {
        draw.line(area, buf, start_row, "  (none)", theme.muted);
        return start_row + 1;
    }

    var row = start_row;
    const focus = app.ui.left_panel != null and app.ui.left_panel.? == .templates;
    var rows = app.buildTemplateRows(allocator) catch return row;
    defer rows.deinit(allocator);

    draw.ensureScroll(&app.ui.templates_scroll, app.ui.selected_template_row, rows.items.len, max_rows);

    const scroll = app.ui.templates_scroll;
    var list_row: usize = 0;
    var rendered: usize = 0;

    for (rows.items) |item| {
        if (list_row >= scroll and rendered < max_rows and row < area.height) {
            const selected = app.ui.selected_template_row != null and app.ui.selected_template_row.? == list_row;
            if (item.kind == .folder) {
                const style = if (selected and focus) theme.accent.reverse() else theme.title;
                const marker = if (item.collapsed) "[+]" else "[-]";
                const is_editing_folder = app.state == .editing and app.editing_field != null and app.editing_field.? == .template_folder;
                if (selected and is_editing_folder) {
                    const cursor_style = style.notReverse();
                    const prefix = std.fmt.allocPrint(allocator, "{s} ", .{marker}) catch return row;
                    draw.inputWithCursor(
                        area,
                        buf,
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
                    draw.line(area, buf, row, line, style);
                }
            } else if (item.template_index) |idx| {
                const template = app.templates.items[idx];
                const method = template.command.method orelse .get;
                const method_label = method.asString();
                const url_label = template.command.url;
                const name_label = template.name;
                const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .template_name and selected and app.ui.editing_template_index == idx;
                if (is_editing) {
                    const prefix = std.fmt.allocPrint(allocator, "{s}  {s} | {s} | ", .{
                        if (selected) ">" else " ",
                        padOrTrim(allocator, method_label, columns.method_w),
                        padOrTrim(allocator, truncate(allocator, url_label, columns.url_w), columns.url_w),
                    }) catch return row;
                    const cursor_style = theme.accent.notReverse();
                    draw.inputWithCursor(
                        area,
                        buf,
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
                        area,
                        buf,
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

fn truncate(allocator: std.mem.Allocator, value: []const u8, width: usize) []const u8 {
    if (width == 0) return "";
    if (value.len <= width) return value;
    if (width <= 3) return value[0..width];
    return std.fmt.allocPrint(allocator, "{s}...", .{value[0 .. width - 3]}) catch "";
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

fn drawTemplateRow(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    row: u16,
    columns: Columns,
    method_label: []const u8,
    url_label: []const u8,
    name_label: []const u8,
    selected: bool,
    focused: bool,
    theme: theme_mod.Theme,
) void {
    if (row >= area.height) return;
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
        method_style = method_style.reverse();
        url_style = url_style.reverse();
        name_style = name_style.reverse();
        prefix_style = prefix_style.reverse();
        sep_style = sep_style.reverse();
    }

    const sep = " | ";
    var x: u16 = area.x;
    const y = area.y + row;
    buf.setString(x, y, prefix, prefix_style);
    x += @intCast(prefix.len);
    buf.setString(x, y, method_text, method_style);
    x += @intCast(method_text.len);
    buf.setString(x, y, sep, sep_style);
    x += @intCast(sep.len);
    buf.setString(x, y, url_text, url_style);
    x += @intCast(url_text.len);
    buf.setString(x, y, sep, sep_style);
    x += @intCast(sep.len);
    buf.setString(x, y, name_text, name_style);
}
