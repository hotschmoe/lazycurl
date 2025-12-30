const std = @import("std");
const core = @import("zvrl_core");
const vaxis = @import("vaxis");
const execution = @import("zvrl_execution");
const persistence = @import("zvrl_persistence");
const command_builder = @import("zvrl_command");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    executor: execution.executor.CommandExecutor,
    active_job: ?execution.executor.ExecutionJob = null,
    last_result: ?execution.executor.ExecutionResult = null,
    stream_stdout: std.ArrayList(u8),
    stream_stderr: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !Runtime {
        return .{
            .allocator = allocator,
            .executor = execution.executor.CommandExecutor.init(allocator),
            .stream_stdout = try std.ArrayList(u8).initCapacity(allocator, 0),
            .stream_stderr = try std.ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Runtime) void {
        if (self.active_job) |*job| {
            job.deinit();
        }
        if (self.last_result) |*result| {
            result.deinit(self.allocator);
        }
        self.stream_stdout.deinit(self.allocator);
        self.stream_stderr.deinit(self.allocator);
    }

    pub fn startExecution(self: *Runtime, command: []const u8) !void {
        if (self.active_job != null) return error.ExecutionInProgress;
        self.clearStreamBuffers();
        self.clearLastResult();
        self.active_job = try self.executor.start(command);
    }

    pub fn tick(self: *Runtime) !void {
        if (self.active_job) |*job| {
            const sink = execution.executor.OutputSink{
                .ctx = self,
                .handler = handleOutput,
            };
            const done = try job.poll(0, sink);
            if (done) {
                const result = try job.finish();
                self.last_result = result;
                job.deinit();
                self.active_job = null;
            }
        }
    }

    fn clearStreamBuffers(self: *Runtime) void {
        self.stream_stdout.clearRetainingCapacity();
        self.stream_stderr.clearRetainingCapacity();
    }

    fn clearLastResult(self: *Runtime) void {
        if (self.last_result) |*result| {
            result.deinit(self.allocator);
            self.last_result = null;
        }
    }

    fn handleOutput(ctx: ?*anyopaque, stream: execution.executor.Stream, chunk: []const u8) void {
        const app: *Runtime = @ptrCast(@alignCast(ctx.?));
        switch (stream) {
            .stdout => _ = app.stream_stdout.appendSlice(app.allocator, chunk) catch {},
            .stderr => _ = app.stream_stderr.appendSlice(app.allocator, chunk) catch {},
        }
    }
};

pub const AppState = enum {
    normal,
    editing,
    method_dropdown,
    exiting,
};

pub const EditField = enum {
    url,
    method,
    header_key,
    header_value,
    query_param_key,
    query_param_value,
    body,
    option_value,
};

pub const Tab = enum {
    url,
    headers,
    body,
    options,
};

pub const UrlField = union(enum) {
    url,
    method,
    query_param: usize,
};

pub const BodyField = enum {
    type,
    content,
};

pub const SelectedField = union(enum) {
    url: UrlField,
    headers: usize,
    body: BodyField,
    options: usize,
};

pub const UiState = struct {
    active_tab: Tab = .url,
    selected_field: SelectedField = .{ .url = .url },
    selected_template: ?usize = null,
    method_dropdown_index: usize = 0,
    cursor_visible: bool = true,
    cursor_blink_counter: u8 = 0,
};

pub const KeyCode = union(enum) {
    tab,
    back_tab,
    up,
    down,
    left,
    right,
    enter,
    escape,
    char: u8,
};

pub const Modifiers = struct {
    ctrl: bool = false,
    shift: bool = false,
};

pub const KeyInput = struct {
    code: KeyCode,
    mods: Modifiers = .{},
};

pub const App = struct {
    allocator: std.mem.Allocator,
    id_generator: core.IdGenerator = .{},
    state: AppState = .normal,
    editing_field: ?EditField = null,
    ui: UiState = .{},
    current_command: core.models.command.CurlCommand,
    templates: std.ArrayList(core.models.template.CommandTemplate),
    environments: std.ArrayList(core.models.environment.Environment),
    history: std.ArrayList(core.models.command.CurlCommand),
    current_environment_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !App {
        var generator = core.IdGenerator{};
        var current_command = try core.models.command.CurlCommand.init(allocator, &generator);
        try current_command.addOption(&generator, "-i", null);

        const templates = try persistence.seedTemplates(allocator, &generator);
        const environments = try persistence.seedEnvironments(allocator, &generator);
        const history = try std.ArrayList(core.models.command.CurlCommand).initCapacity(allocator, 0);

        return .{
            .allocator = allocator,
            .id_generator = generator,
            .current_command = current_command,
            .templates = templates,
            .environments = environments,
            .history = history,
        };
    }

    pub fn deinit(self: *App) void {
        self.current_command.deinit();
        persistence.deinitTemplates(self.allocator, &self.templates);
        persistence.deinitEnvironments(self.allocator, &self.environments);
        persistence.deinitHistory(self.allocator, &self.history);
    }

    pub fn handleKey(self: *App, input: KeyInput) !bool {
        switch (self.state) {
            .normal => return self.handleNormalKey(input),
            .editing => return self.handleEditingKey(input),
            .method_dropdown => return self.handleMethodDropdownKey(input),
            .exiting => return true,
        }
    }

    fn handleNormalKey(self: *App, input: KeyInput) !bool {
        if (input.mods.ctrl) {
            switch (input.code) {
                .char => |ch| {
                    if (ch == 'q') {
                        self.state = .exiting;
                        return true;
                    }
                },
                else => {},
            }
        }

        switch (input.code) {
            .tab => {
                self.nextTab();
                return false;
            },
            .back_tab => {
                self.prevTab();
                return false;
            },
            .up => {
                if (self.ui.selected_template != null) {
                    self.navigateTemplateUp();
                } else {
                    self.navigateFieldUp();
                }
                return false;
            },
            .down => {
                if (self.ui.selected_template != null) {
                    self.navigateTemplateDown();
                } else {
                    self.navigateFieldDown();
                }
                return false;
            },
            .left => {
                self.navigateFieldLeft();
                return false;
            },
            .right => {
                if (self.ui.selected_template != null) {
                    self.ui.selected_template = null;
                    self.ui.selected_field = .{ .url = .method };
                } else {
                    self.navigateFieldRight();
                }
                return false;
            },
            .enter => {
                if (self.ui.selected_template) |idx| {
                    try self.loadTemplate(idx);
                    self.ui.selected_template = null;
                    self.ui.selected_field = .{ .url = .url };
                } else {
                    try self.startEditingField();
                }
                return false;
            },
            else => return false,
        }
    }

    fn handleEditingKey(self: *App, input: KeyInput) !bool {
        switch (input.code) {
            .escape => {
                self.state = .normal;
                self.editing_field = null;
                return false;
            },
            else => return false,
        }
    }

    fn handleMethodDropdownKey(self: *App, input: KeyInput) !bool {
        const methods = methodList();
        switch (input.code) {
            .up => {
                if (self.ui.method_dropdown_index == 0) {
                    self.ui.method_dropdown_index = methods.len - 1;
                } else {
                    self.ui.method_dropdown_index -= 1;
                }
                return false;
            },
            .down => {
                if (self.ui.method_dropdown_index + 1 >= methods.len) {
                    self.ui.method_dropdown_index = 0;
                } else {
                    self.ui.method_dropdown_index += 1;
                }
                return false;
            },
            .enter => {
                self.current_command.method = methods[self.ui.method_dropdown_index];
                self.state = .normal;
                return false;
            },
            .escape => {
                self.state = .normal;
                return false;
            },
            else => return false,
        }
    }

    pub fn executeCommand(self: *App) ![]u8 {
        const environment = self.currentEnvironment();
        return command_builder.builder.CommandBuilder.build(self.allocator, &self.current_command, environment);
    }

    fn currentEnvironment(self: *App) *const core.models.environment.Environment {
        std.debug.assert(self.environments.items.len > 0);
        if (self.current_environment_index >= self.environments.items.len) {
            self.current_environment_index = 0;
        }
        return &self.environments.items[self.current_environment_index];
    }

    fn startEditingField(self: *App) !void {
        switch (self.ui.selected_field) {
            .url => |field| switch (field) {
                .method => {
                    self.openMethodDropdown();
                },
                else => {
                    self.state = .editing;
                    self.editing_field = .url;
                },
            },
            .headers => {
                self.state = .editing;
                self.editing_field = .header_value;
            },
            .body => {
                self.state = .editing;
                self.editing_field = .body;
            },
            .options => {
                self.state = .editing;
                self.editing_field = .option_value;
            },
        }
    }

    fn openMethodDropdown(self: *App) void {
        const methods = methodList();
        const current = self.current_command.method orelse .get;
        self.ui.method_dropdown_index = 0;
        for (methods, 0..) |method, idx| {
            if (method == current) {
                self.ui.method_dropdown_index = idx;
                break;
            }
        }
        self.state = .method_dropdown;
    }

    fn nextTab(self: *App) void {
        self.ui.active_tab = switch (self.ui.active_tab) {
            .url => .headers,
            .headers => .body,
            .body => .options,
            .options => .url,
        };
        self.ui.selected_field = defaultSelectedField(self.ui.active_tab);
    }

    fn prevTab(self: *App) void {
        self.ui.active_tab = switch (self.ui.active_tab) {
            .url => .options,
            .headers => .url,
            .body => .headers,
            .options => .body,
        };
        self.ui.selected_field = defaultSelectedField(self.ui.active_tab);
    }

    fn navigateTemplateUp(self: *App) void {
        if (self.ui.selected_template) |idx| {
            if (idx > 0) self.ui.selected_template = idx - 1;
        }
    }

    fn navigateTemplateDown(self: *App) void {
        if (self.ui.selected_template) |idx| {
            if (idx + 1 < self.templates.items.len) self.ui.selected_template = idx + 1;
        }
    }

    fn navigateFieldUp(self: *App) void {
        const current = self.ui.selected_field;
        switch (current) {
            .url => |field| switch (field) {
                .url => {},
                .method => self.ui.selected_field = .{ .url = .url },
                .query_param => |idx| {
                    if (idx == 0) {
                        self.ui.selected_field = .{ .url = .method };
                    } else {
                        self.ui.selected_field = .{ .url = .{ .query_param = idx - 1 } };
                    }
                },
            },
            .headers => |idx| {
                if (idx > 0) {
                    self.ui.selected_field = .{ .headers = idx - 1 };
                }
            },
            .body => |field| switch (field) {
                .type => {},
                .content => self.ui.selected_field = .{ .body = .type },
            },
            .options => |idx| {
                if (idx > 0) {
                    self.ui.selected_field = .{ .options = idx - 1 };
                }
            },
        }
    }

    fn navigateFieldDown(self: *App) void {
        const current = self.ui.selected_field;
        switch (current) {
            .url => |field| switch (field) {
                .url => self.ui.selected_field = .{ .url = .method },
                .method => if (self.current_command.query_params.items.len > 0) {
                    self.ui.selected_field = .{ .url = .{ .query_param = 0 } };
                },
                .query_param => |idx| {
                    if (idx + 1 < self.current_command.query_params.items.len) {
                        self.ui.selected_field = .{ .url = .{ .query_param = idx + 1 } };
                    }
                },
            },
            .headers => |idx| {
                if (idx + 1 < self.current_command.headers.items.len) {
                    self.ui.selected_field = .{ .headers = idx + 1 };
                }
            },
            .body => |field| switch (field) {
                .type => self.ui.selected_field = .{ .body = .content },
                .content => {},
            },
            .options => |idx| {
                if (idx + 1 < self.current_command.options.items.len) {
                    self.ui.selected_field = .{ .options = idx + 1 };
                }
            },
        }
    }

    fn navigateFieldLeft(self: *App) void {
        switch (self.ui.selected_field) {
            .url => |field| switch (field) {
                .url => self.ui.selected_field = .{ .url = .method },
                .method => {
                    self.ui.selected_template = 0;
                },
                .query_param => self.ui.selected_field = .{ .url = .method },
            },
            else => self.ui.selected_field = .{ .url = .method },
        }
    }

    fn navigateFieldRight(self: *App) void {
        switch (self.ui.selected_field) {
            .url => |field| switch (field) {
                .method => {
                    self.ui.selected_field = defaultSelectedField(self.ui.active_tab);
                },
                else => {},
            },
            else => {},
        }
    }

    pub fn toggleCursor(self: *App) void {
        self.ui.cursor_blink_counter = (self.ui.cursor_blink_counter + 1) % 6;
        if (self.ui.cursor_blink_counter == 0) {
            self.ui.cursor_visible = !self.ui.cursor_visible;
        }
    }

    fn loadTemplate(self: *App, idx: usize) !void {
        if (idx >= self.templates.items.len) return;
        const cloned = try cloneCommand(self.allocator, &self.id_generator, &self.templates.items[idx].command);
        self.current_command.deinit();
        self.current_command = cloned;
    }
};

fn methodList() []const core.models.command.HttpMethod {
    return &[_]core.models.command.HttpMethod{
        .get,
        .post,
        .put,
        .delete,
        .patch,
        .head,
        .options,
        .trace,
        .connect,
    };
}

fn defaultSelectedField(tab: Tab) SelectedField {
    return switch (tab) {
        .url => .{ .url = .url },
        .headers => .{ .headers = 0 },
        .body => .{ .body = .content },
        .options => .{ .options = 0 },
    };
}

fn cloneCommand(
    allocator: std.mem.Allocator,
    generator: *core.IdGenerator,
    source: *const core.models.command.CurlCommand,
) !core.models.command.CurlCommand {
    var cloned = try core.models.command.CurlCommand.init(allocator, generator);

    allocator.free(cloned.name);
    cloned.name = try allocator.dupe(u8, source.name);
    allocator.free(cloned.url);
    cloned.url = try allocator.dupe(u8, source.url);
    cloned.description = if (source.description) |value| try allocator.dupe(u8, value) else null;
    cloned.method = source.method;

    for (cloned.headers.items) |*header| header.deinit(allocator);
    cloned.headers.clearRetainingCapacity();
    for (source.headers.items) |header| {
        try cloned.headers.append(allocator, .{
            .id = generator.nextId(),
            .key = try allocator.dupe(u8, header.key),
            .value = try allocator.dupe(u8, header.value),
            .enabled = header.enabled,
        });
    }

    for (cloned.query_params.items) |*param| param.deinit(allocator);
    cloned.query_params.clearRetainingCapacity();
    for (source.query_params.items) |param| {
        try cloned.query_params.append(allocator, .{
            .id = generator.nextId(),
            .key = try allocator.dupe(u8, param.key),
            .value = try allocator.dupe(u8, param.value),
            .enabled = param.enabled,
        });
    }

    for (cloned.options.items) |*option| option.deinit(allocator);
    cloned.options.clearRetainingCapacity();
    for (source.options.items) |option| {
        const value = if (option.value) |val| try allocator.dupe(u8, val) else null;
        try cloned.options.append(allocator, .{
            .id = generator.nextId(),
            .flag = try allocator.dupe(u8, option.flag),
            .value = value,
            .enabled = option.enabled,
        });
    }

    if (source.body) |body| {
        switch (body) {
            .none => cloned.body = null,
            .raw => |value| {
                cloned.body = .{ .raw = try allocator.dupe(u8, value) };
            },
            .binary => |value| {
                cloned.body = .{ .binary = try allocator.dupe(u8, value) };
            },
            .form_data => |items| {
                var list = try std.ArrayList(core.models.command.FormDataItem).initCapacity(allocator, items.items.len);
                for (items.items) |item| {
                    try list.append(allocator, .{
                        .id = generator.nextId(),
                        .key = try allocator.dupe(u8, item.key),
                        .value = try allocator.dupe(u8, item.value),
                        .enabled = item.enabled,
                    });
                }
                cloned.body = .{ .form_data = list };
            },
        }
    } else {
        cloned.body = null;
    }

    cloned.created_at = core.nowTimestamp();
    cloned.updated_at = cloned.created_at;
    return cloned;
}

test "navigate field up from query param" {
    var app = try App.init(std.testing.allocator);
    defer app.deinit();

    try app.current_command.addQueryParam(&app.id_generator, "a", "b");
    try app.current_command.addQueryParam(&app.id_generator, "c", "d");
    app.ui.selected_field = .{ .url = .{ .query_param = 1 } };
    app.navigateFieldUp();

    switch (app.ui.selected_field) {
        .url => |field| switch (field) {
            .query_param => |idx| try std.testing.expectEqual(@as(usize, 0), idx),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
}

test "execute command builds curl string" {
    var app = try App.init(std.testing.allocator);
    defer app.deinit();

    app.current_command.allocator.free(app.current_command.url);
    app.current_command.url = try app.current_command.allocator.dupe(u8, "https://{{host}}/v1");
    try app.environments.items[0].addVariable(&app.id_generator, "host", "example.com", false);
    const command = try app.executeCommand();
    defer app.allocator.free(command);

    try std.testing.expectEqualStrings("curl -i https://example.com/v1", command);
}

/// Temporary bootstrap entry point for the Zig rewrite.
pub fn run(allocator: std.mem.Allocator) !void {
    const summary = try core.describe(allocator);
    defer allocator.free(summary);

    var runtime = try Runtime.init(allocator);
    defer runtime.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print(
        "TVRL Zig workspace initialized.\n{s}\n",
        .{summary},
    );

    // Placeholder use to ensure the libvaxis dependency is wired up.
    _ = vaxis;
}
