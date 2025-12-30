const std = @import("std");

pub const JsonError = std.json.StringifyError;

pub fn writeJson(writer: anytype, value: anytype) JsonError!void {
    try std.json.stringify(value, .{}, writer);
}

pub fn toJsonString(allocator: std.mem.Allocator, value: anytype) JsonError![]u8 {
    return std.json.stringifyAlloc(allocator, value, .{});
}
