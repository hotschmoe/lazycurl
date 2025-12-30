//! Root Zig module that re-exports reusable packages for dependents.
const std = @import("std");
pub const core = @import("zvrl_core");

pub fn bufferedPrint() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const summary = try core.describe(arena.allocator());
    var stdout = std.io.getStdOut().writer();
    try stdout.print("{s}", .{summary});
}
