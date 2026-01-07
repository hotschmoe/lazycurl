const std = @import("std");
const core = @import("zvrl_core");

const Allocator = std.mem.Allocator;
const CurlCommand = core.models.command.CurlCommand;
const RequestBody = core.models.command.RequestBody;
const Environment = core.models.environment.Environment;
const CommandTemplate = core.models.template.CommandTemplate;

pub const StoragePaths = struct {
    base_dir: []u8,
    templates_dir: []u8,
    environments_dir: []u8,
    history_file: []u8,
    templates_file: []u8,
    environments_file: []u8,

    pub fn deinit(self: *StoragePaths, allocator: Allocator) void {
        allocator.free(self.base_dir);
        allocator.free(self.templates_dir);
        allocator.free(self.environments_dir);
        allocator.free(self.history_file);
        allocator.free(self.templates_file);
        allocator.free(self.environments_file);
    }
};

pub const PersistenceError = error{
    NotImplemented,
};

pub fn resolvePaths(allocator: Allocator) !StoragePaths {
    const base_dir = try std.fs.getAppDataDir(allocator, "tvrl");
    const templates_dir = try std.fs.path.join(allocator, &.{ base_dir, "templates" });
    const environments_dir = try std.fs.path.join(allocator, &.{ base_dir, "environments" });
    const history_file = try std.fs.path.join(allocator, &.{ base_dir, "history.json" });
    const templates_file = try std.fs.path.join(allocator, &.{ base_dir, "templates.json" });
    const environments_file = try std.fs.path.join(allocator, &.{ base_dir, "environments.json" });

    return .{
        .base_dir = base_dir,
        .templates_dir = templates_dir,
        .environments_dir = environments_dir,
        .history_file = history_file,
        .templates_file = templates_file,
        .environments_file = environments_file,
    };
}

pub fn ensureStorageDirs(paths: *const StoragePaths) !void {
    const cwd = std.fs.cwd();
    try cwd.makePath(paths.base_dir);
    try cwd.makePath(paths.templates_dir);
    try cwd.makePath(paths.environments_dir);
}

pub fn loadTemplates(allocator: Allocator, generator: *core.IdGenerator) !std.ArrayList(CommandTemplate) {
    var paths = try resolvePaths(allocator);
    defer paths.deinit(allocator);

    const cwd = std.fs.cwd();
    if (cwd.openFile(paths.templates_file, .{ .mode = .read_only })) |file| {
        defer file.close();
        const data = try file.readToEndAlloc(allocator, 1_048_576);
        defer allocator.free(data);
        return parseTemplatesJson(allocator, generator, data);
    } else |err| switch (err) {
        error.FileNotFound => return seedTemplates(allocator, generator),
        else => return err,
    }
}

pub fn loadEnvironments(allocator: Allocator, generator: *core.IdGenerator) !std.ArrayList(Environment) {
    var paths = try resolvePaths(allocator);
    defer paths.deinit(allocator);

    const cwd = std.fs.cwd();
    if (cwd.openFile(paths.environments_file, .{ .mode = .read_only })) |file| {
        file.close();
        return PersistenceError.NotImplemented;
    } else |err| switch (err) {
        error.FileNotFound => return seedEnvironments(allocator, generator),
        else => return err,
    }
}

pub fn loadHistory(allocator: Allocator) !std.ArrayList(CurlCommand) {
    var paths = try resolvePaths(allocator);
    defer paths.deinit(allocator);

    const cwd = std.fs.cwd();
    if (cwd.openFile(paths.history_file, .{ .mode = .read_only })) |file| {
        file.close();
        return PersistenceError.NotImplemented;
    } else |err| switch (err) {
        error.FileNotFound => return std.ArrayList(CurlCommand).initCapacity(allocator, 0),
        else => return err,
    }
}

pub fn saveTemplates(allocator: Allocator, templates: []const CommandTemplate) !void {
    var paths = try resolvePaths(allocator);
    defer paths.deinit(allocator);
    try ensureStorageDirs(&paths);
    const cwd = std.fs.cwd();
    var file = try cwd.createFile(paths.templates_file, .{ .truncate = true });
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const payload = try buildTemplatesJson(arena_alloc, templates);
    try std.json.stringify(payload, .{ .whitespace = .indent_2 }, file.writer());
}

pub fn saveEnvironments(allocator: Allocator, environments: []const Environment) !void {
    _ = environments;
    var paths = try resolvePaths(allocator);
    defer paths.deinit(allocator);
    try ensureStorageDirs(&paths);
    return PersistenceError.NotImplemented;
}

pub fn saveHistory(allocator: Allocator, history: []const CurlCommand) !void {
    _ = history;
    var paths = try resolvePaths(allocator);
    defer paths.deinit(allocator);
    try ensureStorageDirs(&paths);
    return PersistenceError.NotImplemented;
}

const JsonTemplateFile = struct {
    templates: []JsonTemplate,
};

const JsonTemplate = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    category: ?[]const u8 = null,
    command: JsonCommand,
    created_at: i64,
    updated_at: i64,
};

const JsonCommand = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    url: []const u8,
    method: ?[]const u8 = null,
    headers: []JsonHeader = &.{},
    query_params: []JsonQueryParam = &.{},
    body: ?JsonBody = null,
    options: []JsonOption = &.{},
    created_at: i64,
    updated_at: i64,
};

const JsonHeader = struct {
    key: []const u8,
    value: []const u8,
    enabled: bool,
};

const JsonQueryParam = struct {
    key: []const u8,
    value: []const u8,
    enabled: bool,
};

const JsonOption = struct {
    flag: []const u8,
    value: ?[]const u8,
    enabled: bool,
};

const JsonBody = struct {
    kind: []const u8,
    raw: ?[]const u8 = null,
    binary: ?[]const u8 = null,
    form_data: ?[]JsonFormData = null,
};

const JsonFormData = struct {
    key: []const u8,
    value: []const u8,
    enabled: bool,
};

fn buildTemplatesJson(allocator: Allocator, templates: []const CommandTemplate) !JsonTemplateFile {
    var list = try std.ArrayList(JsonTemplate).initCapacity(allocator, templates.len);
    for (templates) |template| {
        const command = template.command;
        var headers = try std.ArrayList(JsonHeader).initCapacity(allocator, command.headers.items.len);
        for (command.headers.items) |header| {
            try headers.append(allocator, .{
                .key = header.key,
                .value = header.value,
                .enabled = header.enabled,
            });
        }

        var query_params = try std.ArrayList(JsonQueryParam).initCapacity(allocator, command.query_params.items.len);
        for (command.query_params.items) |param| {
            try query_params.append(allocator, .{
                .key = param.key,
                .value = param.value,
                .enabled = param.enabled,
            });
        }

        var options = try std.ArrayList(JsonOption).initCapacity(allocator, command.options.items.len);
        for (command.options.items) |option| {
            try options.append(allocator, .{
                .flag = option.flag,
                .value = option.value,
                .enabled = option.enabled,
            });
        }

        var body_json: ?JsonBody = null;
        if (command.body) |body| {
            switch (body) {
                .none => body_json = .{ .kind = "none" },
                .raw => |value| body_json = .{ .kind = "raw", .raw = value },
                .binary => |value| body_json = .{ .kind = "binary", .binary = value },
                .form_data => |list_data| {
                    var form_items = try std.ArrayList(JsonFormData).initCapacity(allocator, list_data.items.len);
                    for (list_data.items) |item| {
                        try form_items.append(allocator, .{
                            .key = item.key,
                            .value = item.value,
                            .enabled = item.enabled,
                        });
                    }
                    body_json = .{ .kind = "form_data", .form_data = form_items.items };
                },
            }
        }

        const method = if (command.method) |method| method.asString() else null;
        const json_command = JsonCommand{
            .name = command.name,
            .description = command.description,
            .url = command.url,
            .method = method,
            .headers = headers.items,
            .query_params = query_params.items,
            .body = body_json,
            .options = options.items,
            .created_at = @intCast(command.created_at),
            .updated_at = @intCast(command.updated_at),
        };

        try list.append(allocator, .{
            .name = template.name,
            .description = template.description,
            .category = template.category,
            .command = json_command,
            .created_at = @intCast(template.created_at),
            .updated_at = @intCast(template.updated_at),
        });
    }

    return .{ .templates = list.items };
}

fn parseTemplatesJson(
    allocator: Allocator,
    generator: *core.IdGenerator,
    data: []const u8,
) !std.ArrayList(CommandTemplate) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSlice(JsonTemplateFile, arena.allocator(), data, .{});
    defer parsed.deinit();
    const file = parsed.value;

    var templates = try std.ArrayList(CommandTemplate).initCapacity(allocator, file.templates.len);
    for (file.templates) |record| {
        var command = try CurlCommand.init(allocator, generator);
        errdefer command.deinit();

        command.allocator.free(command.name);
        const command_name = if (record.command.name.len > 0) record.command.name else record.name;
        command.name = try allocator.dupe(u8, command_name);
        if (record.command.description) |desc| {
            command.description = try allocator.dupe(u8, desc);
        }
        command.allocator.free(command.url);
        command.url = try allocator.dupe(u8, record.command.url);

        if (record.command.method) |method_str| {
            if (parseMethod(method_str)) |method| {
                command.method = method;
            }
        }

        for (command.headers.items) |*header| header.deinit(allocator);
        command.headers.clearRetainingCapacity();
        for (record.command.headers) |header| {
            try command.headers.append(allocator, .{
                .id = generator.nextId(),
                .key = try allocator.dupe(u8, header.key),
                .value = try allocator.dupe(u8, header.value),
                .enabled = header.enabled,
            });
        }

        for (command.query_params.items) |*param| param.deinit(allocator);
        command.query_params.clearRetainingCapacity();
        for (record.command.query_params) |param| {
            try command.query_params.append(allocator, .{
                .id = generator.nextId(),
                .key = try allocator.dupe(u8, param.key),
                .value = try allocator.dupe(u8, param.value),
                .enabled = param.enabled,
            });
        }

        for (command.options.items) |*option| option.deinit(allocator);
        command.options.clearRetainingCapacity();
        for (record.command.options) |option| {
            const value = if (option.value) |val| try allocator.dupe(u8, val) else null;
            try command.options.append(allocator, .{
                .id = generator.nextId(),
                .flag = try allocator.dupe(u8, option.flag),
                .value = value,
                .enabled = option.enabled,
            });
        }

        if (record.command.body) |body| {
            if (std.mem.eql(u8, body.kind, "none")) {
                command.body = null;
            } else if (std.mem.eql(u8, body.kind, "raw")) {
                const payload = if (body.raw) |raw| try allocator.dupe(u8, raw) else try allocator.dupe(u8, "");
                command.body = .{ .raw = payload };
            } else if (std.mem.eql(u8, body.kind, "binary")) {
                const payload = if (body.binary) |raw| try allocator.dupe(u8, raw) else try allocator.dupe(u8, "");
                command.body = .{ .binary = payload };
            } else if (std.mem.eql(u8, body.kind, "form_data")) {
                var list = try std.ArrayList(core.models.command.FormDataItem).initCapacity(allocator, 0);
                if (body.form_data) |items| {
                    try list.ensureTotalCapacity(allocator, items.len);
                    for (items) |item| {
                        try list.append(allocator, .{
                            .id = generator.nextId(),
                            .key = try allocator.dupe(u8, item.key),
                            .value = try allocator.dupe(u8, item.value),
                            .enabled = item.enabled,
                        });
                    }
                }
                command.body = .{ .form_data = list };
            }
        } else {
            command.body = null;
        }

        command.created_at = @intCast(record.command.created_at);
        command.updated_at = @intCast(record.command.updated_at);

        var template = try CommandTemplate.init(allocator, generator, record.name, command);
        if (record.description) |desc| {
            try template.setDescription(desc);
        }
        if (record.category) |cat| {
            try template.setCategory(cat);
        }
        template.created_at = @intCast(record.created_at);
        template.updated_at = @intCast(record.updated_at);
        try templates.append(allocator, template);
    }

    return templates;
}

fn parseMethod(label: []const u8) ?core.models.command.HttpMethod {
    if (std.ascii.eqlIgnoreCase(label, "GET")) return .get;
    if (std.ascii.eqlIgnoreCase(label, "POST")) return .post;
    if (std.ascii.eqlIgnoreCase(label, "PUT")) return .put;
    if (std.ascii.eqlIgnoreCase(label, "DELETE")) return .delete;
    if (std.ascii.eqlIgnoreCase(label, "PATCH")) return .patch;
    if (std.ascii.eqlIgnoreCase(label, "HEAD")) return .head;
    if (std.ascii.eqlIgnoreCase(label, "OPTIONS")) return .options;
    if (std.ascii.eqlIgnoreCase(label, "TRACE")) return .trace;
    if (std.ascii.eqlIgnoreCase(label, "CONNECT")) return .connect;
    return null;
}

pub fn seedTemplates(allocator: Allocator, generator: *core.IdGenerator) !std.ArrayList(CommandTemplate) {
    var templates = try std.ArrayList(CommandTemplate).initCapacity(allocator, 2);

    var get_command = try CurlCommand.init(allocator, generator);
    allocator.free(get_command.name);
    get_command.name = try allocator.dupe(u8, "GET Example");
    allocator.free(get_command.url);
    get_command.url = try allocator.dupe(u8, "https://httpbin.org/get");
    get_command.method = .get;
    try get_command.addOption(generator, "-i", null);

    var get_template = try CommandTemplate.init(allocator, generator, "GET Example", get_command);
    try get_template.setDescription("Simple GET request");
    try get_template.setCategory("Examples");
    try templates.append(allocator, get_template);

    var post_command = try CurlCommand.init(allocator, generator);
    allocator.free(post_command.name);
    post_command.name = try allocator.dupe(u8, "POST JSON");
    allocator.free(post_command.url);
    post_command.url = try allocator.dupe(u8, "https://httpbin.org/post");
    post_command.method = .post;
    try post_command.addHeader(generator, "Content-Type", "application/json");
    const body = try allocator.dupe(u8, "{\"key\": \"value\"}");
    post_command.setBody(.{ .raw = body });
    try post_command.addOption(generator, "-i", null);

    var post_template = try CommandTemplate.init(allocator, generator, "POST JSON", post_command);
    try post_template.setDescription("POST with JSON body");
    try post_template.setCategory("Examples");
    try templates.append(allocator, post_template);

    return templates;
}

pub fn seedEnvironments(allocator: Allocator, generator: *core.IdGenerator) !std.ArrayList(Environment) {
    var environments = try std.ArrayList(Environment).initCapacity(allocator, 1);
    const env = try Environment.init(allocator, generator, "Default");
    try environments.append(allocator, env);
    return environments;
}

pub fn deinitTemplates(allocator: Allocator, templates: *std.ArrayList(CommandTemplate)) void {
    for (templates.items) |*template| {
        template.deinit();
    }
    templates.deinit(allocator);
}

pub fn deinitEnvironments(allocator: Allocator, environments: *std.ArrayList(Environment)) void {
    for (environments.items) |*env| {
        env.deinit();
    }
    environments.deinit(allocator);
}

pub fn deinitHistory(allocator: Allocator, history: *std.ArrayList(CurlCommand)) void {
    for (history.items) |*command| {
        command.deinit();
    }
    history.deinit(allocator);
}

test "seed data mirrors rust defaults" {
    var generator = core.IdGenerator{};
    var templates = try seedTemplates(std.testing.allocator, &generator);
    defer deinitTemplates(std.testing.allocator, &templates);

    var environments = try seedEnvironments(std.testing.allocator, &generator);
    defer deinitEnvironments(std.testing.allocator, &environments);

    try std.testing.expectEqual(@as(usize, 2), templates.items.len);
    try std.testing.expectEqual(@as(usize, 1), environments.items.len);
}
