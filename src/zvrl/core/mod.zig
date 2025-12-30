const std = @import("std");
const metadata = @import("metadata.zig");

pub const Metadata = metadata.AppMetadata;

/// Produce a formatted metadata summary string owned by `allocator`.
pub fn describe(allocator: std.mem.Allocator) ![]u8 {
    return metadata.summary(allocator);
}

/// Expose the default metadata record for quick access.
pub fn info() Metadata {
    return metadata.defaultMetadata();
}
