const std = @import("std");
const metadata = @import("metadata.zig");
const ids = @import("ids.zig");
pub const models = @import("models/mod.zig");

pub const Metadata = metadata.AppMetadata;
pub const Timestamp = ids.Timestamp;
pub const IdGenerator = ids.IdGenerator;
pub const nowTimestamp = ids.nowTimestamp;

/// Produce a formatted metadata summary string owned by `allocator`.
pub fn describe(allocator: std.mem.Allocator) ![]u8 {
    return metadata.summary(allocator);
}

/// Expose the default metadata record for quick access.
pub fn info() Metadata {
    return metadata.defaultMetadata();
}
