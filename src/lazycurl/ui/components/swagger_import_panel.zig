const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");
const floating_pane = @import("lib/floating_pane.zig");

pub fn render(
    allocator: std.mem.Allocator,
    area: zithril.Rect,
    buf: *zithril.Buffer,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (area.width < 30 or area.height < 10) return;

    const inner = floating_pane.begin(area, buf, .{
        .title = "Import Swagger",
        .right_label = "Esc",
        .border_style = theme.border,
        .title_style = theme.title,
        .right_style = theme.muted,
    }) orelse return;
    if (inner.width < 18 or inner.height < 6) return;

    drawSourceLine(inner, buf, app, theme);

    const footer_rows: u16 = 4;
    if (inner.height <= 1 + footer_rows) return;
    const input_h: u16 = inner.height - 1 - footer_rows;
    const input_x: u16 = 0;
    const input_w: u16 = if (inner.width > 1) inner.width - 1 else inner.width;
    const input_container = zithril.Rect.init(
        inner.x + input_x,
        inner.y + 1,
        input_w,
        input_h,
    );
    renderInputBox(input_container, buf, app, theme);

    const error_row: u16 = inner.height - 4;
    const folder_row: u16 = inner.height - 3;
    const new_folder_row: u16 = inner.height - 2;
    const action_row: u16 = inner.height - 1;

    drawErrorLine(inner, buf, error_row, app, theme);
    drawFolderLine(allocator, inner, buf, folder_row, app, theme);
    drawNewFolderLine(inner, buf, new_folder_row, app, theme);
    drawActionsLine(inner, buf, action_row, app, theme);
}

fn drawSourceLine(area: zithril.Rect, buf: *zithril.Buffer, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (area.width == 0) return;
    const focus = app.ui.import_focus == .source;
    const paste_selected = app.ui.import_source == .paste;
    const file_selected = app.ui.import_source == .file;
    const url_selected = app.ui.import_source == .url;

    const label_style = theme.muted;
    const option_style = theme.text;
    const selected_style = if (focus) theme.accent.reverse() else theme.accent;

    const paste_label = if (paste_selected) "[Paste JSON]" else " Paste JSON ";
    const file_label = if (file_selected) "[File Path]" else " File Path ";
    const url_label = if (url_selected) "[URL]" else " URL ";

    var x: u16 = area.x;
    const y = area.y;
    buf.setString(x, y, "Source: ", label_style);
    x += 8;
    buf.setString(x, y, paste_label, if (paste_selected) selected_style else option_style);
    x += @intCast(paste_label.len);
    buf.setString(x, y, " ", label_style);
    x += 1;
    buf.setString(x, y, file_label, if (file_selected) selected_style else option_style);
    x += @intCast(file_label.len);
    buf.setString(x, y, " ", label_style);
    x += 1;
    buf.setString(x, y, url_label, if (url_selected) selected_style else option_style);
}

fn renderInputBox(area: zithril.Rect, buf: *zithril.Buffer, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (area.width < 6 or area.height < 3) return;
    const focused = app.ui.import_focus == .input;
    const title = switch (app.ui.import_source) {
        .paste => "Paste JSON",
        .file => "File Path",
        .url => "Download URL",
    };
    const border_style = if (focused) theme.accent else theme.border;
    const title_style = if (focused) theme.accent else theme.title;
    const inner = boxed.begin(area, buf, title, "", border_style, title_style, theme.muted);
    if (inner.height == 0 or inner.width == 0) return;
    buf.fill(inner, zithril.Cell.styled(' ', zithril.Style.empty));
    switch (app.ui.import_source) {
        .paste => renderMultilineInput(inner, buf, app, theme, focused),
        .file => renderSingleLineInput(inner, buf, app.ui.import_path_input.slice(), app.ui.import_path_input.cursor, "Path to swagger.json", theme, focused, app.ui.cursor_visible),
        .url => renderSingleLineInput(inner, buf, app.ui.import_url_input.slice(), app.ui.import_url_input.cursor, "https://example.com/swagger.json", theme, focused, app.ui.cursor_visible),
    }
}

fn renderSingleLineInput(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    value: []const u8,
    cursor: usize,
    placeholder: []const u8,
    theme: theme_mod.Theme,
    focused: bool,
    cursor_visible: bool,
) void {
    if (!focused and value.len == 0) {
        drawLineClipped(area, buf, 0, placeholder, theme.muted);
        return;
    }
    const cursor_style = cursorStyle(theme, focused);
    drawInputLineWithCursor(area, buf, 0, value, cursor, theme.text, cursor_style, focused and cursor_visible);
}

fn renderMultilineInput(area: zithril.Rect, buf: *zithril.Buffer, app: *app_mod.App, theme: theme_mod.Theme, focused: bool) void {
    const input = &app.ui.import_spec_input;
    const buffer = input.slice();
    app.ui.import_spec_wrap_width = area.width;
    if (!focused and buffer.len == 0) {
        drawLineClipped(area, buf, 0, "Paste OpenAPI/Swagger JSON here", theme.muted);
        return;
    }
    const metrics = measureWrapped(buffer, input.cursor, area.width);
    const total_rows = metrics.total_rows;
    const status_row: ?u16 = if (area.height > 1) area.height - 1 else null;
    const view_rows: usize = if (status_row != null)
        @intCast(area.height - 1)
    else
        @intCast(area.height);
    ensureScroll(&app.ui.import_spec_scroll, metrics.cursor_row, total_rows, @intCast(view_rows));
    const scroll = app.ui.import_spec_scroll;

    renderWrappedView(
        area,
        buf,
        buffer,
        area.width,
        scroll,
        view_rows,
        metrics.cursor_row,
        metrics.cursor_col,
        theme,
        focused,
        app.ui.cursor_visible,
    );
    if (status_row) |row_index| {
        var info_buf: [64]u8 = undefined;
        const line_no = metrics.cursor_row + 1;
        const info = std.fmt.bufPrint(
            &info_buf,
            "Row {d}/{d}  PgUp/PgDn scroll",
            .{ line_no, total_rows },
        ) catch "";
        drawLineClipped(area, buf, row_index, info, theme.muted);
    }
}

fn drawFolderLine(allocator: std.mem.Allocator, area: zithril.Rect, buf: *zithril.Buffer, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= area.height) return;
    const focus = app.ui.import_focus == .folder;
    const label = folderLabel(app);
    const value_style = if (focus) theme.text.reverse() else theme.text;
    const line = std.fmt.allocPrint(allocator, "Folder: {s}  (use arrows)", .{label}) catch return;
    drawLineClipped(area, buf, row, line, value_style);
}

fn drawNewFolderLine(area: zithril.Rect, buf: *zithril.Buffer, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= area.height) return;
    const selected = isNewFolderSelected(app);
    const value = app.ui.import_new_folder_input.slice();
    if (!selected and value.len == 0) {
        drawLineClipped(area, buf, row, "New folder: select 'New Folder\u{2026}' to name", theme.muted);
        return;
    }
    const placeholder = "New folder name";
    const focused = app.ui.import_focus == .folder and selected;
    if (value.len == 0 and !focused) {
        drawLineClipped(area, buf, row, placeholder, theme.muted);
        return;
    }
    const cursor_style = cursorStyle(theme, focused);
    const line_prefix = "New folder: ";
    const prefix_len: u16 = @intCast(line_prefix.len);
    if (prefix_len >= area.width) return;
    buf.setString(area.x, area.y + row, line_prefix, theme.muted);
    const input_area = zithril.Rect.init(
        area.x + prefix_len,
        area.y + row,
        area.width - prefix_len,
        1,
    );
    drawInputLineWithCursor(
        input_area,
        buf,
        0,
        value,
        app.ui.import_new_folder_input.cursor,
        theme.text,
        cursor_style,
        focused and app.ui.cursor_visible,
    );
}

fn drawActionsLine(area: zithril.Rect, buf: *zithril.Buffer, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= area.height) return;
    const focus = app.ui.import_focus == .actions;
    const import_selected = app.ui.import_action_index == 0;
    const cancel_selected = app.ui.import_action_index == 1;
    const selected_style = if (focus) theme.accent.reverse() else theme.accent;

    const import_label = if (import_selected) "[Import]" else " Import ";
    const cancel_label = if (cancel_selected) "[Cancel]" else " Cancel ";

    var x: u16 = area.x;
    const y = area.y + row;
    buf.setString(x, y, import_label, if (import_selected) selected_style else theme.text);
    x += @intCast(import_label.len);
    buf.setString(x, y, " ", theme.muted);
    x += 1;
    buf.setString(x, y, cancel_label, if (cancel_selected) selected_style else theme.text);
}

fn drawErrorLine(area: zithril.Rect, buf: *zithril.Buffer, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= area.height) return;
    if (app.ui.import_error) |message| {
        drawLineClipped(area, buf, row, message, theme.error_style);
    }
}

fn folderLabel(app: *app_mod.App) []const u8 {
    if (isNewFolderSelected(app)) return "New Folder\u{2026}";
    if (app.ui.import_folder_index == 0) return "Root";
    const idx = app.ui.import_folder_index - 1;
    if (idx >= app.templates_folders.items.len) return "Root";
    return app.templates_folders.items[idx];
}

fn isNewFolderSelected(app: *app_mod.App) bool {
    const new_index = app.templates_folders.items.len + 1;
    return app.ui.import_folder_index == new_index;
}

fn cursorStyle(theme: theme_mod.Theme, focused: bool) zithril.Style {
    return if (focused) theme.accent.reverse() else theme.text;
}

fn drawLineClipped(area: zithril.Rect, buf: *zithril.Buffer, row: u16, text: []const u8, style: zithril.Style) void {
    if (row >= area.height or area.width == 0) return;
    const limit: usize = @intCast(area.width);
    const slice = if (text.len > limit) text[0..limit] else text;
    buf.setString(area.x, area.y + row, slice, style);
    const printed: u16 = @intCast(slice.len);
    if (printed < area.width) {
        fillSpaces(area, buf, row, printed, area.width - printed, style);
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

fn drawInputLineWithCursor(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    row: u16,
    value: []const u8,
    cursor_col: usize,
    style: zithril.Style,
    cursor_style: zithril.Style,
    cursor_visible: bool,
) void {
    if (row >= area.height) return;
    const vis = visibleSlice(value, cursor_col, area.width);
    const before = vis.slice[0..@min(@as(usize, vis.cursor_pos), vis.slice.len)];
    const cursor_char = if (vis.cursor_pos < vis.slice.len)
        vis.slice[vis.cursor_pos .. vis.cursor_pos + 1]
    else
        " ";
    const after = if (vis.cursor_pos < vis.slice.len) vis.slice[vis.cursor_pos + 1 ..] else "";

    var x: u16 = area.x;
    const y = area.y + row;
    if (before.len > 0) {
        buf.setString(x, y, before, style);
        x += @intCast(before.len);
    }
    buf.setString(x, y, cursor_char, if (cursor_visible) cursor_style else style);
    x += @intCast(cursor_char.len);
    if (after.len > 0) {
        buf.setString(x, y, after, style);
        x += @intCast(after.len);
    }
    const printed: u16 = @intCast(before.len + cursor_char.len + after.len);
    if (printed < area.width) {
        fillSpaces(area, buf, row, printed, area.width - printed, style);
    }
}

fn fillSpaces(area: zithril.Rect, buf: *zithril.Buffer, row: u16, col: u16, count: u16, style: zithril.Style) void {
    if (count == 0 or col >= area.width) return;
    var remaining: u16 = count;
    var offset: u16 = col;
    const spaces = "                                                                ";
    while (remaining > 0) {
        const chunk: u16 = @min(remaining, @as(u16, spaces.len));
        buf.setString(area.x + offset, area.y + row, spaces[0..chunk], style);
        remaining -= chunk;
        offset += chunk;
    }
}

const WrapMetrics = struct {
    total_rows: usize,
    cursor_row: usize,
    cursor_col: usize,
};

fn measureWrapped(buffer: []const u8, cursor_idx: usize, width: u16) WrapMetrics {
    if (width == 0) return .{ .total_rows = 0, .cursor_row = 0, .cursor_col = 0 };
    const wrap_width: usize = @intCast(width);
    var total_rows: usize = 0;
    var cursor_row: usize = 0;
    var cursor_col: usize = 0;
    var cursor_found = false;
    var line_start: usize = 0;
    var idx: usize = 0;
    while (idx <= buffer.len) : (idx += 1) {
        if (idx == buffer.len or buffer[idx] == '\n') {
            const line_len = idx - line_start;
            const line_rows = if (line_len == 0) 1 else (line_len + wrap_width - 1) / wrap_width;
            if (!cursor_found and cursor_idx >= line_start and cursor_idx <= idx) {
                const col = cursor_idx - line_start;
                var row_offset: usize = 0;
                var col_in_row: usize = 0;
                if (line_len == 0) {
                    row_offset = 0;
                    col_in_row = 0;
                } else if (col == line_len and line_len % wrap_width == 0) {
                    row_offset = line_rows - 1;
                    col_in_row = wrap_width;
                } else {
                    row_offset = col / wrap_width;
                    col_in_row = col % wrap_width;
                }
                cursor_row = total_rows + row_offset;
                cursor_col = col_in_row;
                cursor_found = true;
            }
            total_rows += line_rows;
            line_start = idx + 1;
        }
    }
    return .{ .total_rows = total_rows, .cursor_row = cursor_row, .cursor_col = cursor_col };
}

fn renderWrappedView(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    buffer: []const u8,
    width: u16,
    scroll: usize,
    view_rows: usize,
    cursor_row: usize,
    cursor_col: usize,
    theme: theme_mod.Theme,
    focused: bool,
    cursor_visible: bool,
) void {
    if (view_rows == 0 or width == 0) return;
    const wrap_width: usize = @intCast(width);
    const view_end = scroll + view_rows;
    const cs = cursorStyle(theme, focused);
    var row_index: usize = 0;
    var line_start: usize = 0;
    var idx: usize = 0;
    var next_row: usize = 0;

    while (idx <= buffer.len) : (idx += 1) {
        if (idx == buffer.len or buffer[idx] == '\n') {
            const line_len = idx - line_start;
            const line_rows = if (line_len == 0) 1 else (line_len + wrap_width - 1) / wrap_width;
            if (row_index + line_rows <= scroll) {
                row_index += line_rows;
                line_start = idx + 1;
                continue;
            }
            if (row_index >= view_end) break;

            const start_offset = if (scroll > row_index) scroll - row_index else 0;
            const end_offset = @min(line_rows, view_end - row_index);
            var offset: usize = start_offset;
            while (offset < end_offset) : (offset += 1) {
                const global_row = row_index + offset;
                const out_row = global_row - scroll;
                while (next_row < out_row) : (next_row += 1) {
                    drawLineClipped(area, buf, @intCast(next_row), "", theme.text);
                }
                const start = line_start + offset * wrap_width;
                const end = @min(line_start + line_len, start + wrap_width);
                const slice = if (start > line_start + line_len) "" else buffer[start..end];
                if (global_row == cursor_row) {
                    drawInputLineWithCursor(
                        area,
                        buf,
                        @intCast(out_row),
                        slice,
                        cursor_col,
                        theme.text,
                        cs,
                        focused and cursor_visible,
                    );
                } else {
                    drawLineClipped(area, buf, @intCast(out_row), slice, theme.text);
                }
                next_row = out_row + 1;
            }

            row_index += line_rows;
            line_start = idx + 1;
            if (row_index >= view_end) break;
        }
    }

    while (next_row < view_rows) : (next_row += 1) {
        drawLineClipped(area, buf, @intCast(next_row), "", theme.text);
    }
}

fn ensureScroll(scroll: *usize, cursor_row: usize, total: usize, view: u16) void {
    if (total == 0 or view == 0) {
        scroll.* = 0;
        return;
    }
    const view_rows: usize = @intCast(view);
    if (cursor_row < scroll.*) scroll.* = cursor_row;
    if (cursor_row >= scroll.* + view_rows) scroll.* = cursor_row - view_rows + 1;
    const max_scroll = if (total > view_rows) total - view_rows else 0;
    if (scroll.* > max_scroll) scroll.* = max_scroll;
}
