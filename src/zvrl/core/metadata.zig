const std = @import("std");

pub const AppMetadata = struct {
    name: []const u8,
    description: []const u8,
    version: []const u8,
    zig_version: []const u8,
    tui_backend: []const u8,
};

pub fn defaultMetadata() AppMetadata {
    return .{
        .name = "TVRL",
        .description = "Terminal Visual Curl \u2013 Zig rewrite bootstrap",
        .version = "0.1.0-dev",
        .zig_version = "0.15.2",
        .tui_backend = "libvaxis",
    };
}

/// Render a human-friendly summary of the current Zig workspace.
pub fn summary(allocator: std.mem.Allocator) ![]u8 {
    const meta = defaultMetadata();
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    try buffer.writer().print(
        "{s} {s}\n{s}\nRequires Zig {s}+ | Backend: {s}\n",
        .{
            meta.name,
            meta.version,
            meta.description,
            meta.zig_version,
            meta.tui_backend,
        },
    );

    return buffer.toOwnedSlice();
}
