const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const text_input = @import("zvrl_text_input");
const theme_mod = @import("../theme.zig");
const options_panel = @import("options_panel.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    const width = win.width;
    const height = win.height;

    if (height == 0 or width == 0) return;

    var url_h: u16 = @min(@as(u16, 4), height);
    var tabs_h: u16 = if (height > url_h) @min(@as(u16, 3), height - url_h) else 0;
    if (height < url_h) {
        url_h = height;
        tabs_h = 0;
    } else if (height < url_h + tabs_h) {
        tabs_h = height - url_h;
    }
    const content_h: u16 = if (height > url_h + tabs_h) height - url_h - tabs_h else 0;

    if (url_h > 0) {
        const url_border = if (isUrlSelected(app) or isEditingUrl(app)) theme.accent else theme.border;
        const url_win = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = width,
            .height = url_h,
            .border = .{ .where = .all, .style = url_border },
        });
        renderUrlInput(url_win, app, theme);
    }

    if (tabs_h > 0) {
        const tabs_win = win.child(.{
            .x_off = 0,
            .y_off = url_h,
            .width = width,
            .height = tabs_h,
            .border = .{ .where = .all, .style = theme.border },
        });
        renderTabs(tabs_win, app, theme);
    }

    if (content_h > 0) {
        const content_border = if (isContentSelected(app)) theme.accent else theme.border;
        const content_win = win.child(.{
            .x_off = 0,
            .y_off = url_h + tabs_h,
            .width = width,
            .height = content_h,
            .border = .{ .where = .all, .style = content_border },
        });
        renderTabContent(allocator, content_win, app, theme);
    }
}

fn renderUrlInput(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    var title_style = theme.title;
    const is_editing = isEditingUrl(app);
    if (is_editing) {
        title_style = theme.accent;
    }
    drawLine(win, 0, "URL", title_style);

    const is_selected = isUrlSelected(app);
    var url_style = if (is_selected) theme.accent else theme.text;
    if (is_editing) {
        url_style = theme.accent;
        url_style.reverse = true;
    }
    if (is_editing) {
        var cursor_style = url_style;
        cursor_style.reverse = !url_style.reverse;
        drawInputWithCursorPrefix(win, 1, app.ui.edit_input.slice(), app.ui.edit_input.cursor, url_style, cursor_style, app.ui.cursor_visible, "");
    } else {
        drawInputWithCursorPrefix(
            win,
            1,
            app.current_command.url,
            app.current_command.url.len,
            url_style,
            url_style,
            false,
            "",
        );
    }
}

fn renderTabs(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    const tabs = [_]struct {
        label: []const u8,
        tab: app_mod.Tab,
    }{
        .{ .label = "[URL]", .tab = .url },
        .{ .label = "[Headers]", .tab = .headers },
        .{ .label = "[Body]", .tab = .body },
        .{ .label = "[Options]", .tab = .options },
    };

    var segments: [12]vaxis.Segment = undefined;
    var idx: usize = 0;
    for (tabs) |tab| {
        var style = if (app.ui.active_tab == tab.tab) theme.accent else theme.text;
        if (app.ui.active_tab == tab.tab) style.reverse = true;
        segments[idx] = .{ .text = tab.label, .style = style };
        idx += 1;
        segments[idx] = .{ .text = " ", .style = theme.muted };
        idx += 1;
    }
    _ = win.print(segments[0..idx], .{ .row_offset = 0, .wrap = .none });
}

fn renderTabContent(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    switch (app.ui.active_tab) {
        .url => renderQueryParams(allocator, win, app, theme),
        .headers => renderHeaders(allocator, win, app, theme),
        .body => renderBody(allocator, win, app, theme),
        .options => options_panel.render(allocator, win, app, theme),
    }
}

fn renderQueryParams(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    drawLine(win, 0, "Query Params", theme.title);
    if (app.current_command.query_params.items.len == 0) {
        drawLine(win, 1, "No query params", theme.muted);
        return;
    }

    var row: u16 = 1;
    for (app.current_command.query_params.items, 0..) |param, idx| {
        if (row >= win.height) break;
        const enabled = if (param.enabled) "[x]" else "[ ]";
        const is_selected = isQueryParamSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .query_param_value and is_selected;
        var style = if (is_selected) theme.accent else theme.text;
        if (is_selected) style.reverse = true;
        if (is_editing) {
            const prefix = std.fmt.allocPrint(allocator, "{s} {s}=", .{ enabled, param.key }) catch return;
            var cursor_style = style;
            cursor_style.reverse = !style.reverse;
            drawInputWithCursorPrefix(win, row, app.ui.edit_input.slice(), app.ui.edit_input.cursor, style, cursor_style, app.ui.cursor_visible, prefix);
        } else {
            const line = std.fmt.allocPrint(allocator, "{s} {s}={s}", .{ enabled, param.key, param.value }) catch return;
            drawLine(win, row, line, style);
        }
        row += 1;
    }
}

fn renderHeaders(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    drawLine(win, 0, "Headers", theme.title);
    if (app.current_command.headers.items.len == 0) {
        drawLine(win, 1, "No headers", theme.muted);
        return;
    }

    var row: u16 = 1;
    for (app.current_command.headers.items, 0..) |header, idx| {
        if (row >= win.height) break;
        const enabled = if (header.enabled) "[x]" else "[ ]";
        const is_selected = isHeaderSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .header_value and is_selected;
        var style = if (is_selected) theme.accent else theme.text;
        if (is_selected) style.reverse = true;
        if (is_editing) {
            const prefix = std.fmt.allocPrint(allocator, "{s} {s}: ", .{ enabled, header.key }) catch return;
            var cursor_style = style;
            cursor_style.reverse = !style.reverse;
            drawInputWithCursorPrefix(win, row, app.ui.edit_input.slice(), app.ui.edit_input.cursor, style, cursor_style, app.ui.cursor_visible, prefix);
        } else {
            const line = std.fmt.allocPrint(allocator, "{s} {s}: {s}", .{ enabled, header.key, header.value }) catch return;
            drawLine(win, row, line, style);
        }
        row += 1;
    }
}

fn renderBody(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    drawLine(win, 0, "Body", theme.title);

    const selected_type = isBodyTypeSelected(app);
    var type_style = if (selected_type) theme.accent else theme.text;
    if (selected_type) type_style.reverse = true;

    const body_type = bodyTypeLabel(app);
    const type_line = std.fmt.allocPrint(allocator, "Type: {s}", .{body_type}) catch return;
    drawLine(win, 1, type_line, type_style);

    const content_selected = isBodyContentSelected(app);
    var content_style = if (content_selected) theme.accent else theme.text;
    if (content_selected) content_style.reverse = true;

    const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .body;
    if (is_editing) {
        renderBodyInput(win, 3, &app.ui.body_input, content_style, theme.accent, theme.muted, app.ui.cursor_visible);
        return;
    }

    switch (app.current_command.body orelse .none) {
        .none => drawLine(win, 3, "No body", theme.muted),
        .raw => |payload| renderBodyLines(win, 3, payload, content_style, theme.accent, theme.muted),
        .form_data => |list| {
            var row: u16 = 3;
            for (list.items) |item| {
                if (row >= win.height) break;
                const enabled = if (item.enabled) "[x]" else "[ ]";
                const line = std.fmt.allocPrint(allocator, "{s} {s}={s}", .{ enabled, item.key, item.value }) catch return;
                drawLine(win, row, line, content_style);
                row += 1;
            }
        },
        .binary => |payload| {
            const line = std.fmt.allocPrint(allocator, "Binary data: {d} bytes", .{payload.len}) catch return;
            drawLine(win, 3, line, content_style);
        },
    }
}

fn renderBodyLines(
    win: vaxis.Window,
    start_row: u16,
    payload: []const u8,
    style: vaxis.Style,
    highlight_style: vaxis.Style,
    empty_style: vaxis.Style,
) void {
    if (payload.len == 0) {
        drawLine(win, start_row, "Empty body", empty_style);
        return;
    }

    var row = start_row;
    var it = std.mem.splitScalar(u8, payload, '\n');
    while (it.next()) |line| {
        if (row >= win.height) break;
        const line_style = if (isHighlightLine(line)) highlight_style else style;
        drawLine(win, row, line, line_style);
        row += 1;
    }
}

fn drawUrlValue(
    win: vaxis.Window,
    row: u16,
    url: []const u8,
    base_style: vaxis.Style,
    var_style: vaxis.Style,
) void {
    if (row >= win.height) return;
    var segments: [32]vaxis.Segment = undefined;
    var count: usize = 0;
    var remaining = url;

    while (remaining.len > 0 and count + 1 < segments.len) {
        const start = std.mem.indexOf(u8, remaining, "{{");
        if (start == null) {
            segments[count] = .{ .text = remaining, .style = base_style };
            count += 1;
            break;
        }
        const start_idx = start.?;
        if (start_idx > 0) {
            segments[count] = .{ .text = remaining[0..start_idx], .style = base_style };
            count += 1;
        }
        const after_start = remaining[start_idx + 2 ..];
        const end = std.mem.indexOf(u8, after_start, "}}");
        if (end == null or count + 1 >= segments.len) {
            segments[count] = .{ .text = remaining[start_idx..], .style = base_style };
            count += 1;
            break;
        }
        const end_idx = end.?;
        segments[count] = .{ .text = remaining[start_idx .. start_idx + 2 + end_idx + 2], .style = var_style };
        count += 1;
        remaining = after_start[end_idx + 2 ..];
    }

    if (count == 0) return;
    _ = win.print(segments[0..count], .{ .row_offset = row, .wrap = .none });
}

fn drawLine(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height) return;
    const segments = [_]vaxis.Segment{.{ .text = text, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
}

fn drawInputWithCursorPrefix(
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

fn renderBodyInput(
    win: vaxis.Window,
    start_row: u16,
    input: *const text_input.TextInput,
    style: vaxis.Style,
    highlight_style: vaxis.Style,
    empty_style: vaxis.Style,
    cursor_visible: bool,
) void {
    _ = empty_style;
    const max_lines: usize = if (win.height > start_row) win.height - start_row else 0;
    if (max_lines == 0) return;

    var row = start_row;
    const text = input.slice();
    const cursor = input.cursorPosition();
    var start_line: usize = 0;
    if (cursor.row >= max_lines) {
        start_line = cursor.row - max_lines + 1;
    }
    var line_index: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (row >= win.height) break;
        if (line_index < start_line) {
            line_index += 1;
            continue;
        }
        if (line_index == cursor.row) {
            var cursor_style = style;
            cursor_style.reverse = !style.reverse;
            drawInputWithCursorPrefix(win, row, line, cursor.col, style, cursor_style, cursor_visible, "");
        } else {
            const line_style = if (isHighlightLine(line)) highlight_style else style;
            drawLine(win, row, line, line_style);
        }
        row += 1;
        line_index += 1;
    }
    if (text.len == 0 and row < win.height) {
        var cursor_style = style;
        cursor_style.reverse = !style.reverse;
        drawInputWithCursorPrefix(win, row, "", 0, style, cursor_style, cursor_visible, "");
    }
}

fn isHighlightLine(line: []const u8) bool {
    if (line.len == 0) return false;
    return switch (line[0]) {
        '{', '}', '[', ']' => true,
        else => false,
    };
}

fn isUrlSelected(app: *app_mod.App) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .url => |field| field == .url,
        else => false,
    };
}

fn isEditingUrl(app: *app_mod.App) bool {
    return app.state == .editing and app.editing_field != null and app.editing_field.? == .url;
}

fn isQueryParamSelected(app: *app_mod.App, idx: usize) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .url => |field| switch (field) {
            .query_param => |sel| sel == idx,
            else => false,
        },
        else => false,
    };
}

fn isHeaderSelected(app: *app_mod.App, idx: usize) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .headers => |sel| sel == idx,
        else => false,
    };
}

fn isBodyTypeSelected(app: *app_mod.App) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .body => |field| field == .type,
        else => false,
    };
}

fn isBodyContentSelected(app: *app_mod.App) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .body => |field| field == .content,
        else => false,
    };
}

fn isContentSelected(app: *app_mod.App) bool {
    if (app.ui.left_panel != null) return false;
    return switch (app.ui.selected_field) {
        .url => |field| switch (field) {
            .query_param => true,
            else => false,
        },
        .headers => true,
        .body => true,
        .options => true,
    };
}

fn bodyTypeLabel(app: *app_mod.App) []const u8 {
    if (app.current_command.body) |body| {
        return switch (body) {
            .none => "none",
            .raw => "raw",
            .form_data => "form",
            .binary => "binary",
        };
    }
    return "none";
}
