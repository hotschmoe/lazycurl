const zithril = @import("zithril");

pub fn line(area: zithril.Rect, buf: *zithril.Buffer, row: u16, text: []const u8, style: zithril.Style) void {
    if (row >= area.height) return;
    buf.setString(area.x, area.y + row, text, style);
}

pub fn lineClipped(area: zithril.Rect, buf: *zithril.Buffer, row: u16, text: []const u8, style: zithril.Style) void {
    if (row >= area.height or area.width == 0) return;
    const limit: usize = @intCast(area.width);
    const slice = if (text.len > limit) text[0..limit] else text;
    line(area, buf, row, slice, style);
}

pub fn ensureScroll(scroll: *usize, selection: ?usize, total: usize, view: usize) void {
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

pub fn inputWithCursor(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    row: u16,
    value: []const u8,
    cursor: usize,
    style: zithril.Style,
    cursor_style: zithril.Style,
    cursor_visible: bool,
    prefix: []const u8,
) void {
    if (row >= area.height) return;
    const prefix_len: usize = prefix.len;
    const win_width: usize = area.width;
    const y = area.y + row;
    if (win_width <= prefix_len) {
        const clipped = prefix[0..@min(prefix_len, win_width)];
        buf.setString(area.x, y, clipped, style);
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

    var x: u16 = area.x;
    if (prefix.len > 0) {
        buf.setString(x, y, prefix, style);
        x += @intCast(prefix.len);
    }
    if (before.len > 0) {
        buf.setString(x, y, before, style);
        x += @intCast(before.len);
    }
    buf.setString(x, y, cursor_char, if (cursor_visible) cursor_style else style);
    x += @intCast(cursor_char.len);
    if (after.len > 0) {
        buf.setString(x, y, after, style);
    }
}
