const std = @import("std");

pub const TextInput = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    cursor: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !TextInput {
        return .{
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, 0),
            .cursor = 0,
        };
    }

    pub fn deinit(self: *TextInput) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *TextInput, value: []const u8) !void {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(self.allocator, value);
        self.cursor = self.buffer.items.len;
    }

    pub fn slice(self: *const TextInput) []const u8 {
        return self.buffer.items;
    }

    pub fn insertByte(self: *TextInput, byte: u8) !void {
        try self.buffer.insert(self.allocator, self.cursor, byte);
        self.cursor += 1;
    }

    pub fn insertSlice(self: *TextInput, text: []const u8) !void {
        if (text.len == 0) return;
        try self.buffer.insertSlice(self.allocator, self.cursor, text);
        self.cursor += text.len;
    }

    pub fn insertPair(self: *TextInput, open: u8, close: u8) !void {
        try self.buffer.insert(self.allocator, self.cursor, open);
        self.cursor += 1;
        try self.buffer.insert(self.allocator, self.cursor, close);
    }

    pub fn skipIfNext(self: *TextInput, byte: u8) bool {
        if (self.cursor >= self.buffer.items.len) return false;
        if (self.buffer.items[self.cursor] != byte) return false;
        self.cursor += 1;
        return true;
    }

    pub fn backspace(self: *TextInput) void {
        if (self.cursor == 0) return;
        self.cursor -= 1;
        _ = self.buffer.orderedRemove(self.cursor);
    }

    pub fn delete(self: *TextInput) void {
        if (self.cursor >= self.buffer.items.len) return;
        _ = self.buffer.orderedRemove(self.cursor);
    }

    pub fn moveLeft(self: *TextInput) void {
        if (self.cursor > 0) self.cursor -= 1;
    }

    pub fn moveRight(self: *TextInput) void {
        if (self.cursor < self.buffer.items.len) self.cursor += 1;
    }

    pub fn moveHome(self: *TextInput) void {
        self.cursor = 0;
    }

    pub fn moveEnd(self: *TextInput) void {
        self.cursor = self.buffer.items.len;
    }

    pub fn moveLineHome(self: *TextInput) void {
        self.cursor = lineStart(self.buffer.items, self.cursor);
    }

    pub fn moveLineEnd(self: *TextInput) void {
        self.cursor = lineEnd(self.buffer.items, self.cursor);
    }

    pub fn moveUp(self: *TextInput) void {
        const idx = self.cursor;
        const line_start = lineStart(self.buffer.items, idx);
        if (line_start == 0) return;
        const prev_line_end = line_start - 1;
        const prev_line_start = lineStart(self.buffer.items, prev_line_end);
        const col = idx - line_start;
        const prev_len = prev_line_end - prev_line_start;
        self.cursor = prev_line_start + @min(col, prev_len);
    }

    pub fn moveDown(self: *TextInput) void {
        const idx = self.cursor;
        const line_end = lineEnd(self.buffer.items, idx);
        if (line_end >= self.buffer.items.len) return;
        const next_line_start = line_end + 1;
        const next_line_end = lineEnd(self.buffer.items, next_line_start);
        const col = idx - lineStart(self.buffer.items, idx);
        const next_len = next_line_end - next_line_start;
        self.cursor = next_line_start + @min(col, next_len);
    }

    pub fn cursorPosition(self: *const TextInput) struct { row: usize, col: usize } {
        var row: usize = 0;
        var col: usize = 0;
        var i: usize = 0;
        while (i < self.cursor and i < self.buffer.items.len) : (i += 1) {
            if (self.buffer.items[i] == '\n') {
                row += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return .{ .row = row, .col = col };
    }

    pub fn moveWordForward(self: *TextInput) void {
        var i = self.cursor;
        const buf = self.buffer.items;
        if (i >= buf.len) return;
        while (i < buf.len and isWordChar(buf[i])) : (i += 1) {}
        while (i < buf.len and !isWordChar(buf[i])) : (i += 1) {}
        self.cursor = i;
    }

    pub fn moveWordBackward(self: *TextInput) void {
        if (self.cursor == 0) return;
        var i = self.cursor - 1;
        const buf = self.buffer.items;
        while (i > 0 and !isWordChar(buf[i])) : (i -= 1) {}
        if (!isWordChar(buf[i]) and i == 0) {
            self.cursor = 0;
            return;
        }
        while (i > 0 and isWordChar(buf[i - 1])) : (i -= 1) {}
        self.cursor = i;
    }

    pub fn currentLineStart(self: *const TextInput) usize {
        return lineStart(self.buffer.items, self.cursor);
    }

    pub fn currentLineEnd(self: *const TextInput) usize {
        return lineEnd(self.buffer.items, self.cursor);
    }

    pub fn setCursor(self: *TextInput, idx: usize) void {
        self.cursor = @min(idx, self.buffer.items.len);
    }
};

fn lineStart(buf: []const u8, idx: usize) usize {
    if (buf.len == 0) return 0;
    if (idx == 0) return 0;
    var i = if (idx > 0) idx - 1 else 0;
    while (true) {
        if (buf[i] == '\n') return i + 1;
        if (i == 0) return 0;
        i -= 1;
    }
}

fn lineEnd(buf: []const u8, idx: usize) usize {
    var i = idx;
    while (i < buf.len) : (i += 1) {
        if (buf[i] == '\n') return i;
    }
    return buf.len;
}

fn isWordChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

test "text input insert and delete" {
    var input = try TextInput.init(std.testing.allocator);
    defer input.deinit();

    try input.reset("ab");
    try input.insertByte('c');
    try std.testing.expectEqualStrings("abc", input.slice());
    input.moveLeft();
    input.backspace();
    try std.testing.expectEqualStrings("ac", input.slice());
}

test "text input move up and down" {
    var input = try TextInput.init(std.testing.allocator);
    defer input.deinit();

    try input.reset("one\ntwo\nthree");
    input.moveHome();
    input.moveDown();
    try std.testing.expectEqual(@as(usize, 4), input.cursor);
    input.moveDown();
    try std.testing.expectEqual(@as(usize, 8), input.cursor);
    input.moveUp();
    try std.testing.expectEqual(@as(usize, 4), input.cursor);
}
