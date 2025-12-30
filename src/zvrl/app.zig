const std = @import("std");
const core = @import("zvrl_core");
const vaxis = @import("vaxis");

/// Temporary bootstrap entry point for the Zig rewrite.
pub fn run(allocator: std.mem.Allocator) !void {
    const summary = try core.describe(allocator);
    defer allocator.free(summary);

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print(
        "TVRL Zig workspace initialized.\n{s}\n",
        .{summary},
    );

    // Placeholder use to ensure the libvaxis dependency is wired up.
    _ = vaxis;
}
