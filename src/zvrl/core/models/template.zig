const std = @import("std");
const ids = @import("../ids.zig");
const command_model = @import("command.zig");

const Allocator = std.mem.Allocator;

pub const CommandTemplate = struct {
    allocator: Allocator,
    id: u64,
    name: []u8,
    description: ?[]u8,
    command: command_model.CurlCommand,
    category: ?[]u8,
    created_at: ids.Timestamp,
    updated_at: ids.Timestamp,

    pub fn init(allocator: Allocator, generator: *ids.IdGenerator, name: []const u8, command: command_model.CurlCommand) !CommandTemplate {
        const now = ids.nowTimestamp();
        return .{
            .allocator = allocator,
            .id = generator.nextId(),
            .name = try allocator.dupe(u8, name),
            .description = null,
            .command = command,
            .category = null,
            .created_at = now,
            .updated_at = now,
        };
    }

    pub fn deinit(self: *CommandTemplate) void {
        self.allocator.free(self.name);
        if (self.description) |value| self.allocator.free(value);
        if (self.category) |value| self.allocator.free(value);
        self.command.deinit();
    }

    pub fn setDescription(self: *CommandTemplate, description: []const u8) !void {
        if (self.description) |value| self.allocator.free(value);
        self.description = try self.allocator.dupe(u8, description);
        self.updated_at = ids.nowTimestamp();
    }

    pub fn setCategory(self: *CommandTemplate, category: []const u8) !void {
        if (self.category) |value| self.allocator.free(value);
        self.category = try self.allocator.dupe(u8, category);
        self.updated_at = ids.nowTimestamp();
    }
};

test "command template initializes" {
    var generator = ids.IdGenerator{};
    const command = try command_model.CurlCommand.init(std.testing.allocator, &generator);
    var template = try CommandTemplate.init(std.testing.allocator, &generator, "Auth", command);
    defer template.deinit();

    try std.testing.expectEqualStrings("Auth", template.name);
}
