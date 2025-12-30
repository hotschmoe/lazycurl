const std = @import("std");
const app = @import("zvrl_app");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) std.log.warn("memory leaked during shutdown", .{});
    }

    try app.run(gpa.allocator());
}
