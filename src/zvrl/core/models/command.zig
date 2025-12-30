const std = @import("std");
const ids = @import("../ids.zig");

const Allocator = std.mem.Allocator;

pub const HttpMethod = enum {
    get,
    post,
    put,
    delete,
    patch,
    head,
    options,
    trace,
    connect,

    pub fn default() HttpMethod {
        return .get;
    }

    pub fn asString(self: HttpMethod) []const u8 {
        return switch (self) {
            .get => "GET",
            .post => "POST",
            .put => "PUT",
            .delete => "DELETE",
            .patch => "PATCH",
            .head => "HEAD",
            .options => "OPTIONS",
            .trace => "TRACE",
            .connect => "CONNECT",
        };
    }
};

pub const Header = struct {
    id: u64,
    key: []u8,
    value: []u8,
    enabled: bool,

    pub fn deinit(self: *Header, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const QueryParam = struct {
    id: u64,
    key: []u8,
    value: []u8,
    enabled: bool,

    pub fn deinit(self: *QueryParam, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const FormDataItem = struct {
    id: u64,
    key: []u8,
    value: []u8,
    enabled: bool,

    pub fn deinit(self: *FormDataItem, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const RequestBody = union(enum) {
    none,
    raw: []u8,
    form_data: std.ArrayList(FormDataItem),
    binary: []u8,

    pub fn deinit(self: *RequestBody, allocator: Allocator) void {
        switch (self.*) {
            .none => {},
            .raw => |value| allocator.free(value),
            .binary => |value| allocator.free(value),
            .form_data => |*list| {
                for (list.items) |*item| {
                    item.deinit(allocator);
                }
                list.deinit(allocator);
            },
        }
    }
};

pub const CurlOption = struct {
    id: u64,
    flag: []u8,
    value: ?[]u8,
    enabled: bool,

    pub fn deinit(self: *CurlOption, allocator: Allocator) void {
        allocator.free(self.flag);
        if (self.value) |value| allocator.free(value);
    }
};

pub const CurlCommand = struct {
    allocator: Allocator,
    id: u64,
    name: []u8,
    description: ?[]u8,
    url: []u8,
    method: ?HttpMethod,
    headers: std.ArrayList(Header),
    query_params: std.ArrayList(QueryParam),
    body: ?RequestBody,
    options: std.ArrayList(CurlOption),
    created_at: ids.Timestamp,
    updated_at: ids.Timestamp,

    pub fn init(allocator: Allocator, generator: *ids.IdGenerator) !CurlCommand {
        const now = ids.nowTimestamp();
        return .{
            .allocator = allocator,
            .id = generator.nextId(),
            .name = try allocator.dupe(u8, "New Command"),
            .description = null,
            .url = try allocator.dupe(u8, "https://"),
            .method = HttpMethod.default(),
            .headers = try std.ArrayList(Header).initCapacity(allocator, 0),
            .query_params = try std.ArrayList(QueryParam).initCapacity(allocator, 0),
            .body = null,
            .options = try std.ArrayList(CurlOption).initCapacity(allocator, 0),
            .created_at = now,
            .updated_at = now,
        };
    }

    pub fn new(allocator: Allocator, generator: *ids.IdGenerator, url: []const u8) !CurlCommand {
        var command = try CurlCommand.init(allocator, generator);
        allocator.free(command.url);
        command.url = try allocator.dupe(u8, url);
        return command;
    }

    pub fn deinit(self: *CurlCommand) void {
        self.allocator.free(self.name);
        if (self.description) |value| self.allocator.free(value);
        self.allocator.free(self.url);

        if (self.body) |*body| {
            body.deinit(self.allocator);
        }

        for (self.headers.items) |*header| {
            header.deinit(self.allocator);
        }
        self.headers.deinit(self.allocator);

        for (self.query_params.items) |*param| {
            param.deinit(self.allocator);
        }
        self.query_params.deinit(self.allocator);

        for (self.options.items) |*option| {
            option.deinit(self.allocator);
        }
        self.options.deinit(self.allocator);
    }

    pub fn addHeader(self: *CurlCommand, generator: *ids.IdGenerator, key: []const u8, value: []const u8) !void {
        try self.headers.append(self.allocator, .{
            .id = generator.nextId(),
            .key = try self.allocator.dupe(u8, key),
            .value = try self.allocator.dupe(u8, value),
            .enabled = true,
        });
        self.updated_at = ids.nowTimestamp();
    }

    pub fn addQueryParam(self: *CurlCommand, generator: *ids.IdGenerator, key: []const u8, value: []const u8) !void {
        try self.query_params.append(self.allocator, .{
            .id = generator.nextId(),
            .key = try self.allocator.dupe(u8, key),
            .value = try self.allocator.dupe(u8, value),
            .enabled = true,
        });
        self.updated_at = ids.nowTimestamp();
    }

    pub fn addOption(self: *CurlCommand, generator: *ids.IdGenerator, flag: []const u8, value: ?[]const u8) !void {
        const owned_value = if (value) |item| try self.allocator.dupe(u8, item) else null;
        try self.options.append(self.allocator, .{
            .id = generator.nextId(),
            .flag = try self.allocator.dupe(u8, flag),
            .value = owned_value,
            .enabled = true,
        });
        self.updated_at = ids.nowTimestamp();
    }

    pub fn setMethod(self: *CurlCommand, method: HttpMethod) void {
        self.method = method;
        self.updated_at = ids.nowTimestamp();
    }

    pub fn setBody(self: *CurlCommand, body: RequestBody) void {
        if (self.body) |*existing| {
            existing.deinit(self.allocator);
        }
        self.body = body;
        self.updated_at = ids.nowTimestamp();
    }
};

test "curl command default values" {
    var generator = ids.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();

    try std.testing.expectEqualStrings("New Command", command.name);
    try std.testing.expectEqualStrings("https://", command.url);
    try std.testing.expect(command.method.? == .get);
    try std.testing.expect(command.headers.items.len == 0);
    try std.testing.expect(command.options.items.len == 0);
}

test "curl command add header/option" {
    var generator = ids.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();

    try command.addHeader(&generator, "Accept", "application/json");
    try command.addOption(&generator, "-v", null);

    try std.testing.expectEqual(@as(usize, 1), command.headers.items.len);
    try std.testing.expectEqual(@as(usize, 1), command.options.items.len);
}
