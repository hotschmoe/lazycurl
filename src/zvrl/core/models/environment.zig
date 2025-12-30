const std = @import("std");
const ids = @import("../ids.zig");

const Allocator = std.mem.Allocator;

pub const EnvironmentVariable = struct {
    id: u64,
    key: []u8,
    value: []u8,
    is_secret: bool,

    pub fn deinit(self: *EnvironmentVariable, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const Environment = struct {
    allocator: Allocator,
    id: u64,
    name: []u8,
    variables: std.ArrayList(EnvironmentVariable),
    created_at: ids.Timestamp,
    updated_at: ids.Timestamp,

    pub fn init(allocator: Allocator, generator: *ids.IdGenerator, name: []const u8) !Environment {
        const now = ids.nowTimestamp();
        return .{
            .allocator = allocator,
            .id = generator.nextId(),
            .name = try allocator.dupe(u8, name),
            .variables = try std.ArrayList(EnvironmentVariable).initCapacity(allocator, 0),
            .created_at = now,
            .updated_at = now,
        };
    }

    pub fn deinit(self: *Environment) void {
        self.allocator.free(self.name);
        for (self.variables.items) |*variable| {
            variable.deinit(self.allocator);
        }
        self.variables.deinit(self.allocator);
    }

    pub fn addVariable(self: *Environment, generator: *ids.IdGenerator, key: []const u8, value: []const u8, is_secret: bool) !void {
        try self.variables.append(self.allocator, .{
            .id = generator.nextId(),
            .key = try self.allocator.dupe(u8, key),
            .value = try self.allocator.dupe(u8, value),
            .is_secret = is_secret,
        });
        self.updated_at = ids.nowTimestamp();
    }

    pub fn getVariable(self: *const Environment, key: []const u8) ?[]const u8 {
        for (self.variables.items) |variable| {
            if (std.mem.eql(u8, variable.key, key)) {
                return variable.value;
            }
        }
        return null;
    }

    pub fn updateVariable(self: *Environment, key: []const u8, value: []const u8) !bool {
        for (self.variables.items) |*variable| {
            if (std.mem.eql(u8, variable.key, key)) {
                self.allocator.free(variable.value);
                variable.value = try self.allocator.dupe(u8, value);
                self.updated_at = ids.nowTimestamp();
                return true;
            }
        }
        return false;
    }

    pub fn removeVariable(self: *Environment, key: []const u8) bool {
        var index: usize = 0;
        while (index < self.variables.items.len) {
            if (std.mem.eql(u8, self.variables.items[index].key, key)) {
                var removed = self.variables.swapRemove(index);
                removed.deinit(self.allocator);
                self.updated_at = ids.nowTimestamp();
                return true;
            }
            index += 1;
        }
        return false;
    }
};

test "environment variable lifecycle" {
    var generator = ids.IdGenerator{};
    var env = try Environment.init(std.testing.allocator, &generator, "Development");
    defer env.deinit();

    try env.addVariable(&generator, "api_key", "dev", true);
    try std.testing.expectEqualStrings("dev", env.getVariable("api_key").?);

    try std.testing.expect(try env.updateVariable("api_key", "prod"));
    try std.testing.expectEqualStrings("prod", env.getVariable("api_key").?);

    try std.testing.expect(env.removeVariable("api_key"));
    try std.testing.expect(env.getVariable("api_key") == null);
}
