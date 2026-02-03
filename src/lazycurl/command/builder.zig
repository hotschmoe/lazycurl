const std = @import("std");
const core = @import("lazycurl_core");

const Allocator = std.mem.Allocator;
const CurlCommand = core.models.command.CurlCommand;
const RequestBody = core.models.command.RequestBody;
const HttpMethod = core.models.command.HttpMethod;
const Environment = core.models.environment.Environment;

pub const CommandBuilder = struct {
    const status_marker_prefix = "__LAZYCURL_HTTP_STATUS__";
    const status_marker_format = "\\n" ++ status_marker_prefix ++ "%{http_code}\\n";
    const include_flag = "-i";

    pub fn build(allocator: Allocator, command: *const CurlCommand, environment: *const Environment) ![]u8 {
        return buildInternal(allocator, command, environment, false);
    }

    pub fn buildForExecution(allocator: Allocator, command: *const CurlCommand, environment: *const Environment) ![]u8 {
        return buildInternal(allocator, command, environment, true);
    }

    fn buildInternal(
        allocator: Allocator,
        command: *const CurlCommand,
        environment: *const Environment,
        include_status_marker: bool,
    ) ![]u8 {
        var args = try std.ArrayList([]u8).initCapacity(allocator, 8);
        defer {
            for (args.items) |arg| allocator.free(arg);
            args.deinit(allocator);
        }

        try args.append(allocator, try allocator.dupe(u8, "curl"));

        var has_write_out = false;
        var has_include = false;
        for (command.options.items) |option| {
            if (!option.enabled) continue;
            if (include_status_marker and isIncludeFlag(option.flag)) {
                has_include = true;
            }
            if (include_status_marker and isWriteOutFlag(option.flag)) {
                has_write_out = true;
                if (try appendWriteOutOption(allocator, &args, option, environment)) continue;
            }
            try args.append(allocator, try allocator.dupe(u8, option.flag));
            if (option.value) |value| {
                const substituted = try substituteEnvVars(allocator, value, environment);
                try args.append(allocator, substituted);
            }
        }
        if (include_status_marker and !has_include) {
            try args.append(allocator, try allocator.dupe(u8, include_flag));
        }
        if (include_status_marker and !has_write_out) {
            try args.append(allocator, try allocator.dupe(u8, "-w"));
            try args.append(allocator, try allocator.dupe(u8, status_marker_format));
        }

        if (command.method) |method| {
            if (method != HttpMethod.default()) {
                try args.append(allocator, try allocator.dupe(u8, "-X"));
                try args.append(allocator, try allocator.dupe(u8, method.asString()));
            }
        }

        for (command.headers.items) |header| {
            if (!header.enabled) continue;
            const value = try substituteEnvVars(allocator, header.value, environment);
            defer allocator.free(value);
            const formatted = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ header.key, value });
            try args.append(allocator, try allocator.dupe(u8, "-H"));
            try args.append(allocator, formatted);
        }

        if (command.body) |body| {
            switch (body) {
                .raw => |content| {
                    if (std.mem.trim(u8, content, " \t\r\n").len > 0) {
                        const substituted = try substituteEnvVars(allocator, content, environment);
                        try args.append(allocator, try allocator.dupe(u8, "-d"));
                        try args.append(allocator, substituted);
                    }
                },
                .form_data => |list| {
                    for (list.items) |item| {
                        if (!item.enabled) continue;
                        const value = try substituteEnvVars(allocator, item.value, environment);
                        defer allocator.free(value);
                        const formatted = try std.fmt.allocPrint(allocator, "{s}={s}", .{ item.key, value });
                        try args.append(allocator, try allocator.dupe(u8, "-F"));
                        try args.append(allocator, formatted);
                    }
                },
                .binary => |path| {
                    const formatted = try std.fmt.allocPrint(allocator, "@{s}", .{path});
                    try args.append(allocator, try allocator.dupe(u8, "--data-binary"));
                    try args.append(allocator, formatted);
                },
                .none => {},
            }
        }

        const url_with_query = try buildUrlWithQuery(allocator, command, environment);
        defer allocator.free(url_with_query);
        try args.append(allocator, try allocator.dupe(u8, url_with_query));

        return formatCurlCommand(allocator, args.items);
    }

    fn appendWriteOutOption(
        allocator: Allocator,
        args: *std.ArrayList([]u8),
        option: core.models.command.CurlOption,
        environment: *const Environment,
    ) !bool {
        if (writeOutInlineValue(option.flag)) |inline_value| {
            if (std.mem.indexOf(u8, inline_value, status_marker_prefix) != null) {
                try args.append(allocator, try allocator.dupe(u8, option.flag));
                return true;
            }
            const prefix = if (std.mem.startsWith(u8, option.flag, "--write-out=")) "--write-out=" else "-w";
            const new_flag = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
                prefix,
                inline_value,
                status_marker_format,
            });
            try args.append(allocator, new_flag);
            return true;
        }

        try args.append(allocator, try allocator.dupe(u8, option.flag));
        if (option.value) |value| {
            const substituted = try substituteEnvVars(allocator, value, environment);
            if (std.mem.indexOf(u8, substituted, status_marker_prefix) != null) {
                try args.append(allocator, substituted);
                return true;
            }
            const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ substituted, status_marker_format });
            allocator.free(substituted);
            try args.append(allocator, combined);
            return true;
        }

        try args.append(allocator, try allocator.dupe(u8, status_marker_format));
        return true;
    }

    fn buildUrlWithQuery(allocator: Allocator, command: *const CurlCommand, environment: *const Environment) ![]u8 {
        const base_url = try substituteEnvVars(allocator, command.url, environment);
        if (command.query_params.items.len == 0) return base_url;

        var has_enabled = false;
        for (command.query_params.items) |param| {
            if (param.enabled) {
                has_enabled = true;
                break;
            }
        }
        if (!has_enabled) return base_url;

        var query_builder = try std.ArrayList(u8).initCapacity(allocator, 64);
        defer query_builder.deinit(allocator);
        var first = true;

        for (command.query_params.items) |param| {
            if (!param.enabled) continue;
            if (!first) try query_builder.append(allocator, '&');
            first = false;

            try query_builder.appendSlice(allocator, param.key);
            try query_builder.append(allocator, '=');

            const value = try substituteEnvVars(allocator, param.value, environment);
            defer allocator.free(value);
            const encoded = try percentEncode(allocator, value);
            defer allocator.free(encoded);
            try query_builder.appendSlice(allocator, encoded);
        }

        const query = try query_builder.toOwnedSlice(allocator);
        defer allocator.free(query);

        const separator: []const u8 = if (std.mem.indexOfScalar(u8, base_url, '?') != null) "&" else "?";
        const combined = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base_url, separator, query });
        allocator.free(base_url);
        return combined;
    }

    pub fn substituteEnvVars(allocator: Allocator, input: []const u8, environment: *const Environment) ![]u8 {
        var output = try std.ArrayList(u8).initCapacity(allocator, input.len);
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            if (i + 1 < input.len and input[i] == '{' and input[i + 1] == '{') {
                const start = i;
                const rest = input[(i + 2)..];
                if (std.mem.indexOf(u8, rest, "}}")) |rel_end| {
                    const token = rest[0..rel_end];
                    const full_end = i + 2 + rel_end + 2;
                    const replacement = resolveEnvToken(token, input[start..full_end], environment);
                    try output.appendSlice(allocator, replacement);
                    i = full_end;
                    continue;
                }
            }
            try output.append(allocator, input[i]);
            i += 1;
        }

        return output.toOwnedSlice(allocator);
    }

    fn resolveEnvToken(token: []const u8, fallback: []const u8, environment: *const Environment) []const u8 {
        if (std.mem.indexOfScalar(u8, token, ':')) |idx| {
            const key = token[0..idx];
            const default_value = token[(idx + 1)..];
            if (environment.getVariable(key)) |value| return value;
            return default_value;
        }
        if (environment.getVariable(token)) |value| return value;
        return fallback;
    }

    fn percentEncode(allocator: Allocator, input: []const u8) ![]u8 {
        var output = try std.ArrayList(u8).initCapacity(allocator, input.len);
        defer output.deinit(allocator);

        for (input) |byte| {
            if (isUnreserved(byte)) {
                try output.append(allocator, byte);
            } else {
                const hi = hexDigit(@intCast((byte >> 4) & 0x0f));
                const lo = hexDigit(@intCast(byte & 0x0f));
                try output.append(allocator, '%');
                try output.append(allocator, hi);
                try output.append(allocator, lo);
            }
        }
        return output.toOwnedSlice(allocator);
    }

    fn isUnreserved(byte: u8) bool {
        return std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~';
    }

    fn hexDigit(value: u4) u8 {
        return if (value < 10) ('0' + @as(u8, value)) else ('A' + @as(u8, value - 10));
    }

    fn formatCurlCommand(allocator: Allocator, args: []const []const u8) ![]u8 {
        var output = try std.ArrayList(u8).initCapacity(allocator, 64);
        defer output.deinit(allocator);

        for (args, 0..) |arg, index| {
            if (index > 0) try output.append(allocator, ' ');
            if (needsQuoting(arg) and !startsWithQuote(arg)) {
                try output.append(allocator, '\'');
                for (arg) |byte| {
                    if (byte == '\'') {
                        try output.appendSlice(allocator, "'\"'\"'");
                    } else {
                        try output.append(allocator, byte);
                    }
                }
                try output.append(allocator, '\'');
            } else {
                try output.appendSlice(allocator, arg);
            }
        }

        return output.toOwnedSlice(allocator);
    }

    fn startsWithQuote(arg: []const u8) bool {
        return std.mem.startsWith(u8, arg, "\"") or std.mem.startsWith(u8, arg, "'");
    }

    pub fn needsQuoting(arg: []const u8) bool {
        if (std.mem.startsWith(u8, arg, "http://") or std.mem.startsWith(u8, arg, "https://") or std.mem.startsWith(u8, arg, "ftp://")) {
            return false;
        }
        if (arg.len == 0) return true;
        for (arg) |byte| {
            switch (byte) {
                ' ', '\t', '\n', '\r',
                '"', '\'', '\\',
                '|', '&', ';', '(', ')',
                '<', '>',
                '$', '`',
                '*', '?', '[', ']',
                '{', '}',
                '!', '#',
                '~' => return true,
                else => {},
            }
        }
        return false;
    }
};

fn isWriteOutFlag(flag: []const u8) bool {
    if (std.mem.eql(u8, flag, "-w") or std.mem.eql(u8, flag, "--write-out")) return true;
    if (std.mem.startsWith(u8, flag, "-w")) return true;
    return std.mem.startsWith(u8, flag, "--write-out");
}

fn writeOutInlineValue(flag: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, flag, "--write-out=")) {
        return flag["--write-out=".len..];
    }
    if (std.mem.startsWith(u8, flag, "-w") and flag.len > 2) {
        return flag[2..];
    }
    return null;
}

fn isIncludeFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "-i") or std.mem.eql(u8, flag, "--include");
}

test "build simple command" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.build(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("curl https://example.com", result);
}

test "build for execution adds write-out status marker" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.buildForExecution(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(
        "curl -i -w '\\n__LAZYCURL_HTTP_STATUS__%{http_code}\\n' https://example.com",
        result,
    );
}

test "build for execution keeps custom write-out" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");
    try command.addOption(&generator, "--write-out", "%{http_code}");

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.buildForExecution(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(
        "curl --write-out '%{http_code}\\n__LAZYCURL_HTTP_STATUS__%{http_code}\\n' -i https://example.com",
        result,
    );
}

test "build command with options" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");
    try command.addOption(&generator, "-v", null);

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.build(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("curl -v https://example.com", result);
}

test "build command with headers" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");
    try command.addHeader(&generator, "Content-Type", "application/json");

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.build(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("curl -H 'Content-Type: application/json' https://example.com", result);
}

test "build command with method" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");
    command.method = .post;

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.build(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("curl -X POST https://example.com", result);
}

test "build command with query params" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");
    try command.addQueryParam(&generator, "q", "test query");

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.build(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("curl https://example.com?q=test%20query", result);
}

test "substitute env vars" {
    var generator = core.IdGenerator{};
    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();
    try environment.addVariable(&generator, "api_url", "https://api.example.com", false);
    try environment.addVariable(&generator, "api_key", "secret-key", true);

    const result = try CommandBuilder.substituteEnvVars(std.testing.allocator, "{{api_url}}/users?key={{api_key}}", &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("https://api.example.com/users?key=secret-key", result);
}

test "substitute env vars with default" {
    var generator = core.IdGenerator{};
    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.substituteEnvVars(std.testing.allocator, "{{api_url:https://default.example.com}}/users", &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("https://default.example.com/users", result);
}

test "build command with json body" {
    var generator = core.IdGenerator{};
    var command = try CurlCommand.init(std.testing.allocator, &generator);
    defer command.deinit();
    command.allocator.free(command.url);
    command.url = try command.allocator.dupe(u8, "https://example.com");
    command.method = .post;
    try command.addHeader(&generator, "Content-Type", "application/json");
    const body = try command.allocator.dupe(u8, "{\"key\": \"value\", \"number\": 42}");
    command.setBody(.{ .raw = body });

    var environment = try Environment.init(std.testing.allocator, &generator, "test");
    defer environment.deinit();

    const result = try CommandBuilder.build(std.testing.allocator, &command, &environment);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "'{\"key\": \"value\", \"number\": 42}'") != null);
}

test "needs quoting" {
    try std.testing.expect(CommandBuilder.needsQuoting("{\"key\": \"value\"}"));
    try std.testing.expect(CommandBuilder.needsQuoting("hello world"));
    try std.testing.expect(CommandBuilder.needsQuoting("test&more"));
    try std.testing.expect(CommandBuilder.needsQuoting("test|more"));
    try std.testing.expect(CommandBuilder.needsQuoting("test$var"));
    try std.testing.expect(CommandBuilder.needsQuoting(""));

    try std.testing.expect(!CommandBuilder.needsQuoting("simple"));
    try std.testing.expect(!CommandBuilder.needsQuoting("test123"));
    try std.testing.expect(!CommandBuilder.needsQuoting("test-value"));
    try std.testing.expect(!CommandBuilder.needsQuoting("test_value"));
    try std.testing.expect(!CommandBuilder.needsQuoting("test.value"));

    try std.testing.expect(!CommandBuilder.needsQuoting("https://example.com?param={\"key\":\"value\"}"));
    try std.testing.expect(!CommandBuilder.needsQuoting("http://example.com/path?q=test&other=value"));
    try std.testing.expect(!CommandBuilder.needsQuoting("https://api.example.com/users?filter={\"active\":true}"));
}
