const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("lazycurl_app");
const theme_mod = @import("../theme.zig");
const boxed = @import("lib/boxed.zig");
const floating_pane = @import("lib/floating_pane.zig");

pub fn render(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    app: *app_mod.App,
    theme: theme_mod.Theme,
) void {
    if (win.width < 30 or win.height < 10) return;

    const inner = floating_pane.begin(allocator, win, .{
        .title = "Import Swagger",
        .right_label = "Esc",
        .border_style = theme.border,
        .title_style = theme.title,
        .right_style = theme.muted,
    }) orelse return;
    if (inner.width < 18 or inner.height < 6) return;

    drawSourceLine(allocator, inner, app, theme);

    const footer_rows: u16 = 3;
    if (inner.height <= 1 + footer_rows) return;
    const input_h: u16 = inner.height - 1 - footer_rows;
    const input_container = inner.child(.{
        .x_off = 0,
        .y_off = 1,
        .width = inner.width,
        .height = input_h,
        .border = .{ .where = .none },
    });
    renderInputBox(allocator, input_container, app, theme);

    const error_row: u16 = inner.height - 3;
    const folder_row: u16 = inner.height - 2;
    const action_row: u16 = inner.height - 1;

    drawErrorLine(inner, error_row, app, theme);
    drawFolderLine(allocator, inner, folder_row, app, theme);
    drawActionsLine(allocator, inner, action_row, app, theme);
}

fn drawSourceLine(allocator: std.mem.Allocator, win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (win.width == 0) return;
    const focus = app.ui.import_focus == .source;
    const paste_selected = app.ui.import_source == .paste;
    const file_selected = app.ui.import_source == .file;
    const url_selected = app.ui.import_source == .url;

    const label_style = theme.muted;
    const option_style = theme.text;
    var selected_style = theme.accent;
    if (focus) {
        selected_style.reverse = true;
    }

    const paste_label = if (paste_selected) "[Paste JSON]" else " Paste JSON ";
    const file_label = if (file_selected) "[File Path]" else " File Path ";
    const url_label = if (url_selected) "[URL]" else " URL ";

    const segments = [_]vaxis.Segment{
        .{ .text = "Source: ", .style = label_style },
        .{ .text = paste_label, .style = if (paste_selected) selected_style else option_style },
        .{ .text = " ", .style = label_style },
        .{ .text = file_label, .style = if (file_selected) selected_style else option_style },
        .{ .text = " ", .style = label_style },
        .{ .text = url_label, .style = if (url_selected) selected_style else option_style },
    };
    _ = win.print(segments[0..], .{ .row_offset = 0, .wrap = .none });
    _ = allocator;
}

fn renderInputBox(allocator: std.mem.Allocator, win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (win.width < 6 or win.height < 3) return;
    const focused = app.ui.import_focus == .input;
    const title = switch (app.ui.import_source) {
        .paste => "Paste JSON",
        .file => "File Path",
        .url => "Download URL",
    };
    var border_style = theme.border;
    var title_style = theme.title;
    if (focused) {
        border_style = theme.accent;
        title_style = theme.accent;
    }
    const inner = boxed.begin(allocator, win, title, "", border_style, title_style, theme.muted);
    if (inner.height == 0 or inner.width == 0) return;
    switch (app.ui.import_source) {
        .paste => renderMultilineInput(inner, app, theme, focused),
        .file => renderSingleLineInput(inner, app.ui.import_path_input.slice(), app.ui.import_path_input.cursor, "Path to swagger.json", theme, focused, app.ui.cursor_visible),
        .url => renderSingleLineInput(inner, app.ui.import_url_input.slice(), app.ui.import_url_input.cursor, "https://example.com/swagger.json", theme, focused, app.ui.cursor_visible),
    }
}

fn renderSingleLineInput(
    win: vaxis.Window,
    value: []const u8,
    cursor: usize,
    placeholder: []const u8,
    theme: theme_mod.Theme,
    focused: bool,
    cursor_visible: bool,
) void {
    if (!focused and value.len == 0) {
        drawLineClipped(win, 0, placeholder, theme.muted);
        return;
    }
    const cursor_style = cursorStyle(theme, focused);
    drawInputLineWithCursor(win, 0, value, cursor, theme.text, cursor_style, focused and cursor_visible);
}

fn renderMultilineInput(win: vaxis.Window, app: *app_mod.App, theme: theme_mod.Theme, focused: bool) void {
    const input = &app.ui.import_spec_input;
    const buffer = input.slice();
    if (!focused and buffer.len == 0) {
        drawLineClipped(win, 0, "Paste OpenAPI/Swagger JSON here", theme.muted);
        return;
    }
    const cursor = input.cursorPosition();
    const total_lines = countLines(buffer);
    const status_row: ?u16 = if (win.height > 1) win.height - 1 else null;
    const view_rows: usize = if (status_row != null)
        @intCast(win.height - 1)
    else
        @intCast(win.height);
    ensureScroll(&app.ui.import_spec_scroll, cursor.row, total_lines, @intCast(view_rows));
    const scroll = app.ui.import_spec_scroll;

    var row: usize = 0;
    while (row < view_rows) : (row += 1) {
        const line_index = scroll + row;
        const line = lineAt(buffer, line_index);
        if (line_index == cursor.row) {
            const cursor_style = cursorStyle(theme, focused);
            drawInputLineWithCursor(win, @intCast(row), line, cursor.col, theme.text, cursor_style, focused and app.ui.cursor_visible);
        } else {
            drawLineClipped(win, @intCast(row), line, theme.text);
        }
    }
    if (status_row) |row_index| {
        var info_buf: [64]u8 = undefined;
        const line_no = cursor.row + 1;
        const info = std.fmt.bufPrint(
            &info_buf,
            "Ln {d}/{d}  PgUp/PgDn scroll",
            .{ line_no, total_lines },
        ) catch "";
        drawLineClipped(win, row_index, info, theme.muted);
    }
}

fn drawFolderLine(allocator: std.mem.Allocator, win: vaxis.Window, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= win.height) return;
    const focus = app.ui.import_focus == .folder;
    const label = folderLabel(app);
    var value_style = theme.text;
    if (focus) value_style.reverse = true;
    const line = std.fmt.allocPrint(allocator, "Folder: {s}  (use arrows)", .{label}) catch return;
    drawLineClipped(win, row, line, value_style);
}

fn drawActionsLine(allocator: std.mem.Allocator, win: vaxis.Window, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= win.height) return;
    const focus = app.ui.import_focus == .actions;
    const import_selected = app.ui.import_action_index == 0;
    const cancel_selected = app.ui.import_action_index == 1;
    var selected_style = theme.accent;
    if (focus) selected_style.reverse = true;

    const import_label = if (import_selected) "[Import]" else " Import ";
    const cancel_label = if (cancel_selected) "[Cancel]" else " Cancel ";
    const segments = [_]vaxis.Segment{
        .{ .text = import_label, .style = if (import_selected) selected_style else theme.text },
        .{ .text = " ", .style = theme.muted },
        .{ .text = cancel_label, .style = if (cancel_selected) selected_style else theme.text },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .wrap = .none });
    _ = allocator;
}

fn drawErrorLine(win: vaxis.Window, row: u16, app: *app_mod.App, theme: theme_mod.Theme) void {
    if (row >= win.height) return;
    if (app.ui.import_error) |message| {
        drawLineClipped(win, row, message, theme.error_style);
    }
}

fn folderLabel(app: *app_mod.App) []const u8 {
    if (app.ui.import_folder_index == 0) return "Root";
    const idx = app.ui.import_folder_index - 1;
    if (idx >= app.templates_folders.items.len) return "Root";
    return app.templates_folders.items[idx];
}

fn cursorStyle(theme: theme_mod.Theme, focused: bool) vaxis.Style {
    var style = if (focused) theme.accent else theme.text;
    style.reverse = focused;
    return style;
}

fn drawLineClipped(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    if (row >= win.height or win.width == 0) return;
    const limit: usize = @intCast(win.width);
    const slice = if (text.len > limit) text[0..limit] else text;
    const segments = [_]vaxis.Segment{.{ .text = slice, .style = style }};
    _ = win.print(&segments, .{ .row_offset = row, .wrap = .none });
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
    win: vaxis.Window,
    row: u16,
    value: []const u8,
    cursor_col: usize,
    style: vaxis.Style,
    cursor_style: vaxis.Style,
    cursor_visible: bool,
) void {
    if (row >= win.height) return;
    const vis = visibleSlice(value, cursor_col, win.width);
    const before = vis.slice[0..@min(@as(usize, vis.cursor_pos), vis.slice.len)];
    const cursor_char = if (vis.cursor_pos < vis.slice.len)
        vis.slice[vis.cursor_pos .. vis.cursor_pos + 1]
    else
        " ";
    const after = if (vis.cursor_pos < vis.slice.len) vis.slice[vis.cursor_pos + 1 ..] else "";

    const segments = [_]vaxis.Segment{
        .{ .text = before, .style = style },
        .{ .text = cursor_char, .style = if (cursor_visible) cursor_style else style },
        .{ .text = after, .style = style },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .wrap = .none });
}

fn countLines(buffer: []const u8) usize {
    if (buffer.len == 0) return 1;
    var count: usize = 1;
    for (buffer) |ch| {
        if (ch == '\n') count += 1;
    }
    return count;
}

fn lineAt(buffer: []const u8, line_index: usize) []const u8 {
    if (buffer.len == 0) return "";
    var current: usize = 0;
    var start: usize = 0;
    var idx: usize = 0;
    while (idx < buffer.len) : (idx += 1) {
        if (buffer[idx] == '\n') {
            if (current == line_index) return buffer[start..idx];
            current += 1;
            start = idx + 1;
        }
    }
    if (current == line_index) return buffer[start..buffer.len];
    return "";
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
