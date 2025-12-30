const std = @import("std");

pub const Timestamp = i64;

pub fn nowTimestamp() Timestamp {
    return std.time.timestamp();
}

pub const IdGenerator = struct {
    next: u64 = 1,

    pub fn nextId(self: *IdGenerator) u64 {
        const id = self.next;
        self.next += 1;
        return id;
    }
};
