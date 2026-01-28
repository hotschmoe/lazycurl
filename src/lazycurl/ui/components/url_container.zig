const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const text_input = @import("lazycurl_text_input");
const theme_mod = @import("../theme.zig");
const options_panel = @import("options_panel.zig");
const boxed = @import("lib/boxed.zig");

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
            .border = .{ .where = .none },
        });
        renderUrlInput(allocator, url_win, app, theme, url_border);
    }

    if (tabs_h > 0) {
        const tabs_win = win.child(.{
            .x_off = 0,
            .y_off = url_h,
            .width = width,
            .height = tabs_h,
            .border = .{ .where = .none },
        });
        const inner = boxed.begin(allocator, tabs_win, "", "", theme.border, theme.title, theme.muted);
        renderTabs(inner, app, theme);
    }

    if (content_h > 0) {
        const content_selected = isContentSelected(app);
        const content_win = win.child(.{
            .x_off = 0,
            .y_off = url_h + tabs_h,
            .width = width,
            .height = content_h,
            .border = .{ .where = .none },
        });
        const border_style = if (content_selected) theme.accent else theme.border;
        const tab_title = switch (app.ui.active_tab) {
            .url => "Query Params",
            .headers => "Headers",
            .body => "Body",
            .options => "Curl Options",
        };
        const right_label = if (app.ui.active_tab == .body) bodyTypeLabel(app) else "";
        const right_style = if (app.ui.active_tab == .body and isBodyTypeSelected(app)) theme.accent else theme.muted;
        const inner = boxed.begin(allocator, content_win, tab_title, right_label, border_style, theme.title, right_style);
        renderTabContent(allocator, inner, app, theme);
    }
}

fn renderUrlInput(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
    border_style: vaxis.Style,
) void {
    var title_style = theme.title;
    const is_editing = isEditingUrl(app);
    if (is_editing) {
        title_style = theme.accent;
    }
    const inner = boxed.begin(allocator, win, "URL", "", border_style, title_style, theme.muted);

    const is_selected = isUrlSelected(app);
    var url_style = if (is_selected) theme.accent else theme.text;
    if (is_editing) {
        url_style = theme.accent;
        url_style.reverse = true;
    }
    if (is_editing) {
        var cursor_style = url_style;
        cursor_style.reverse = !url_style.reverse;
        drawInputWithCursorPrefix(inner, 0, app.ui.edit_input.slice(), app.ui.edit_input.cursor, url_style, cursor_style, app.ui.cursor_visible, "");
    } else {
        drawInputWithCursorPrefix(
            inner,
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
    if (app.current_command.query_params.items.len == 0) {
        drawLine(win, 0, "No query params", theme.muted);
        return;
    }

    var row: u16 = 0;
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
    var row: u16 = 0;
    for (app.current_command.headers.items, 0..) |header, idx| {
        if (row >= win.height) break;
        const enabled = if (header.enabled) "[x]" else "[ ]";
        const is_selected = isHeaderSelected(app, idx);
        const is_editing = app.state == .editing and app.editing_field != null and is_selected and
            (app.editing_field.? == .header_value or app.editing_field.? == .header_key);
        var style = if (is_selected) theme.accent else theme.text;
        if (is_selected) style.reverse = true;
        if (is_editing) {
            const prefix = if (app.editing_field.? == .header_key)
                std.fmt.allocPrint(allocator, "{s} ", .{enabled}) catch return
            else
                std.fmt.allocPrint(allocator, "{s} {s}: ", .{ enabled, header.key }) catch return;
            var cursor_style = style;
            cursor_style.reverse = !style.reverse;
            drawInputWithCursorPrefix(win, row, app.ui.edit_input.slice(), app.ui.edit_input.cursor, style, cursor_style, app.ui.cursor_visible, prefix);
        } else {
            const line = std.fmt.allocPrint(allocator, "{s} {s}: {s}", .{ enabled, header.key, header.value }) catch return;
            drawLine(win, row, line, style);
        }
        row += 1;
    }

    if (row < win.height) {
        const ghost_selected = isHeaderSelected(app, app.current_command.headers.items.len);
        var ghost_style = if (ghost_selected) theme.accent else theme.muted;
        if (ghost_selected) ghost_style.reverse = true;
        drawLine(win, row, "[ ] New header", ghost_style);
    }
}

fn renderBody(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
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
            win,
            start_row,
            &app.ui.body_input,
            content_style,
            theme,
            app.ui.cursor_visible,
            is_json,
            app.ui.body_mode,
        );
        return;
    }
    win.hideCursor();

    switch (app.current_command.body orelse .none) {
        .none => drawLine(win, start_row, "No body", theme.muted),
        .raw => |payload| renderBodyLines(win, start_row, payload, content_style, theme, is_json),
        .form_data => |list| {
            var row: u16 = start_row;
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
            drawLine(win, start_row, line, content_style);
        },
    }
}

fn renderBodyLines(
    win: vaxis.Window,
    start_row: u16,
    payload: []const u8,
    style: vaxis.Style,
    theme: theme_mod.Theme,
    is_json: bool,
) void {
    if (payload.len == 0) {
        drawLine(win, start_row, "Empty body", theme.muted);
        return;
    }

    var row = start_row;
    var it = std.mem.splitScalar(u8, payload, '\n');
    while (it.next()) |line| {
        if (row >= win.height) break;
        if (is_json) {
            drawJsonLine(win, row, line, style, theme);
        } else {
            drawLineClipped(win, row, line, style);
        }
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

fn drawLineClipped(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height or win.width == 0) return;
    const limit: usize = @intCast(win.width);
    const slice = if (text.len > limit) text[0..limit] else text;
    drawLine(win, row, slice, style);
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

fn drawJsonLine(win: vaxis.Window, row: u16, text: []const u8, base_style: vaxis.Style, theme: theme_mod.Theme) void {
    if (row >= win.height or win.width == 0) return;
    const limit: usize = @intCast(win.width);
    const slice = if (text.len > limit) text[0..limit] else text;
    if (!renderJsonSegments(win, row, slice, base_style, theme)) {
        drawLineClipped(win, row, slice, base_style);
    }
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

fn renderJsonSegments(
    win: vaxis.Window,
    row: u16,
    text: []const u8,
    base_style: vaxis.Style,
    theme: theme_mod.Theme,
) bool {
    var segments: [64]vaxis.Segment = undefined;
    var count: usize = 0;
    const string_style = theme.accent;
    const number_style = theme.success;
    const bool_style = theme.muted;
    const punct_style = theme.muted;

    var i: usize = 0;
    while (i < text.len) {
        if (count >= segments.len) return false;
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
            segments[count] = .{ .text = text[start..i], .style = string_style };
            count += 1;
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
            segments[count] = .{ .text = text[start..i], .style = number_style };
            count += 1;
            continue;
        }
        if (std.ascii.isAlphabetic(ch)) {
            const start = i;
            i += 1;
            while (i < text.len and std.ascii.isAlphabetic(text[i])) : (i += 1) {}
            const word = text[start..i];
            const style = if (isJsonKeyword(word)) bool_style else base_style;
            segments[count] = .{ .text = word, .style = style };
            count += 1;
            continue;
        }
        if (isJsonPunct(ch)) {
            segments[count] = .{ .text = text[i .. i + 1], .style = punct_style };
            count += 1;
            i += 1;
            continue;
        }
        const start = i;
        i += 1;
        while (i < text.len and !isJsonSpecial(text[i])) : (i += 1) {}
        segments[count] = .{ .text = text[start..i], .style = base_style };
        count += 1;
    }

    if (count == 0) return false;
    _ = win.print(segments[0..count], .{ .row_offset = row, .wrap = .none });
    return true;
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
    win: vaxis.Window,
    start_row: u16,
    input: *const text_input.TextInput,
    style: vaxis.Style,
    theme: theme_mod.Theme,
    cursor_visible: bool,
    is_json: bool,
    mode: app_mod.BodyEditMode,
) void {
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
    var rendered_any = false;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (row >= win.height) break;
        if (line_index < start_line) {
            line_index += 1;
            continue;
        }
        rendered_any = true;
        if (line_index == cursor.row) {
            const view = visibleSlice(line, cursor.col, win.width);
            if (is_json) {
                drawJsonLine(win, row, view.slice, style, theme);
            } else {
                drawLine(win, row, view.slice, style);
            }
            if (cursor_visible) {
                win.setCursorShape(if (mode == .insert) .beam else .block);
                win.showCursor(view.cursor_pos, row);
            } else {
                win.hideCursor();
            }
        } else {
            if (is_json) {
                drawJsonLine(win, row, line, style, theme);
            } else {
                drawLineClipped(win, row, line, style);
            }
        }
        row += 1;
        line_index += 1;
    }
    if (!rendered_any and row < win.height) {
        const view = visibleSlice("", 0, win.width);
        if (is_json) {
            drawJsonLine(win, row, view.slice, style, theme);
        } else {
            drawLine(win, row, view.slice, style);
        }
        if (cursor_visible) {
            win.setCursorShape(if (mode == .insert) .beam else .block);
            win.showCursor(view.cursor_pos, row);
        } else {
            win.hideCursor();
        }
    }
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
