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
            try applyRequestBody(allocator, generator, &command, operation_obj, root_obj, &root, path_parameters);

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

fn applyRequestBody(
    allocator: Allocator,
    generator: *ids.IdGenerator,
    command: *command_model.CurlCommand,
    operation_obj: ObjectMap,
    root_obj: ObjectMap,
    root_value: *const JsonValue,
    path_parameters: ?JsonValue,
) !void {
    if (operation_obj.get("requestBody")) |request_body_value| {
        if (try applyOpenApiRequestBody(allocator, generator, command, request_body_value, root_value)) return;
    }
    if (operation_obj.get("parameters")) |params_value| {
        _ = try applySwaggerBodyFromParameters(allocator, command, params_value, root_value);
    }
    if (path_parameters) |params_value| {
        _ = try applySwaggerBodyFromParameters(allocator, command, params_value, root_value);
    }

    if (operation_obj.get("consumes")) |consumes_value| {
        _ = try applyConsumesHeader(generator, command, consumes_value);
    } else if (root_obj.get("consumes")) |consumes_value| {
        _ = try applyConsumesHeader(generator, command, consumes_value);
    }
}

fn applyOpenApiRequestBody(
    allocator: Allocator,
    generator: *ids.IdGenerator,
    command: *command_model.CurlCommand,
    request_body_value: JsonValue,
    root_value: *const JsonValue,
) !bool {
    if (request_body_value != .object) return false;
    const request_obj = request_body_value.object;
    const content_value = request_obj.get("content") orelse return true;
    if (content_value != .object) return true;

    var iter = content_value.object.iterator();
    const entry = iter.next() orelse return true;
    const content_type = entry.key_ptr.*;
    try ensureHeader(generator, command, "Content-Type", content_type);

    const media_value = entry.value_ptr.*;
    const body = try extractOpenApiBodyExample(allocator, media_value, root_value);
    if (body) |payload| {
        command.setBody(.{ .raw = payload });
    }
    return true;
}

fn extractOpenApiBodyExample(allocator: Allocator, media_value: JsonValue, root_value: *const JsonValue) !?[]u8 {
    if (media_value != .object) return null;
    const media_obj = media_value.object;

    if (media_obj.get("example")) |example_value| {
        return try stringifyExample(allocator, example_value);
    }
    if (media_obj.get("examples")) |examples_value| {
        if (examples_value == .object) {
            var iter = examples_value.object.iterator();
            if (iter.next()) |entry| {
                const example_value = entry.value_ptr.*;
                if (example_value == .object) {
                    if (example_value.object.get("value")) |value| {
                        return try stringifyExample(allocator, value);
                    }
                    if (example_value.object.get("example")) |value| {
                        return try stringifyExample(allocator, value);
                    }
                }
                return try stringifyExample(allocator, example_value);
            }
        }
    }
    if (media_obj.get("schema")) |schema_value| {
        return try extractSchemaExample(allocator, schema_value, root_value, 0);
    }
    return null;
}

fn applySwaggerBodyFromParameters(
    allocator: Allocator,
    command: *command_model.CurlCommand,
    params_value: JsonValue,
    root_value: *const JsonValue,
) !bool {
    if (params_value != .array) return false;
    for (params_value.array.items) |param_value| {
        if (param_value != .object) continue;
        const param_obj = param_value.object;
        const loc_value = param_obj.get("in") orelse continue;
        const location = asString(&loc_value) orelse continue;
        if (!std.ascii.eqlIgnoreCase(location, "body")) continue;
        if (try extractSwaggerBodyExample(allocator, param_obj, root_value)) |payload| {
            command.setBody(.{ .raw = payload });
        }
        return true;
    }
    return false;
}

fn extractSwaggerBodyExample(allocator: Allocator, param_obj: ObjectMap, root_value: *const JsonValue) !?[]u8 {
    if (param_obj.get("example")) |example_value| {
        return try stringifyExample(allocator, example_value);
    }
    if (param_obj.get("x-example")) |example_value| {
        return try stringifyExample(allocator, example_value);
    }
    if (param_obj.get("schema")) |schema_value| {
        return try extractSchemaExample(allocator, schema_value, root_value, 0);
    }
    if (param_obj.get("default")) |default_value| {
        return try stringifyExample(allocator, default_value);
    }
    return null;
}

fn extractSchemaExample(allocator: Allocator, schema_value: JsonValue, root_value: *const JsonValue, depth: usize) !?[]u8 {
    if (depth > 4) return null;
    if (schema_value != .object) return null;
    if (schema_value.object.get("$ref")) |ref_value| {
        if (asString(&ref_value)) |ref_str| {
            if (resolveRef(root_value, ref_str)) |resolved| {
                return try extractSchemaExample(allocator, resolved, root_value, depth + 1);
            }
        }
    }
    if (schema_value.object.get("example")) |example_value| {
        return try stringifyExample(allocator, example_value);
    }
    if (schema_value.object.get("default")) |default_value| {
        return try stringifyExample(allocator, default_value);
    }
    if (schema_value.object.get("enum")) |enum_value| {
        if (enum_value == .array and enum_value.array.items.len > 0) {
            return try stringifyExample(allocator, enum_value.array.items[0]);
        }
    }
    if (try buildSchemaPlaceholder(allocator, schema_value, root_value, depth + 1)) |payload| {
        return payload;
    }
    return null;
}

fn buildSchemaPlaceholder(
    allocator: Allocator,
    schema_value: JsonValue,
    root_value: *const JsonValue,
    depth: usize,
) error{OutOfMemory}!?[]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    const value = try buildSchemaPlaceholderValue(arena_alloc, schema_value, root_value, depth) orelse return null;
    return try std.json.Stringify.valueAlloc(allocator, value, .{});
}

fn buildSchemaPlaceholderValue(
    allocator: Allocator,
    schema_value: JsonValue,
    root_value: *const JsonValue,
    depth: usize,
) error{OutOfMemory}!?JsonValue {
    if (depth > 4) return null;
    if (schema_value != .object) return null;
    const schema_obj = schema_value.object;

    if (schema_obj.get("$ref")) |ref_value| {
        if (asString(&ref_value)) |ref_str| {
            if (resolveRef(root_value, ref_str)) |resolved| {
                return try buildSchemaPlaceholderValue(allocator, resolved, root_value, depth + 1);
            }
        }
    }

    if (schema_obj.get("enum")) |enum_value| {
        if (enum_value == .array and enum_value.array.items.len > 0) {
            return enum_value.array.items[0];
        }
    }
    if (schema_obj.get("example")) |example_value| {
        return example_value;
    }
    if (schema_obj.get("default")) |default_value| {
        return default_value;
    }

    const type_value = schema_obj.get("type");
    const type_name = if (type_value) |value| asString(&value) else null;

    if (type_name == null) {
        if (schema_obj.get("properties") != null) {
            return try buildObjectPlaceholder(allocator, schema_obj, root_value, depth);
        }
        if (schema_obj.get("items") != null) {
            return try buildArrayPlaceholder(allocator, schema_obj.get("items").?, root_value, depth);
        }
        return null;
    }

    if (std.ascii.eqlIgnoreCase(type_name.?, "object")) {
        return try buildObjectPlaceholder(allocator, schema_obj, root_value, depth);
    }
    if (std.ascii.eqlIgnoreCase(type_name.?, "array")) {
        if (schema_obj.get("items")) |items_value| {
            return try buildArrayPlaceholder(allocator, items_value, root_value, depth);
        }
        return JsonValue{ .array = std.json.Array.init(allocator) };
    }
    if (std.ascii.eqlIgnoreCase(type_name.?, "string")) return JsonValue{ .string = "" };
    if (std.ascii.eqlIgnoreCase(type_name.?, "integer")) return JsonValue{ .integer = 0 };
    if (std.ascii.eqlIgnoreCase(type_name.?, "number")) return JsonValue{ .float = 0 };
    if (std.ascii.eqlIgnoreCase(type_name.?, "boolean")) return JsonValue{ .bool = false };
    return null;
}

fn buildArrayPlaceholder(
    allocator: Allocator,
    items_value: JsonValue,
    root_value: *const JsonValue,
    depth: usize,
) error{OutOfMemory}!?JsonValue {
    var array = std.json.Array.init(allocator);
    if (try buildSchemaPlaceholderValue(allocator, items_value, root_value, depth + 1)) |item_value| {
        try array.append(item_value);
    }
    return JsonValue{ .array = array };
}

fn buildObjectPlaceholder(
    allocator: Allocator,
    schema_obj: ObjectMap,
    root_value: *const JsonValue,
    depth: usize,
) error{OutOfMemory}!?JsonValue {
    const props_value = schema_obj.get("properties") orelse return JsonValue{ .object = ObjectMap.init(allocator) };
    if (props_value != .object) return JsonValue{ .object = ObjectMap.init(allocator) };

    const required_list = schema_obj.get("required");

    var obj = ObjectMap.init(allocator);
    var iter = props_value.object.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const prop_value = entry.value_ptr.*;
        const include = hasPropertyExample(&prop_value) or isPropertyRequired(required_list, key);
        if (!include) continue;
        if (try buildSchemaPlaceholderValue(allocator, prop_value, root_value, depth + 1)) |value| {
            try obj.put(key, value);
        }
    }

    if (obj.count() == 0) {
        var fallback_iter = props_value.object.iterator();
        if (fallback_iter.next()) |entry| {
            if (try buildSchemaPlaceholderValue(allocator, entry.value_ptr.*, root_value, depth + 1)) |value| {
                try obj.put(entry.key_ptr.*, value);
            }
        }
    }

    return JsonValue{ .object = obj };
}

fn hasPropertyExample(prop_value: *const JsonValue) bool {
    if (prop_value.* != .object) return false;
    const obj = prop_value.*.object;
    return obj.get("example") != null or obj.get("default") != null or obj.get("enum") != null;
}

fn isPropertyRequired(required_value: ?JsonValue, key: []const u8) bool {
    if (required_value == null) return false;
    const value = required_value.?;
    if (value != .array) return false;
    for (value.array.items) |item| {
        if (asString(&item)) |name| {
            if (std.mem.eql(u8, name, key)) return true;
        }
    }
    return false;
}

fn resolveRef(root_value: *const JsonValue, ref: []const u8) ?JsonValue {
    if (ref.len < 2 or ref[0] != '#' or ref[1] != '/') return null;
    var current: JsonValue = root_value.*;
    var it = std.mem.splitScalar(u8, ref[2..], '/');
    while (it.next()) |raw_part| {
        if (raw_part.len == 0) continue;
        if (current != .object) return null;
        var temp_buf: [256]u8 = undefined;
        const part = if (std.mem.indexOf(u8, raw_part, "~") == null)
            raw_part
        else
            unescapeRefPart(raw_part, &temp_buf) orelse return null;
        if (current.object.get(part)) |next| {
            current = next;
        } else {
            return null;
        }
    }
    return current;
}

fn unescapeRefPart(part: []const u8, buf: []u8) ?[]const u8 {
    if (part.len > buf.len) return null;
    var out: usize = 0;
    var i: usize = 0;
    while (i < part.len) : (i += 1) {
        if (part[i] == '~' and i + 1 < part.len) {
            const next = part[i + 1];
            if (next == '0') {
                buf[out] = '~';
                out += 1;
                i += 1;
                continue;
            } else if (next == '1') {
                buf[out] = '/';
                out += 1;
                i += 1;
                continue;
            }
        }
        buf[out] = part[i];
        out += 1;
    }
    return buf[0..out];
}

fn stringifyExample(allocator: Allocator, value: JsonValue) !?[]u8 {
    return switch (value) {
        .string => |text| try allocator.dupe(u8, text),
        .number_string => |text| try allocator.dupe(u8, text),
        .integer, .float, .bool, .null, .object, .array => try std.json.Stringify.valueAlloc(allocator, value, .{}),
    };
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
        \\          "content": {
        \\            "application/json": {
        \\              "example": { "name": "Fluffy", "age": 2 }
        \\            }
        \\          }
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
    if (templates.items[1].command.body) |body| {
        switch (body) {
            .raw => |payload| {
                const parsed_body = try std.json.parseFromSlice(JsonValue, std.testing.allocator, payload, .{});
                defer parsed_body.deinit();
                const obj = parsed_body.value.object;
                try std.testing.expectEqualStrings("Fluffy", asString(&obj.get("name").?).?);
                try std.testing.expectEqual(@as(i64, 2), obj.get("age").?.integer);
            },
            else => try std.testing.expect(false),
        }
    } else {
        try std.testing.expect(false);
    }
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
        \\      "post": {
        \\        "summary": "Status",
        \\        "consumes": ["application/json"],
        \\        "parameters": [
        \\          {
        \\            "name": "body",
        \\            "in": "body",
        \\            "schema": { "example": { "ok": true } }
        \\          }
        \\        ]
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
    try std.testing.expect(templates.items[0].command.method.? == .post);
    if (templates.items[0].command.body) |body| {
        switch (body) {
            .raw => |payload| {
                const parsed_body = try std.json.parseFromSlice(JsonValue, std.testing.allocator, payload, .{});
                defer parsed_body.deinit();
                const obj = parsed_body.value.object;
                try std.testing.expect(obj.get("ok").?.bool);
            },
            else => try std.testing.expect(false),
        }
    } else {
        try std.testing.expect(false);
    }
}

test "import swagger 2 body placeholder from schema properties" {
    var generator = ids.IdGenerator{};
    const json =
        \\{
        \\  "swagger": "2.0",
        \\  "host": "example.com",
        \\  "basePath": "/api",
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "consumes": ["application/json"],
        \\        "parameters": [
        \\          {
        \\            "in": "body",
        \\            "name": "body",
        \\            "schema": {
        \\              "type": "object",
        \\              "required": ["name"],
        \\              "properties": {
        \\                "name": { "type": "string", "example": "doggie" },
        \\                "age": { "type": "integer" }
        \\              }
        \\            }
        \\          }
        \\        ]
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
    var found_header = false;
    for (templates.items[0].command.headers.items) |header| {
        if (std.ascii.eqlIgnoreCase(header.key, "Content-Type")) {
            found_header = true;
            try std.testing.expectEqualStrings("application/json", header.value);
        }
    }
    try std.testing.expect(found_header);
    if (templates.items[0].command.body) |body| {
        switch (body) {
            .raw => |payload| {
                const parsed_body = try std.json.parseFromSlice(JsonValue, std.testing.allocator, payload, .{});
                defer parsed_body.deinit();
                const obj = parsed_body.value.object;
                try std.testing.expectEqualStrings("doggie", asString(&obj.get("name").?).?);
            },
            else => try std.testing.expect(false),
        }
    } else {
        try std.testing.expect(false);
    }
}

test "import swagger query params" {
    var generator = ids.IdGenerator{};
    const json =
        \\{
        \\  "swagger": "2.0",
        \\  "host": "example.com",
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "parameters": [
        \\          { "name": "limit", "in": "query", "default": 10 },
        \\          { "name": "tags", "in": "query" }
        \\        ]
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
    const params = templates.items[0].command.query_params.items;
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqualStrings("limit", params[0].key);
    try std.testing.expectEqualStrings("10", params[0].value);
    try std.testing.expectEqualStrings("tags", params[1].key);
    try std.testing.expectEqualStrings("", params[1].value);
}
