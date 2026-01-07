const std = @import("std");
const core = @import("zvrl_core");
const vaxis = @import("vaxis");
const execution = @import("zvrl_execution");
const persistence = @import("zvrl_persistence");
const command_builder = @import("zvrl_command");
const text_input = @import("zvrl_text_input");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    executor: execution.executor.CommandExecutor,
    active_job: ?execution.executor.ExecutionJob = null,
    last_result: ?execution.executor.ExecutionResult = null,
    last_result_handled: bool = true,
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
        self.last_result_handled = false;
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
                self.last_result_handled = false;
            }
        }
    }

    pub fn setResult(self: *Runtime, result: ?execution.executor.ExecutionResult) void {
        self.clearStreamBuffers();
        self.clearLastResult();
        self.last_result = result;
        self.last_result_handled = true;
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
    selected_environment: ?usize = null,
    selected_history: ?usize = null,
    method_dropdown_index: usize = 0,
    cursor_visible: bool = true,
    cursor_blink_counter: u8 = 0,
    edit_input: text_input.TextInput,
    body_input: text_input.TextInput,
    left_panel: ?LeftPanel = null,
    templates_expanded: bool = true,
    environments_expanded: bool = true,
    history_expanded: bool = true,
    templates_scroll: usize = 0,
    environments_scroll: usize = 0,
    history_scroll: usize = 0,
};

pub const LeftPanel = enum {
    templates,
    environments,
    history,
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
    backspace,
    delete,
    home,
    end,
    f2,
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
    ui: UiState,
    current_command: core.models.command.CurlCommand,
    templates: std.ArrayList(core.models.template.CommandTemplate),
    environments: std.ArrayList(core.models.environment.Environment),
    history: std.ArrayList(core.models.command.CurlCommand),
    history_results: std.ArrayList(?execution.executor.ExecutionResult),
    pending_history_command: ?core.models.command.CurlCommand = null,
    current_environment_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !App {
        var generator = core.IdGenerator{};
        var current_command = try core.models.command.CurlCommand.init(allocator, &generator);
        try current_command.addOption(&generator, "-i", null);

        const templates = try persistence.seedTemplates(allocator, &generator);
        const environments = try persistence.seedEnvironments(allocator, &generator);
        const history = try std.ArrayList(core.models.command.CurlCommand).initCapacity(allocator, 0);
        const history_results = try std.ArrayList(?execution.executor.ExecutionResult).initCapacity(allocator, 0);
        const edit_input = try text_input.TextInput.init(allocator);
        const body_input = try text_input.TextInput.init(allocator);

        return .{
            .allocator = allocator,
            .id_generator = generator,
            .current_command = current_command,
            .templates = templates,
            .environments = environments,
            .history = history,
            .history_results = history_results,
            .ui = .{
                .edit_input = edit_input,
                .body_input = body_input,
            },
        };
    }

    pub fn deinit(self: *App) void {
        self.current_command.deinit();
        persistence.deinitTemplates(self.allocator, &self.templates);
        persistence.deinitEnvironments(self.allocator, &self.environments);
        persistence.deinitHistory(self.allocator, &self.history);
        for (self.history_results.items) |*maybe_result| {
            if (maybe_result.*) |*result| {
                result.deinit(self.allocator);
            }
        }
        self.history_results.deinit(self.allocator);
        if (self.pending_history_command) |*command| {
            command.deinit();
        }
        self.ui.edit_input.deinit();
        self.ui.body_input.deinit();
    }

    pub fn handleKey(self: *App, input: KeyInput, runtime: *Runtime) !bool {
        switch (self.state) {
            .normal => return self.handleNormalKey(input, runtime),
            .editing => return self.handleEditingKey(input),
            .method_dropdown => return self.handleMethodDropdownKey(input),
            .exiting => return true,
        }
    }

    fn handleNormalKey(self: *App, input: KeyInput, runtime: *Runtime) !bool {
        if (input.mods.ctrl) {
            switch (input.code) {
                .char => |ch| {
                    if (ch == 'x') {
                        self.state = .exiting;
                        return true;
                    }
                    if (ch == 't') {
                        self.ui.templates_expanded = !self.ui.templates_expanded;
                        self.focusLeftPanel(.templates);
                        return false;
                    }
                    if (ch == 'e') {
                        self.ui.environments_expanded = !self.ui.environments_expanded;
                        self.focusLeftPanel(.environments);
                        return false;
                    }
                    if (ch == 'h') {
                        self.ui.history_expanded = !self.ui.history_expanded;
                        self.focusLeftPanel(.history);
                        return false;
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
                if (self.ui.left_panel != null) {
                    self.navigateLeftPanelUp();
                } else {
                    self.navigateFieldUp();
                }
                return false;
            },
            .down => {
                if (self.ui.left_panel != null) {
                    self.navigateLeftPanelDown();
                } else {
                    self.navigateFieldDown();
                }
                return false;
            },
            .left => {
                if (self.ui.left_panel == null) {
                    self.navigateFieldLeft();
                } else {
                    if (self.ui.left_panel.? == .history) {
                        self.clearLeftPanelFocus();
                        self.ui.selected_field = .{ .url = .url };
                    }
                    return false;
                }
                return false;
            },
            .right => {
                if (self.ui.left_panel != null) {
                    if (self.ui.left_panel.? == .history) {
                        return false;
                    }
                    self.clearLeftPanelFocus();
                    self.ui.selected_field = .{ .url = .method };
                } else {
                    if (self.isMethodSelected()) {
                        self.ui.selected_field = .{ .url = .url };
                    } else if (self.isUrlColumnSelected()) {
                        self.focusLeftPanel(.history);
                    }
                }
                return false;
            },
            .enter => {
                if (self.ui.left_panel) |panel| {
                    switch (panel) {
                        .templates => if (self.ui.selected_template) |idx| {
                            try self.loadTemplate(idx);
                            self.clearLeftPanelFocus();
                            self.ui.selected_field = .{ .url = .url };
                        },
                        .environments => if (self.ui.selected_environment) |idx| {
                            if (idx < self.environments.items.len) {
                                self.current_environment_index = idx;
                            }
                            self.clearLeftPanelFocus();
                        },
                        .history => if (self.ui.selected_history) |idx| {
                            try self.loadHistoryEntry(runtime, idx);
                            self.clearLeftPanelFocus();
                            self.ui.selected_field = .{ .url = .url };
                        },
                    }
                } else {
                    try self.startEditingField();
                }
                return false;
            },
            else => return false,
        }
    }

    fn handleEditingKey(self: *App, input: KeyInput) !bool {
        if (input.code == .escape) {
            self.state = .normal;
            self.editing_field = null;
            return false;
        }

        const field = self.editing_field orelse return false;
        if (field == .body) {
            return self.handleBodyEditingKey(input);
        }

        return self.handleSingleLineEditingKey(input);
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

    pub fn buildCommandPreview(self: *App, allocator: std.mem.Allocator) ![]u8 {
        const environment = self.currentEnvironment();
        return command_builder.builder.CommandBuilder.build(allocator, &self.current_command, environment);
    }

    pub fn addHistoryFromCurrent(self: *App, runtime: *Runtime) !void {
        var entry: core.models.command.CurlCommand = undefined;
        if (self.pending_history_command) |*pending| {
            entry = pending.*;
            self.pending_history_command = null;
        } else {
            entry = try cloneCommand(self.allocator, &self.id_generator, &self.current_command);
        }
        errdefer entry.deinit();
        const max_history: usize = 100;
        if (self.history.items.len >= max_history) {
            var oldest = self.history.orderedRemove(0);
            oldest.deinit();
            if (self.history_results.items.len > 0) {
                var oldest_result = self.history_results.orderedRemove(0);
                if (oldest_result) |*result| {
                    result.deinit(self.allocator);
                }
            }
        }
        try self.history.append(self.allocator, entry);
        const stored = if (runtime.last_result) |*result|
            try cloneExecutionResult(self.allocator, result)
        else
            null;
        try self.history_results.append(self.allocator, stored);
    }

    pub fn prepareHistorySnapshot(self: *App) !void {
        if (self.pending_history_command) |*command| {
            command.deinit();
            self.pending_history_command = null;
        }
        const cloned = try cloneCommand(self.allocator, &self.id_generator, &self.current_command);
        self.pending_history_command = cloned;
    }

    pub fn clearPendingHistorySnapshot(self: *App) void {
        if (self.pending_history_command) |*command| {
            command.deinit();
            self.pending_history_command = null;
        }
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
                .url => {
                    self.state = .editing;
                    self.editing_field = .url;
                    try self.ui.edit_input.reset(self.current_command.url);
                },
                .query_param => |idx| {
                    if (idx < self.current_command.query_params.items.len) {
                        self.state = .editing;
                        self.editing_field = .query_param_value;
                        try self.ui.edit_input.reset(self.current_command.query_params.items[idx].value);
                    }
                },
            },
            .headers => {
                self.state = .editing;
                self.editing_field = .header_value;
                switch (self.ui.selected_field) {
                    .headers => |idx| {
                        if (idx < self.current_command.headers.items.len) {
                            try self.ui.edit_input.reset(self.current_command.headers.items[idx].value);
                        }
                    },
                    else => {},
                }
            },
            .body => {
                switch (self.ui.selected_field) {
                    .body => |field| switch (field) {
                        .content => {
                            const allow_raw = if (self.current_command.body) |body| switch (body) {
                                .raw, .none => true,
                                else => false,
                            } else true;
                            if (!allow_raw) return;

                            self.state = .editing;
                            self.editing_field = .body;
                            const content = if (self.current_command.body) |body| switch (body) {
                                .raw => |payload| payload,
                                else => "",
                            } else "";
                            try self.ui.body_input.reset(content);
                        },
                        .type => {},
                    },
                    else => {},
                }
            },
            .options => {
                self.state = .editing;
                self.editing_field = .option_value;
                switch (self.ui.selected_field) {
                    .options => |idx| {
                        if (idx < self.current_command.options.items.len) {
                            if (self.current_command.options.items[idx].value) |value| {
                                try self.ui.edit_input.reset(value);
                            }
                        }
                    },
                    else => {},
                }
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

    pub fn applyMethodDropdownSelection(self: *App) void {
        if (self.state != .method_dropdown) return;
        const methods = methodList();
        if (self.ui.method_dropdown_index < methods.len) {
            self.current_command.method = methods[self.ui.method_dropdown_index];
        }
        self.state = .normal;
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

    fn focusLeftPanel(self: *App, panel: LeftPanel) void {
        self.ui.left_panel = panel;
        switch (panel) {
            .templates => {
                if (self.templates.items.len == 0) {
                    self.ui.selected_template = null;
                } else if (self.ui.selected_template == null) {
                    self.ui.selected_template = 0;
                }
            },
            .environments => {
                if (self.environments.items.len == 0) {
                    self.ui.selected_environment = null;
                } else if (self.ui.selected_environment == null) {
                    self.ui.selected_environment = 0;
                }
            },
            .history => {
                if (self.history.items.len == 0) {
                    self.ui.selected_history = null;
                } else if (self.ui.selected_history == null) {
                    self.ui.selected_history = 0;
                }
            },
        }
    }

    fn clearLeftPanelFocus(self: *App) void {
        self.ui.left_panel = null;
    }

    fn navigateLeftPanelUp(self: *App) void {
        if (self.ui.left_panel == null) return;
        switch (self.ui.left_panel.?) {
            .templates => if (self.ui.selected_template) |idx| {
                if (idx > 0) {
                    self.ui.selected_template = idx - 1;
                } else if (self.ui.environments_expanded and self.environments.items.len > 0) {
                    self.focusLeftPanel(.environments);
                    self.ui.selected_environment = self.environments.items.len - 1;
                }
            },
            .environments => if (self.ui.selected_environment) |idx| {
                if (idx > 0) {
                    self.ui.selected_environment = idx - 1;
                } else if (self.ui.history_expanded and self.history.items.len > 0) {
                    self.focusLeftPanel(.history);
                    self.ui.selected_history = self.history.items.len - 1;
                }
            },
            .history => if (self.ui.selected_history) |idx| {
                if (idx > 0) {
                    self.ui.selected_history = idx - 1;
                }
            },
        }
    }

    fn navigateLeftPanelDown(self: *App) void {
        if (self.ui.left_panel == null) return;
        switch (self.ui.left_panel.?) {
            .templates => if (self.ui.selected_template) |idx| {
                if (idx + 1 < self.templates.items.len) {
                    self.ui.selected_template = idx + 1;
                }
            },
            .environments => if (self.ui.selected_environment) |idx| {
                if (idx + 1 < self.environments.items.len) {
                    self.ui.selected_environment = idx + 1;
                } else if (self.ui.templates_expanded and self.templates.items.len > 0) {
                    self.focusLeftPanel(.templates);
                    self.ui.selected_template = 0;
                }
            },
            .history => if (self.ui.selected_history) |idx| {
                if (idx + 1 < self.history.items.len) {
                    self.ui.selected_history = idx + 1;
                } else if (self.ui.environments_expanded and self.environments.items.len > 0) {
                    self.focusLeftPanel(.environments);
                    self.ui.selected_environment = 0;
                }
            },
        }
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
                    self.focusLeftPanel(.templates);
                },
                .query_param => self.ui.selected_field = .{ .url = .method },
            },
            else => self.ui.selected_field = .{ .url = .method },
        }
    }

    fn isUrlColumnSelected(self: *App) bool {
        return switch (self.ui.selected_field) {
            .url => true,
            else => false,
        };
    }

    fn isMethodSelected(self: *App) bool {
        return switch (self.ui.selected_field) {
            .url => |field| field == .method,
            else => false,
        };
    }

    fn navigateFieldRight(self: *App) void {
        switch (self.ui.selected_field) {
            .url => |field| switch (field) {
                .method => self.ui.selected_field = .{ .url = .url },
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

    fn handleSingleLineEditingKey(self: *App, input: KeyInput) !bool {
        switch (input.code) {
            .enter => {
                try self.commitSingleLineEdit();
                return false;
            },
            .backspace => {
                self.ui.edit_input.backspace();
                return false;
            },
            .delete => {
                self.ui.edit_input.delete();
                return false;
            },
            .left => {
                self.ui.edit_input.moveLeft();
                return false;
            },
            .right => {
                self.ui.edit_input.moveRight();
                return false;
            },
            .home => {
                self.ui.edit_input.moveHome();
                return false;
            },
            .end => {
                self.ui.edit_input.moveEnd();
                return false;
            },
            .char => |ch| {
                if (!input.mods.ctrl) {
                    try self.ui.edit_input.insertByte(ch);
                }
                return false;
            },
            else => return false,
        }
    }

    fn handleBodyEditingKey(self: *App, input: KeyInput) !bool {
        if (input.code == .f2) {
            try self.commitBodyEdit();
            return false;
        }
        if (input.mods.ctrl) {
            switch (input.code) {
                .char => |ch| {
                    if (ch == 's') {
                        try self.commitBodyEdit();
                        return false;
                    }
                },
                else => {},
            }
        }

        switch (input.code) {
            .enter => {
                try self.ui.body_input.insertByte('\n');
                return false;
            },
            .backspace => {
                self.ui.body_input.backspace();
                return false;
            },
            .delete => {
                self.ui.body_input.delete();
                return false;
            },
            .left => {
                self.ui.body_input.moveLeft();
                return false;
            },
            .right => {
                self.ui.body_input.moveRight();
                return false;
            },
            .up => {
                self.ui.body_input.moveUp();
                return false;
            },
            .down => {
                self.ui.body_input.moveDown();
                return false;
            },
            .home => {
                self.ui.body_input.moveHome();
                return false;
            },
            .end => {
                self.ui.body_input.moveEnd();
                return false;
            },
            .char => |ch| {
                if (!input.mods.ctrl) {
                    try self.ui.body_input.insertByte(ch);
                }
                return false;
            },
            else => return false,
        }
    }

    fn commitSingleLineEdit(self: *App) !void {
        const value = self.ui.edit_input.slice();
        switch (self.ui.selected_field) {
            .url => |field| switch (field) {
                .url => {
                    self.allocator.free(self.current_command.url);
                    self.current_command.url = try self.allocator.dupe(u8, value);
                },
                .query_param => |idx| {
                    if (idx < self.current_command.query_params.items.len) {
                        var param = &self.current_command.query_params.items[idx];
                        self.allocator.free(param.value);
                        param.value = try self.allocator.dupe(u8, value);
                    }
                },
                .method => {},
            },
            .headers => |idx| {
                if (idx < self.current_command.headers.items.len) {
                    var header = &self.current_command.headers.items[idx];
                    self.allocator.free(header.value);
                    header.value = try self.allocator.dupe(u8, value);
                }
            },
            .options => |idx| {
                if (idx < self.current_command.options.items.len) {
                    var option = &self.current_command.options.items[idx];
                    if (option.value) |old| self.allocator.free(old);
                    option.value = try self.allocator.dupe(u8, value);
                }
            },
            .body => {},
        }

        self.state = .normal;
        self.editing_field = null;
    }

    fn commitBodyEdit(self: *App) !void {
        const allow_raw = if (self.current_command.body) |body| switch (body) {
            .raw, .none => true,
            else => false,
        } else true;
        if (allow_raw) {
            const value = self.ui.body_input.slice();
            const payload = try self.allocator.dupe(u8, value);
            if (self.current_command.body) |*body| {
                body.deinit(self.allocator);
            }
            self.current_command.body = .{ .raw = payload };
        }
        self.state = .normal;
        self.editing_field = null;
    }

    fn loadTemplate(self: *App, idx: usize) !void {
        if (idx >= self.templates.items.len) return;
        const cloned = try cloneCommand(self.allocator, &self.id_generator, &self.templates.items[idx].command);
        self.current_command.deinit();
        self.current_command = cloned;
    }

    fn loadHistoryEntry(self: *App, runtime: *Runtime, idx: usize) !void {
        if (idx >= self.history.items.len) return;
        const cloned = try cloneCommand(self.allocator, &self.id_generator, &self.history.items[idx]);
        self.current_command.deinit();
        self.current_command = cloned;
        if (idx < self.history_results.items.len) {
            if (self.history_results.items[idx]) |*result| {
                const restored = try cloneExecutionResult(self.allocator, result);
                runtime.setResult(restored);
            } else {
                runtime.setResult(null);
            }
        } else {
            runtime.setResult(null);
        }
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

fn cloneExecutionResult(
    allocator: std.mem.Allocator,
    source: *const execution.executor.ExecutionResult,
) !execution.executor.ExecutionResult {
    return .{
        .command = try allocator.dupe(u8, source.command),
        .exit_code = source.exit_code,
        .stdout = try allocator.dupe(u8, source.stdout),
        .stderr = try allocator.dupe(u8, source.stderr),
        .duration_ns = source.duration_ns,
        .error_message = if (source.error_message) |msg| try allocator.dupe(u8, msg) else null,
    };
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
