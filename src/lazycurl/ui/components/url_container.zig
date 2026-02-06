const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const text_input = @import("lazycurl_text_input");
const theme_mod = @import("../theme.zig");
const options_panel = @import("options_panel.zig");
const boxed = @import("lib/boxed.zig");
const key_value_control = @import("lib/key_value_control.zig");
const draw = @import("lib/draw.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    const width = area.width;
    const height = area.height;

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
        const url_area = zithril.Rect.init(area.x, area.y, width, url_h);
        renderUrlInput(url_area, buf, app, theme, url_border);
    }

    if (tabs_h > 0) {
        const tabs_area = zithril.Rect.init(area.x, area.y + url_h, width, tabs_h);
        const inner = boxed.begin(tabs_area, buf, "", "", theme.border, theme.title, theme.muted);
        renderTabs(inner, buf, app, theme);
    }

    if (content_h > 0) {
        const content_selected = isContentSelected(app);
        const content_area = zithril.Rect.init(area.x, area.y + url_h + tabs_h, width, content_h);
        const border_style = if (content_selected) theme.accent else theme.border;
        const tab_title = switch (app.ui.active_tab) {
            .url => "Query Params",
            .headers => "Headers",
            .body => "Body",
            .options => "Curl Options",
        };
        const right_label = if (app.ui.active_tab == .body) bodyTypeLabel(app) else "";
        const right_style = if (app.ui.active_tab == .body and isBodyTypeSelected(app)) theme.accent else theme.muted;
        const inner = boxed.begin(content_area, buf, tab_title, right_label, border_style, theme.title, right_style);
        renderTabContent(allocator, inner, buf, app, theme);
    }
}

fn renderUrlInput(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
    border_style: zithril.Style,
) void {
    const is_editing = isEditingUrl(app);
    const title_style = if (is_editing) theme.accent else theme.title;
    const inner = boxed.begin(area, buf, "URL", "", border_style, title_style, theme.muted);

    const is_selected = isUrlSelected(app);
    const url_style = if (is_editing) theme.accent.reverse() else if (is_selected) theme.accent else theme.text;
    if (is_editing) {
        const cursor_style = url_style.notReverse();
        key_value_control.drawInputWithCursorPrefix(
            inner,
            buf,
            0,
            app.ui.edit_input.slice(),
            app.ui.edit_input.cursor,
            url_style,
            cursor_style,
            app.ui.cursor_visible,
            "",
        );
    } else {
        key_value_control.drawInputWithCursorPrefix(
            inner,
            buf,
            0,
            app.current_command.url,
            app.current_command.url.len,
            url_style,
            url_style,
            false,
            "",
        );
    }
}

fn renderTabs(area: zithril.Rect, buf: *zithril.Buffer, app: *app_mod.App, theme: theme_mod.Theme) void {
    const tabs = [_]struct {
        label: []const u8,
        tab: app_mod.Tab,
    }{
        .{ .label = "[URL]", .tab = .url },
        .{ .label = "[Headers]", .tab = .headers },
        .{ .label = "[Body]", .tab = .body },
        .{ .label = "[Options]", .tab = .options },
    };

    var x: u16 = area.x;
    const y = area.y;
    for (tabs) |tab| {
        const style = if (app.ui.active_tab == tab.tab) theme.accent.reverse() else theme.text;
        buf.setString(x, y, tab.label, style);
        x += @intCast(tab.label.len);
        buf.setString(x, y, " ", theme.muted);
        x += 1;
    }
}

fn renderTabContent(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    switch (app.ui.active_tab) {
        .url => renderQueryParams(allocator, area, buf, app, theme),
        .headers => renderHeaders(allocator, area, buf, app, theme),
        .body => renderBody(allocator, area, buf, app, theme),
        .options => options_panel.render(allocator, area, buf, app, theme),
    }
}

fn renderQueryParams(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    var row: u16 = 0;
    for (app.current_command.query_params.items, 0..) |param, idx| {
        if (row >= area.height) break;
        const enabled = if (param.enabled) "[x]" else "[ ]";
        const is_selected = isQueryParamSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and is_selected and
            (app.editing_field.? == .query_param_value or app.editing_field.? == .query_param_key);
        const style = if (is_selected) theme.accent.reverse() else theme.text;
        if (is_editing) {
            const cursor_style = style.notReverse();
            if (app.editing_field.? == .query_param_key) {
                const prefix = std.fmt.allocPrint(allocator, "{s} ", .{enabled}) catch return;
                const suffix = std.fmt.allocPrint(allocator, "={s}", .{param.value}) catch return;
                key_value_control.drawInputWithCursorPrefixSuffix(
                    area,
                    buf,
                    row,
                    app.ui.edit_input.slice(),
                    app.ui.edit_input.cursor,
                    style,
                    cursor_style,
                    app.ui.cursor_visible,
                    prefix,
                    suffix,
                    theme.muted,
                );
            } else {
                const prefix = std.fmt.allocPrint(allocator, "{s} {s}=", .{ enabled, param.key }) catch return;
                key_value_control.drawInputWithCursorPrefix(
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
            }
        } else {
            const line = std.fmt.allocPrint(allocator, "{s} {s}={s}", .{ enabled, param.key, param.value }) catch return;
            draw.line(area, buf, row, line, style);
        }
        row += 1;
    }

    if (row < area.height) {
        const ghost_selected = isQueryParamSelected(app, app.current_command.query_params.items.len);
        const ghost_style = if (ghost_selected) theme.accent.reverse() else theme.muted;
        draw.line(area, buf, row, "[ ] New query param", ghost_style);
    }
}

fn renderHeaders(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    var row: u16 = 0;
    for (app.current_command.headers.items, 0..) |header, idx| {
        if (row >= area.height) break;
        const enabled = if (header.enabled) "[x]" else "[ ]";
        const is_selected = isHeaderSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and is_selected and
            (app.editing_field.? == .header_value or app.editing_field.? == .header_key);
        const style = if (is_selected) theme.accent.reverse() else theme.text;
        if (is_editing) {
            const prefix = if (app.editing_field.? == .header_key)
                std.fmt.allocPrint(allocator, "{s} ", .{enabled}) catch return
            else
                std.fmt.allocPrint(allocator, "{s} {s}: ", .{ enabled, header.key }) catch return;
            const cursor_style = style.notReverse();
            if (app.editing_field.? == .header_key) {
                const suffix = std.fmt.allocPrint(allocator, ": {s}", .{header.value}) catch return;
                key_value_control.drawInputWithCursorPrefixSuffix(
                    area,
                    buf,
                    row,
                    app.ui.edit_input.slice(),
                    app.ui.edit_input.cursor,
                    style,
                    cursor_style,
                    app.ui.cursor_visible,
                    prefix,
                    suffix,
                    theme.muted,
                );
            } else {
                key_value_control.drawInputWithCursorPrefix(
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
            }
        } else {
            const line = std.fmt.allocPrint(allocator, "{s} {s}: {s}", .{ enabled, header.key, header.value }) catch return;
            draw.line(area, buf, row, line, style);
        }
        row += 1;
    }

    if (row < area.height) {
        const ghost_selected = isHeaderSelected(app, app.current_command.headers.items.len);
        const ghost_style = if (ghost_selected) theme.accent.reverse() else theme.muted;
        draw.line(area, buf, row, "[ ] New header", ghost_style);
    }
}

fn renderBody(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    const content_selected = isBodyContentSelected(app);
    const content_style = if (content_selected) theme.accent else theme.text;

    const is_json = isJsonBody(app);

    const start_row: u16 = 0;

    const is_editing = app.state == .editing and app.editing_field != null and app.editing_field.? == .body;
    if (is_editing) {
        renderBodyInput(
            area,
            buf,
            start_row,
            &app.ui.body_input,
            content_style,
            theme,
            app.ui.cursor_visible,
            is_json,
        );
        return;
    }

    switch (app.current_command.body orelse .none) {
        .none => draw.line(area, buf, start_row, "No body", theme.muted),
        .raw => |payload| renderBodyLines(area, buf, start_row, payload, content_style, theme, is_json),
        .form_data => |list| {
            var row: u16 = start_row;
            for (list.items) |item| {
                if (row >= area.height) break;
                const enabled = if (item.enabled) "[x]" else "[ ]";
                const line = std.fmt.allocPrint(allocator, "{s} {s}={s}", .{ enabled, item.key, item.value }) catch return;
                draw.line(area, buf, row, line, content_style);
                row += 1;
            }
        },
        .binary => |payload| {
            const line = std.fmt.allocPrint(allocator, "Binary data: {d} bytes", .{payload.len}) catch return;
            draw.line(area, buf, start_row, line, content_style);
        },
    }
}

fn renderBodyLines(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    start_row: u16,
    payload: []const u8,
    style: zithril.Style,
    theme: theme_mod.Theme,
    is_json: bool,
) void {
    if (payload.len == 0) {
        draw.line(area, buf, start_row, "Empty body", theme.muted);
        return;
    }

    var row = start_row;
    var it = std.mem.splitScalar(u8, payload, '\n');
    while (it.next()) |line| {
        if (row >= area.height) break;
        if (is_json) {
            drawJsonLine(area, buf, row, line, style, theme);
        } else {
            draw.lineClipped(area, buf, row, line, style);
        }
        row += 1;
    }
}

const VisibleSlice = struct {
    slice: []const u8,
    cursor_pos: u16,
};

fn visibleSlice(line: []const u8, cursor_col: usize, width: u16) VisibleSlice {
    if (width == 0) return .{ .slice = "", .cursor_pos = 0 };
    const win_width: usize = width;
    const safe_cursor = @min(cursor_col, line.len);
    var start: usize = 0;
    if (safe_cursor >= win_width) {
        start = safe_cursor - win_width + 1;
    }
    const end = @min(line.len, start + win_width);
    const visible = line[start..end];
    const cursor_pos: u16 = @intCast(safe_cursor - start);
    return .{ .slice = visible, .cursor_pos = cursor_pos };
}

fn drawJsonLine(area: zithril.Rect, buf: *zithril.Buffer, row: u16, text: []const u8, base_style: zithril.Style, theme: theme_mod.Theme) void {
    if (row >= area.height or area.width == 0) return;
    const limit: usize = @intCast(area.width);
    const slice = if (text.len > limit) text[0..limit] else text;
    if (!renderJsonSegments(area, buf, row, slice, base_style, theme)) {
        draw.lineClipped(area, buf, row, slice, base_style);
    }
}

fn renderJsonSegments(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    row: u16,
    text: []const u8,
    base_style: zithril.Style,
    theme: theme_mod.Theme,
) bool {
    const string_style = theme.accent;
    const number_style = theme.success;
    const bool_style = theme.muted;
    const punct_style = theme.muted;

    var x: u16 = area.x;
    const y = area.y + row;
    var i: usize = 0;
    while (i < text.len) {
        const ch = text[i];
        if (ch == '"') {
            const start = i;
            i += 1;
            while (i < text.len) : (i += 1) {
                if (text[i] == '\\') {
                    if (i + 1 < text.len) i += 1;
                    continue;
                }
                if (text[i] == '"') {
                    i += 1;
                    break;
                }
            }
            const seg = text[start..i];
            buf.setString(x, y, seg, string_style);
            x += @intCast(seg.len);
            continue;
        }
        if (isNumberStart(text, i)) {
            const start = i;
            i += 1;
            while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {}
            if (i < text.len and text[i] == '.') {
                i += 1;
                while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {}
            }
            if (i < text.len and (text[i] == 'e' or text[i] == 'E')) {
                i += 1;
                if (i < text.len and (text[i] == '+' or text[i] == '-')) i += 1;
                while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {}
            }
            const seg = text[start..i];
            buf.setString(x, y, seg, number_style);
            x += @intCast(seg.len);
            continue;
        }
        if (std.ascii.isAlphabetic(ch)) {
            const start = i;
            i += 1;
            while (i < text.len and std.ascii.isAlphabetic(text[i])) : (i += 1) {}
            const word = text[start..i];
            const style = if (isJsonKeyword(word)) bool_style else base_style;
            buf.setString(x, y, word, style);
            x += @intCast(word.len);
            continue;
        }
        if (isJsonPunct(ch)) {
            buf.setString(x, y, text[i .. i + 1], punct_style);
            x += 1;
            i += 1;
            continue;
        }
        const start = i;
        i += 1;
        while (i < text.len and !isJsonSpecial(text[i])) : (i += 1) {}
        const seg = text[start..i];
        buf.setString(x, y, seg, base_style);
        x += @intCast(seg.len);
    }

    return i > 0;
}

fn isJsonSpecial(ch: u8) bool {
    return ch == '"' or isJsonPunct(ch) or std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '-' or ch == '.';
}

fn isNumberStart(text: []const u8, idx: usize) bool {
    const ch = text[idx];
    if (std.ascii.isDigit(ch)) return true;
    if (ch == '-' and idx + 1 < text.len) return std.ascii.isDigit(text[idx + 1]);
    return false;
}

fn isJsonPunct(ch: u8) bool {
    return switch (ch) {
        '{', '}', '[', ']', ':', ',' => true,
        else => false,
    };
}

fn isJsonKeyword(word: []const u8) bool {
    return std.mem.eql(u8, word, "true") or std.mem.eql(u8, word, "false") or std.mem.eql(u8, word, "null");
}

fn renderBodyInput(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    start_row: u16,
    input: *const text_input.TextInput,
    style: zithril.Style,
    theme: theme_mod.Theme,
    cursor_visible: bool,
    is_json: bool,
) void {
    const max_lines: usize = if (area.height > start_row) area.height - start_row else 0;
    if (max_lines == 0) return;

    var row = start_row;
    const text = input.slice();
    const cursor = input.cursorPosition();
    var start_line: usize = 0;
    if (cursor.row >= max_lines) {
        start_line = cursor.row - max_lines + 1;
    }
    var line_index: usize = 0;
    var rendered_any = false;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (row >= area.height) break;
        if (line_index < start_line) {
            line_index += 1;
            continue;
        }
        rendered_any = true;
        if (line_index == cursor.row) {
            const view = visibleSlice(line, cursor.col, area.width);
            if (is_json) {
                drawJsonLine(area, buf, row, view.slice, style, theme);
            } else {
                draw.line(area, buf, row, view.slice, style);
            }
            if (cursor_visible) {
                drawCursorAt(area, buf, row, view.cursor_pos, view.slice, style);
            }
        } else {
            if (is_json) {
                drawJsonLine(area, buf, row, line, style, theme);
            } else {
                draw.lineClipped(area, buf, row, line, style);
            }
        }
        row += 1;
        line_index += 1;
    }
    if (!rendered_any and row < area.height) {
        const view = visibleSlice("", 0, area.width);
        if (is_json) {
            drawJsonLine(area, buf, row, view.slice, style, theme);
        } else {
            draw.line(area, buf, row, view.slice, style);
        }
        if (cursor_visible) {
            drawCursorAt(area, buf, row, view.cursor_pos, view.slice, style);
        }
    }
}

fn drawCursorAt(area: zithril.Rect, buf: *zithril.Buffer, row: u16, cursor_pos: u16, text: []const u8, style: zithril.Style) void {
    if (row >= area.height) return;
    const x = area.x + cursor_pos;
    const y = area.y + row;
    const cursor_style = style.reverse();
    const ch = if (cursor_pos < text.len) text[cursor_pos .. cursor_pos + 1] else " ";
    buf.setString(x, y, ch, cursor_style);
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

fn isJsonBody(app: *app_mod.App) bool {
    for (app.current_command.headers.items) |header| {
        if (!header.enabled) continue;
        if (!std.ascii.eqlIgnoreCase(header.key, "Content-Type")) continue;
        if (containsIgnoreCase(header.value, "application/json")) return true;
    }
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            const a = std.ascii.toLower(haystack[i + j]);
            const b = std.ascii.toLower(needle[j]);
            if (a != b) break;
        }
        if (j == needle.len) return true;
    }
    return false;
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
