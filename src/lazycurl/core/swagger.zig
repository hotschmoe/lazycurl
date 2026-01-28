const std = @import("std");
const ids = @import("ids.zig");
const command_model = @import("models/command.zig");
const template_model = @import("models/template.zig");

const Allocator = std.mem.Allocator;
const JsonValue = std.json.Value;
const ObjectMap = std.json.ObjectMap;

pub const ImportError = error{
    MissingPaths,
    NoOperations,
};

const MethodSpec = struct {
    key: []const u8,
    method: command_model.HttpMethod,
};

const method_specs = [_]MethodSpec{
    .{ .key = "get", .method = .get },
    .{ .key = "post", .method = .post },
    .{ .key = "put", .method = .put },
    .{ .key = "delete", .method = .delete },
    .{ .key = "patch", .method = .patch },
    .{ .key = "head", .method = .head },
    .{ .key = "options", .method = .options },
    .{ .key = "trace", .method = .trace },
    .{ .key = "connect", .method = .connect },
};

pub fn importTemplatesFromJson(
    allocator: Allocator,
    generator: *ids.IdGenerator,
    json_text: []const u8,
    category: ?[]const u8,
) !std.ArrayList(template_model.CommandTemplate) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const parsed = try std.json.parseFromSlice(JsonValue, arena_alloc, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const root_obj = asObject(&root) orelse return ImportError.MissingPaths;

    const base_url = try resolveBaseUrl(arena_alloc, root_obj);
    const paths_value = root_obj.get("paths") orelse return ImportError.MissingPaths;
    const paths_obj = asObject(&paths_value) orelse return ImportError.MissingPaths;

    var templates = try std.ArrayList(template_model.CommandTemplate).initCapacity(allocator, 0);
    var total_ops: usize = 0;

    var paths_iter = paths_obj.iterator();
    while (paths_iter.next()) |path_entry| {
        const path = path_entry.key_ptr.*;
        const path_item_value = path_entry.value_ptr.*;
        const path_item_obj = asObject(&path_item_value) orelse continue;

        const path_parameters = path_item_obj.get("parameters");

        var method_iter = path_item_obj.iterator();
        while (method_iter.next()) |method_entry| {
            const method_key = method_entry.key_ptr.*;
            const method = parseMethod(method_key) orelse continue;
            const operation_value = method_entry.value_ptr.*;
            const operation_obj = asObject(&operation_value) orelse continue;

            const url = try joinUrl(arena_alloc, base_url, path);
            var command = try command_model.CurlCommand.new(allocator, generator, url);
            errdefer command.deinit();
            command.setMethod(method);

            const name_value = try resolveOperationName(arena_alloc, method, path, operation_obj);
            defer if (name_value.owned) arena_alloc.free(name_value.value);

            command.allocator.free(command.name);
            command.name = try allocator.dupe(u8, name_value.value);

            if (operation_obj.get("description")) |desc_value| {
                if (asString(&desc_value)) |desc| {
                    command.description = try allocator.dupe(u8, desc);
                }
            } else if (operation_obj.get("summary")) |summary_value| {
                if (asString(&summary_value)) |summary| {
                    command.description = try allocator.dupe(u8, summary);
                }
            }

            if (path_parameters) |params_value| {
                try applyParameters(allocator, generator, &command, params_value);
            }
            if (operation_obj.get("parameters")) |params_value| {
                try applyParameters(allocator, generator, &command, params_value);
            }
            try applyRequestBodyHeaders(generator, &command, operation_obj, root_obj);

            var template = try template_model.CommandTemplate.init(allocator, generator, name_value.value, command);
            if (category) |folder| {
                try template.setCategory(folder);
            }
            if (operation_obj.get("description")) |desc_value| {
                if (asString(&desc_value)) |desc| {
                    try template.setDescription(desc);
                }
            } else if (operation_obj.get("summary")) |summary_value| {
                if (asString(&summary_value)) |summary| {
                    try template.setDescription(summary);
                }
            }
            try templates.append(allocator, template);
            total_ops += 1;
        }
    }

    if (total_ops == 0) {
        for (templates.items) |*template| {
            template.deinit();
        }
        templates.deinit(allocator);
        return ImportError.NoOperations;
    }

    return templates;
}

const NameValue = struct {
    value: []const u8,
    owned: bool,
};

fn resolveOperationName(
    allocator: Allocator,
    method: command_model.HttpMethod,
    path: []const u8,
    operation_obj: ObjectMap,
) !NameValue {
    if (operation_obj.get("operationId")) |op_id_value| {
        if (asString(&op_id_value)) |op_id| {
            if (op_id.len > 0) return .{ .value = op_id, .owned = false };
        }
    }
    if (operation_obj.get("summary")) |summary_value| {
        if (asString(&summary_value)) |summary| {
            if (summary.len > 0) return .{ .value = summary, .owned = false };
        }
    }
    const fallback = try std.fmt.allocPrint(allocator, "{s} {s}", .{ method.asString(), path });
    return .{ .value = fallback, .owned = true };
}

fn resolveBaseUrl(allocator: Allocator, root_obj: ObjectMap) ![]const u8 {
    if (root_obj.get("openapi")) |_| {
        if (root_obj.get("servers")) |servers_value| {
            if (servers_value == .array) {
                if (servers_value.array.items.len > 0) {
                    const server_value = servers_value.array.items[0];
                    if (server_value == .object) {
                        if (server_value.object.get("url")) |url_value| {
                            if (asString(&url_value)) |url| return url;
                        }
                    }
                }
            }
        }
        return "https://localhost";
    }

    if (root_obj.get("swagger")) |_| {
        const host_value = root_obj.get("host");
        const base_path_value = root_obj.get("basePath");
        var scheme: []const u8 = "https";
        if (root_obj.get("schemes")) |schemes_value| {
            if (schemes_value == .array and schemes_value.array.items.len > 0) {
                const scheme_value = schemes_value.array.items[0];
                if (asString(&scheme_value)) |scheme_str| {
                    scheme = scheme_str;
                }
            }
        }
        if (host_value) |host| {
            if (asString(&host)) |host_str| {
                const base_path = if (base_path_value) |base_val|
                    asString(&base_val) orelse ""
                else
                    "";
                return std.fmt.allocPrint(allocator, "{s}://{s}{s}", .{ scheme, host_str, base_path });
            }
        }
        return "https://localhost";
    }

    return "https://localhost";
}

fn joinUrl(allocator: Allocator, base: []const u8, path: []const u8) ![]const u8 {
    if (base.len == 0) return path;
    var base_slice = base;
    if (base_slice.len > 1 and base_slice[base_slice.len - 1] == '/' and path.len > 0 and path[0] == '/' and
        !std.mem.endsWith(u8, base_slice, "://"))
    {
        base_slice = base_slice[0 .. base_slice.len - 1];
    }
    if (base_slice.len == 0) return path;
    if (path.len == 0) return base_slice;
    if (base_slice[base_slice.len - 1] != '/' and path[0] != '/') {
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_slice, path });
    }
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base_slice, path });
}

fn parseMethod(key: []const u8) ?command_model.HttpMethod {
    for (method_specs) |spec| {
        if (std.ascii.eqlIgnoreCase(key, spec.key)) return spec.method;
    }
    return null;
}

fn applyParameters(
    allocator: Allocator,
    generator: *ids.IdGenerator,
    command: *command_model.CurlCommand,
    params_value: JsonValue,
) !void {
    if (params_value != .array) return;
    for (params_value.array.items) |param_value| {
        if (param_value != .object) continue;
        const param_obj = param_value.object;
        const name_value = param_obj.get("name") orelse continue;
        const loc_value = param_obj.get("in") orelse continue;
        const name = asString(&name_value) orelse continue;
        const location = asString(&loc_value) orelse continue;
        const default_str = try defaultValueString(allocator, param_obj.get("default"));
        defer if (default_str) |value| allocator.free(value);
        const value = if (default_str) |item| item else "";

        if (std.ascii.eqlIgnoreCase(location, "query")) {
            try command.addQueryParam(generator, name, value);
        } else if (std.ascii.eqlIgnoreCase(location, "header")) {
            if (!hasHeader(command, name)) {
                try command.addHeader(generator, name, value);
            }
        }
    }
}

fn applyRequestBodyHeaders(
    generator: *ids.IdGenerator,
    command: *command_model.CurlCommand,
    operation_obj: ObjectMap,
    root_obj: ObjectMap,
) !void {
    if (operation_obj.get("requestBody")) |request_body_value| {
        if (request_body_value == .object) {
            if (request_body_value.object.get("content")) |content_value| {
                if (content_value == .object) {
                    var iter = content_value.object.iterator();
                    if (iter.next()) |entry| {
                        const content_type = entry.key_ptr.*;
                        try ensureHeader(generator, command, "Content-Type", content_type);
                        return;
                    }
                }
            }
        }
    }

    if (operation_obj.get("consumes")) |consumes_value| {
        if (try applyConsumesHeader(generator, command, consumes_value)) return;
    } else if (root_obj.get("consumes")) |consumes_value| {
        _ = try applyConsumesHeader(generator, command, consumes_value);
    }
}

fn applyConsumesHeader(
    generator: *ids.IdGenerator,
    command: *command_model.CurlCommand,
    consumes_value: JsonValue,
) !bool {
    if (consumes_value != .array) return false;
    if (consumes_value.array.items.len == 0) return false;
    const first_value = consumes_value.array.items[0];
    const content_type = asString(&first_value) orelse return false;
    try ensureHeader(generator, command, "Content-Type", content_type);
    return true;
}

fn ensureHeader(
    generator: *ids.IdGenerator,
    command: *command_model.CurlCommand,
    key: []const u8,
    value: []const u8,
) !void {
    if (hasHeader(command, key)) return;
    try command.addHeader(generator, key, value);
}

fn hasHeader(command: *command_model.CurlCommand, key: []const u8) bool {
    for (command.headers.items) |header| {
        if (std.ascii.eqlIgnoreCase(header.key, key)) return true;
    }
    return false;
}

fn defaultValueString(allocator: Allocator, value: ?JsonValue) !?[]u8 {
    if (value == null) return null;
    const payload = value.?;
    return switch (payload) {
        .string => |text| try allocator.dupe(u8, text),
        .integer => |int| try std.fmt.allocPrint(allocator, "{d}", .{int}),
        .float => |num| try std.fmt.allocPrint(allocator, "{any}", .{num}),
        .bool => |flag| if (flag) try allocator.dupe(u8, "true") else try allocator.dupe(u8, "false"),
        .number_string => |text| try allocator.dupe(u8, text),
        else => null,
    };
}

fn asObject(value: *const JsonValue) ?ObjectMap {
    return switch (value.*) {
        .object => |obj| obj,
        else => null,
    };
}

fn asString(value: *const JsonValue) ?[]const u8 {
    return switch (value.*) {
        .string => |text| text,
        .number_string => |text| text,
        else => null,
    };
}

test "import openapi 3 templates" {
    var generator = ids.IdGenerator{};
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "servers": [{"url": "https://api.example.com/v1"}],
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "summary": "List pets",
        \\        "parameters": [
        \\          {"name": "limit", "in": "query", "default": 10}
        \\        ]
        \\      },
        \\      "post": {
        \\        "operationId": "createPet",
        \\        "requestBody": {
        \\          "content": { "application/json": {} }
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var templates = try importTemplatesFromJson(std.testing.allocator, &generator, json, "Imported");
    defer {
        for (templates.items) |*template| template.deinit();
        templates.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(usize, 2), templates.items.len);
    try std.testing.expectEqualStrings("List pets", templates.items[0].name);
    try std.testing.expectEqualStrings("https://api.example.com/v1/pets", templates.items[0].command.url);
    try std.testing.expectEqualStrings("createPet", templates.items[1].name);
}

test "import swagger 2 templates" {
    var generator = ids.IdGenerator{};
    const json =
        \\{
        \\  "swagger": "2.0",
        \\  "host": "example.com",
        \\  "basePath": "/api",
        \\  "schemes": ["https"],
        \\  "paths": {
        \\    "/status": {
        \\      "get": {
        \\        "summary": "Status",
        \\        "consumes": ["application/json"]
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var templates = try importTemplatesFromJson(std.testing.allocator, &generator, json, null);
    defer {
        for (templates.items) |*template| template.deinit();
        templates.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), templates.items.len);
    try std.testing.expectEqualStrings("https://example.com/api/status", templates.items[0].command.url);
    try std.testing.expect(templates.items[0].command.method.? == .get);
}
