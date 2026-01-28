const std = @import("std");
const core = @import("lazycurl_core");
const vaxis = @import("vaxis");
const execution = @import("lazycurl_execution");
const persistence = @import("lazycurl_persistence");
const command_builder = @import("lazycurl_command");
const text_input = @import("lazycurl_text_input");

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

    pub fn outputBody(self: *Runtime) []const u8 {
        if (self.active_job != null) return self.stream_stdout.items;
        if (self.last_result) |result| return result.stdout;
        return "";
    }

    pub fn outputError(self: *Runtime) []const u8 {
        if (self.active_job != null) return self.stream_stderr.items;
        if (self.last_result) |result| return result.stderr;
        return "";
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
    importing,
    exiting,
};

pub const ImportSource = enum {
    paste,
    file,
    url,
};

pub const ImportFocus = enum {
    source,
    input,
    folder,
    actions,
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
    template_name,
    template_folder,
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

pub const BodyEditMode = enum {
    insert,
    normal,
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
    selected_template_row: ?usize = null,
    selected_environment: ?usize = null,
    selected_history: ?usize = null,
    method_dropdown_index: usize = 0,
    cursor_visible: bool = true,
    cursor_blink_counter: u8 = 0,
    edit_input: text_input.TextInput,
    body_input: text_input.TextInput,
    editing_template_index: ?usize = null,
    new_folder_active: bool = false,
    left_panel: ?LeftPanel = null,
    templates_expanded: bool = true,
    environments_expanded: bool = true,
    history_expanded: bool = true,
    templates_scroll: usize = 0,
    environments_scroll: usize = 0,
    history_scroll: usize = 0,
    output_scroll: usize = 0,
    output_total_lines: usize = 0,
    output_view_height: u16 = 0,
    output_follow: bool = false,
    output_rect: ?PanelRect = null,
    output_copy_rect: ?PanelRect = null,
    output_copy_until_ms: i64 = 0,
    body_mode: BodyEditMode = .insert,
    import_source: ImportSource = .paste,
    import_focus: ImportFocus = .input,
    import_action_index: usize = 0,
    import_folder_index: usize = 0,
    import_spec_scroll: usize = 0,
    import_spec_input: text_input.TextInput,
    import_path_input: text_input.TextInput,
    import_url_input: text_input.TextInput,
    import_new_folder_input: text_input.TextInput,
    import_error: ?[]u8 = null,
    header_new_pending: bool = false,
    header_new_index: ?usize = null,
    header_prev_selection: ?usize = null,
};

pub const LeftPanel = enum {
    templates,
    environments,
    history,
};

pub const TemplateRowKind = enum {
    folder,
    template,
};

pub const TemplateRow = struct {
    kind: TemplateRowKind,
    category: []const u8,
    template_index: ?usize = null,
    collapsed: bool = false,
};

const DeletedTemplate = struct {
    template: core.models.template.CommandTemplate,
    index: usize,
};

const DeletedFolder = struct {
    name: []u8,
    index: usize,
    template_ids: []u64,
};

const UndoEntry = union(enum) {
    template: DeletedTemplate,
    folder: DeletedFolder,

    fn deinit(self: *UndoEntry, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .template => |*item| {
                item.template.deinit();
            },
            .folder => |*item| {
                allocator.free(item.name);
                allocator.free(item.template_ids);
            },
        }
    }
};

pub const PanelRect = struct {
    x: i17,
    y: i17,
    width: u16,
    height: u16,

    pub fn contains(self: PanelRect, col: i16, row: i16) bool {
        if (col < 0 or row < 0) return false;
        const c: i17 = @intCast(col);
        const r: i17 = @intCast(row);
        const right: i17 = self.x + @as(i17, @intCast(self.width));
        const bottom: i17 = self.y + @as(i17, @intCast(self.height));
        return c >= self.x and c < right and r >= self.y and r < bottom;
    }
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
    page_up,
    page_down,
    f2,
    f3,
    f4,
    f6,
    f10,
    paste: []const u8,
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
    templates_folders: std.ArrayList([]u8),
    templates_collapsed: std.StringHashMap(bool),
    environments: std.ArrayList(core.models.environment.Environment),
    history: std.ArrayList(core.models.command.CurlCommand),
    history_results: std.ArrayList(?execution.executor.ExecutionResult),
    pending_history_command: ?core.models.command.CurlCommand = null,
    current_environment_index: usize = 0,
    undo_stack: std.ArrayList(UndoEntry),

    pub fn init(allocator: std.mem.Allocator) !App {
        var generator = core.IdGenerator{};
        var current_command = try core.models.command.CurlCommand.init(allocator, &generator);
        try current_command.addOption(&generator, "-i", null);

        const template_store = try persistence.loadTemplates(allocator, &generator);
        const environments = try persistence.seedEnvironments(allocator, &generator);
        const history = try std.ArrayList(core.models.command.CurlCommand).initCapacity(allocator, 0);
        const history_results = try std.ArrayList(?execution.executor.ExecutionResult).initCapacity(allocator, 0);
        const templates_collapsed = std.StringHashMap(bool).init(allocator);
        const edit_input = try text_input.TextInput.init(allocator);
        const body_input = try text_input.TextInput.init(allocator);
        const import_spec_input = try text_input.TextInput.init(allocator);
        const import_path_input = try text_input.TextInput.init(allocator);
        const import_url_input = try text_input.TextInput.init(allocator);
        const import_new_folder_input = try text_input.TextInput.init(allocator);
        const undo_stack = try std.ArrayList(UndoEntry).initCapacity(allocator, 0);

        return .{
            .allocator = allocator,
            .id_generator = generator,
            .current_command = current_command,
            .templates = template_store.templates,
            .templates_folders = template_store.folders,
            .templates_collapsed = templates_collapsed,
            .environments = environments,
            .history = history,
            .history_results = history_results,
            .undo_stack = undo_stack,
            .ui = .{
                .edit_input = edit_input,
                .body_input = body_input,
                .import_spec_input = import_spec_input,
                .import_path_input = import_path_input,
                .import_url_input = import_url_input,
                .import_new_folder_input = import_new_folder_input,
            },
        };
    }

    pub fn deinit(self: *App) void {
        self.current_command.deinit();
        persistence.deinitTemplates(self.allocator, &self.templates);
        persistence.deinitTemplateFolders(self.allocator, &self.templates_folders);
        self.templates_collapsed.deinit();
        persistence.deinitEnvironments(self.allocator, &self.environments);
        persistence.deinitHistory(self.allocator, &self.history);
        for (self.history_results.items) |*maybe_result| {
            if (maybe_result.*) |*result| {
                result.deinit(self.allocator);
            }
        }
        self.history_results.deinit(self.allocator);
        for (self.undo_stack.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.undo_stack.deinit(self.allocator);
        if (self.pending_history_command) |*command| {
            command.deinit();
        }
        self.ui.edit_input.deinit();
        self.ui.body_input.deinit();
        self.ui.import_spec_input.deinit();
        self.ui.import_path_input.deinit();
        self.ui.import_url_input.deinit();
        self.ui.import_new_folder_input.deinit();
        if (self.ui.import_error) |message| {
            self.allocator.free(message);
            self.ui.import_error = null;
        }
    }

    pub fn handleKey(self: *App, input: KeyInput, runtime: *Runtime) !bool {
        switch (self.state) {
            .normal => return self.handleNormalKey(input, runtime),
            .editing => return self.handleEditingKey(input),
            .method_dropdown => return self.handleMethodDropdownKey(input),
            .importing => return self.handleImportKey(input),
            .exiting => return true,
        }
    }

    fn handleNormalKey(self: *App, input: KeyInput, runtime: *Runtime) !bool {
        if (input.code == .f2) {
            if (self.ui.left_panel != null and self.ui.left_panel.? == .templates) {
                if (try self.selectedTemplateRow()) |row| {
                    switch (row.kind) {
                        .template => if (row.template_index) |idx| {
                            self.state = .editing;
                            self.editing_field = .template_name;
                            self.ui.editing_template_index = idx;
                            try self.ui.edit_input.reset(self.templates.items[idx].name);
                        },
                        .folder => {
                            self.state = .editing;
                            self.editing_field = .template_folder;
                            self.ui.editing_template_index = null;
                            try self.ui.edit_input.reset(row.category);
                        },
                    }
                }
                return false;
            }
        }
        if (input.code == .f3) {
            if (self.ui.left_panel != null and self.ui.left_panel.? == .templates) {
                try self.saveTemplateFromCurrent();
                return false;
            }
        }
        if (input.code == .f4) {
            if (self.ui.left_panel != null and self.ui.left_panel.? == .templates) {
                self.state = .editing;
                self.editing_field = .template_folder;
                self.ui.editing_template_index = null;
                self.ui.new_folder_active = true;
                try self.ui.edit_input.reset("New Folder");
                self.ui.selected_template_row = 0;
                return false;
            }
        }
        if (input.code == .delete) {
            if (self.ui.left_panel != null and self.ui.left_panel.? == .templates) {
                try self.deleteSelectedTemplateOrFolder();
                self.ensureTemplateSelection();
                return false;
            }
        }
        if (input.mods.ctrl) {
            switch (input.code) {
                .char => |ch| {
                    if (ch == 'x') {
                        self.state = .exiting;
                        return true;
                    }
                    if (ch == 'i') {
                        try self.openSwaggerImport();
                        return false;
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
                    if (ch == 'z') {
                        try self.undoDelete();
                        self.ensureTemplateSelection();
                        return false;
                    }
                    if (ch == 'd') {
                        if (self.ui.left_panel != null and self.ui.left_panel.? == .templates) {
                            try self.duplicateSelectedTemplate();
                            self.ensureTemplateSelection();
                            return false;
                        }
                    }
                },
                else => {},
            }
        }

        if (self.ui.active_tab == .headers) {
            switch (input.code) {
                .char => |ch| {
                    if (ch == ' ' and self.ui.left_panel == null) {
                        try self.toggleSelectedHeader();
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
            .page_up => {
                self.scrollOutputPage(-1);
                return false;
            },
            .page_down => {
                self.scrollOutputPage(1);
                return false;
            },
            .home => {
                self.scrollOutputToStart();
                return false;
            },
            .end => {
                self.scrollOutputToEnd();
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
                        .templates => if (try self.selectedTemplateRow()) |row| {
                            switch (row.kind) {
                                .folder => {
                                    try self.toggleTemplateFolder(row.category);
                                },
                                .template => if (row.template_index) |idx| {
                                    try self.loadTemplate(idx);
                                    self.clearLeftPanelFocus();
                                    self.ui.selected_field = .{ .url = .url };
                                },
                            }
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
        const field = self.editing_field orelse return false;
        if (field == .body) {
            return self.handleBodyEditingKey(input);
        }

        if (input.code == .escape) {
            if (field == .header_key or field == .header_value) {
                if (self.ui.header_new_pending) {
                    self.cancelNewHeader();
                    return false;
                }
            }
            self.state = .normal;
            self.editing_field = null;
            self.ui.editing_template_index = null;
            self.ui.new_folder_active = false;
            return false;
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

    fn handleImportKey(self: *App, input: KeyInput) !bool {
        if (input.code == .escape) {
            self.closeSwaggerImport();
            return false;
        }
        if (input.code == .tab) {
            self.importFocusNext();
            return false;
        }
        if (input.code == .back_tab) {
            self.importFocusPrev();
            return false;
        }
        if (input.mods.ctrl and input.code == .enter) {
            try self.tryImportSwagger();
            return false;
        }

        switch (self.ui.import_focus) {
            .source => {
                switch (input.code) {
                    .left => self.setImportSource(prevImportSource(self.ui.import_source)),
                    .right => self.setImportSource(nextImportSource(self.ui.import_source)),
                    .down => self.ui.import_focus = .input,
                    .up => self.ui.import_focus = .actions,
                    .char => |ch| {
                        if (ch == 'p') self.setImportSource(.paste);
                        if (ch == 'f') self.setImportSource(.file);
                        if (ch == 'u') self.setImportSource(.url);
                    },
                    else => {},
                }
                return false;
            },
            .input => {
                if (input.code == .up and self.ui.import_source != .paste) {
                    self.ui.import_focus = .source;
                    return false;
                }
                if (input.code == .down and self.ui.import_source != .paste) {
                    self.ui.import_focus = .folder;
                    return false;
                }
                if (self.ui.import_source == .file) {
                    return self.handleImportPathInput(input);
                }
                if (self.ui.import_source == .url) {
                    return self.handleImportUrlInput(input);
                }
                return self.handleImportSpecInput(input);
            },
            .folder => {
                if (self.isImportNewFolderSelected()) {
                    switch (input.code) {
                        .left => self.moveImportFolder(-1),
                        .right => self.moveImportFolder(1),
                        .up => self.ui.import_focus = .input,
                        .down => self.ui.import_focus = .actions,
                        .enter => self.importFocusNext(),
                        .paste => |text| try self.ui.import_new_folder_input.insertSlice(firstLine(text)),
                        .backspace => self.ui.import_new_folder_input.backspace(),
                        .delete => self.ui.import_new_folder_input.delete(),
                        .home => self.ui.import_new_folder_input.moveHome(),
                        .end => self.ui.import_new_folder_input.moveEnd(),
                        .char => |ch| {
                            if (!input.mods.ctrl) {
                                try self.ui.import_new_folder_input.insertByte(ch);
                            }
                        },
                        else => {},
                    }
                } else {
                    switch (input.code) {
                        .left => self.moveImportFolder(-1),
                        .right => self.moveImportFolder(1),
                        .up => self.ui.import_focus = .input,
                        .down => self.ui.import_focus = .actions,
                        .enter => self.importFocusNext(),
                        else => {},
                    }
                }
                return false;
            },
            .actions => {
                switch (input.code) {
                    .left => {
                        if (self.ui.import_action_index > 0) {
                            self.ui.import_action_index -= 1;
                        }
                    },
                    .right => {
                        if (self.ui.import_action_index < 1) {
                            self.ui.import_action_index += 1;
                        }
                    },
                    .up => self.ui.import_focus = .folder,
                    .down => self.ui.import_focus = .source,
                    .enter => {
                        if (self.ui.import_action_index == 0) {
                            try self.tryImportSwagger();
                        } else {
                            self.closeSwaggerImport();
                        }
                    },
                    else => {},
                }
                return false;
            },
        }
    }

    fn handleImportPathInput(self: *App, input: KeyInput) !bool {
        switch (input.code) {
            .enter => {
                try self.tryImportSwagger();
                return false;
            },
            .paste => |text| {
                try self.ui.import_path_input.insertSlice(firstLine(text));
            },
            .backspace => self.ui.import_path_input.backspace(),
            .delete => self.ui.import_path_input.delete(),
            .left => self.ui.import_path_input.moveLeft(),
            .right => self.ui.import_path_input.moveRight(),
            .home => self.ui.import_path_input.moveHome(),
            .end => self.ui.import_path_input.moveEnd(),
            .char => |ch| {
                if (!input.mods.ctrl) {
                    try self.ui.import_path_input.insertByte(ch);
                }
            },
            else => {},
        }
        return false;
    }

    fn handleImportUrlInput(self: *App, input: KeyInput) !bool {
        switch (input.code) {
            .enter => {
                try self.tryImportSwagger();
                return false;
            },
            .paste => |text| {
                try self.ui.import_url_input.insertSlice(firstLine(text));
            },
            .backspace => self.ui.import_url_input.backspace(),
            .delete => self.ui.import_url_input.delete(),
            .left => self.ui.import_url_input.moveLeft(),
            .right => self.ui.import_url_input.moveRight(),
            .home => self.ui.import_url_input.moveHome(),
            .end => self.ui.import_url_input.moveEnd(),
            .char => |ch| {
                if (!input.mods.ctrl) {
                    try self.ui.import_url_input.insertByte(ch);
                }
            },
            else => {},
        }
        return false;
    }

    fn handleImportSpecInput(self: *App, input: KeyInput) !bool {
        const cursor = self.ui.import_spec_input.cursorPosition();
        const total_lines = countLines(self.ui.import_spec_input.slice());
        switch (input.code) {
            .enter => try self.ui.import_spec_input.insertByte('\n'),
            .paste => |text| try self.ui.import_spec_input.insertSlice(text),
            .backspace => self.ui.import_spec_input.backspace(),
            .delete => self.ui.import_spec_input.delete(),
            .left => self.ui.import_spec_input.moveLeft(),
            .right => self.ui.import_spec_input.moveRight(),
            .up => {
                if (cursor.row == 0) {
                    self.ui.import_focus = .source;
                } else {
                    self.ui.import_spec_input.moveUp();
                }
            },
            .down => {
                if (cursor.row + 1 >= total_lines) {
                    self.ui.import_focus = .folder;
                } else {
                    self.ui.import_spec_input.moveDown();
                }
            },
            .home => self.ui.import_spec_input.moveLineHome(),
            .end => self.ui.import_spec_input.moveLineEnd(),
            .page_up => moveInputLines(&self.ui.import_spec_input, -10),
            .page_down => moveInputLines(&self.ui.import_spec_input, 10),
            .char => |ch| {
                if (!input.mods.ctrl) {
                    try self.ui.import_spec_input.insertByte(ch);
                }
            },
            else => {},
        }
        return false;
    }

    fn openSwaggerImport(self: *App) !void {
        self.state = .importing;
        self.editing_field = null;
        self.ui.import_focus = .input;
        self.ui.import_action_index = 0;
        self.ui.import_spec_scroll = 0;
        self.ui.import_new_folder_input.reset("") catch {};
        self.clearImportError();
        try self.syncImportFolderSelection();
    }

    fn closeSwaggerImport(self: *App) void {
        self.state = .normal;
        self.clearImportError();
    }

    fn setImportSource(self: *App, source: ImportSource) void {
        self.ui.import_source = source;
    }

    fn nextImportSource(source: ImportSource) ImportSource {
        return switch (source) {
            .paste => .file,
            .file => .url,
            .url => .paste,
        };
    }

    fn prevImportSource(source: ImportSource) ImportSource {
        return switch (source) {
            .paste => .url,
            .file => .paste,
            .url => .file,
        };
    }

    fn moveInputLines(input: *text_input.TextInput, delta: i32) void {
        const steps: usize = @intCast(@abs(delta));
        if (steps == 0) return;
        if (delta < 0) {
            for (0..steps) |_| input.moveUp();
        } else {
            for (0..steps) |_| input.moveDown();
        }
    }

    fn firstLine(text: []const u8) []const u8 {
        if (text.len == 0) return text;
        const cut = std.mem.indexOfAny(u8, text, "\r\n");
        const line = if (cut) |idx| text[0..idx] else text;
        return std.mem.trim(u8, line, " \t\r\n");
    }

    fn countLines(buffer: []const u8) usize {
        if (buffer.len == 0) return 1;
        var count: usize = 1;
        for (buffer) |ch| {
            if (ch == '\n') count += 1;
        }
        return count;
    }

    fn importFocusNext(self: *App) void {
        self.ui.import_focus = switch (self.ui.import_focus) {
            .source => .input,
            .input => .folder,
            .folder => .actions,
            .actions => .source,
        };
    }

    fn importFocusPrev(self: *App) void {
        self.ui.import_focus = switch (self.ui.import_focus) {
            .source => .actions,
            .input => .source,
            .folder => .input,
            .actions => .folder,
        };
    }

    fn moveImportFolder(self: *App, delta: i32) void {
        const count: usize = self.templates_folders.items.len + 2;
        if (count == 0) {
            self.ui.import_folder_index = 0;
            return;
        }
        const current: i32 = @intCast(self.ui.import_folder_index);
        var next = current + delta;
        if (next < 0) {
            next = @intCast(count - 1);
        } else if (next >= @as(i32, @intCast(count))) {
            next = 0;
        }
        self.ui.import_folder_index = @intCast(next);
    }

    fn syncImportFolderSelection(self: *App) !void {
        self.ui.import_folder_index = 0;
        if (try self.selectedTemplateRow()) |row| {
            if (row.kind == .folder) {
                self.setImportFolderByName(row.category);
            } else if (row.template_index != null) {
                self.setImportFolderByName(row.category);
            }
        }
    }

    fn setImportFolderByName(self: *App, name: []const u8) void {
        if (self.templates_folders.items.len == 0) {
            self.ui.import_folder_index = 0;
            return;
        }
        for (self.templates_folders.items, 0..) |folder, idx| {
            if (std.mem.eql(u8, folder, name)) {
                self.ui.import_folder_index = idx + 1;
                return;
            }
        }
        self.ui.import_folder_index = 0;
    }

    fn importSelectedCategory(self: *App) ?[]const u8 {
        if (self.ui.import_folder_index == 0) return null;
        const idx = self.ui.import_folder_index - 1;
        if (idx >= self.templates_folders.items.len) return null;
        return self.templates_folders.items[idx];
    }

    fn isImportNewFolderSelected(self: *App) bool {
        const new_index = self.templates_folders.items.len + 1;
        return self.ui.import_folder_index == new_index;
    }

    fn tryImportSwagger(self: *App) !void {
        self.clearImportError();
        var category = self.importSelectedCategory();
        if (self.isImportNewFolderSelected()) {
            const raw_name = std.mem.trim(u8, self.ui.import_new_folder_input.slice(), " \t\r\n");
            if (raw_name.len == 0) {
                try self.setImportError("New folder name required");
                return;
            }
            category = raw_name;
        }
        if (self.ui.import_source == .file) {
            const raw_path = std.mem.trim(u8, self.ui.import_path_input.slice(), " \t\r\n");
            if (raw_path.len == 0) {
                try self.setImportError("Path required");
                return;
            }
            const path = try self.expandHomePath(raw_path);
            defer self.allocator.free(path);
            const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
                try self.setImportErrorFmt("File error: {s}", .{@errorName(err)});
                return;
            };
            defer file.close();
            const data = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch |err| {
                try self.setImportErrorFmt("Read error: {s}", .{@errorName(err)});
                return;
            };
            defer self.allocator.free(data);
            try self.applySwaggerImport(data, category);
            return;
        }
        if (self.ui.import_source == .url) {
            const raw_url = std.mem.trim(u8, self.ui.import_url_input.slice(), " \t\r\n");
            if (raw_url.len == 0) {
                try self.setImportError("URL required");
                return;
            }
            if (!std.mem.startsWith(u8, raw_url, "http://") and !std.mem.startsWith(u8, raw_url, "https://")) {
                try self.setImportError("URL must start with http:// or https://");
                return;
            }
            const download = self.downloadSwaggerSpec(raw_url) catch |err| {
                try self.setImportErrorFmt("Download error: {s}", .{@errorName(err)});
                return;
            };
            defer self.allocator.free(download.body);
            if (download.status.class() != .success) {
                try self.setImportErrorFmt("Download error: HTTP {d}", .{@intFromEnum(download.status)});
                return;
            }
            if (download.body.len == 0) {
                try self.setImportError("Download error: Empty response");
                return;
            }
            try self.applySwaggerImport(download.body, category);
            return;
        }

        const raw_spec = self.ui.import_spec_input.slice();
        if (std.mem.trim(u8, raw_spec, " \t\r\n").len == 0) {
            try self.setImportError("Paste spec JSON first");
            return;
        }
        try self.applySwaggerImport(raw_spec, category);
    }

    fn applySwaggerImport(self: *App, json_text: []const u8, category: ?[]const u8) !void {
        var imported = core.swagger.importTemplatesFromJson(self.allocator, &self.id_generator, json_text, category) catch |err| {
            const err_name = @errorName(err);
            if (err == error.MissingPaths) {
                try self.setImportError("No paths found in spec");
            } else if (err == error.NoOperations) {
                try self.setImportError("No operations found in spec");
            } else if (std.mem.eql(u8, err_name, "SyntaxError") or std.mem.eql(u8, err_name, "UnexpectedEndOfInput") or
                std.mem.eql(u8, err_name, "InvalidNumber") or std.mem.eql(u8, err_name, "ValueTooLong") or
                std.mem.eql(u8, err_name, "UnexpectedToken") or std.mem.eql(u8, err_name, "InvalidCharacter"))
            {
                try self.setImportError("Invalid JSON");
            } else {
                try self.setImportErrorFmt("Import error: {s}", .{err_name});
            }
            return;
        };
        var success = false;
        defer {
            if (!success) {
                for (imported.items) |*template| template.deinit();
            }
            imported.deinit(self.allocator);
        }

        try self.templates.ensureUnusedCapacity(self.allocator, imported.items.len);
        for (imported.items) |template| {
            self.templates.appendAssumeCapacity(template);
        }
        success = true;

        if (category) |folder| {
            if (!self.hasTemplateFolder(folder)) {
                try self.templates_folders.append(self.allocator, try self.allocator.dupe(u8, folder));
            }
        }
        persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items) catch |err| {
            try self.setImportErrorFmt("Save error: {s}", .{@errorName(err)});
            return;
        };
        self.ui.import_spec_input.reset("") catch {};
        self.ui.import_path_input.reset("") catch {};
        self.ui.import_url_input.reset("") catch {};
        self.ui.import_new_folder_input.reset("") catch {};
        self.closeSwaggerImport();
        self.ui.templates_expanded = true;
        self.focusLeftPanel(.templates);
    }

    const DownloadResult = struct {
        status: std.http.Status,
        body: []u8,
    };

    fn downloadSwaggerSpec(self: *App, url: []const u8) !DownloadResult {
        var client: std.http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        var sink: std.Io.Writer.Allocating = .init(self.allocator);
        defer sink.deinit();

        const headers = [_]std.http.Header{
            .{ .name = "accept", .value = "application/json" },
            .{ .name = "user-agent", .value = "lazycurl" },
        };
        const result = try client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &sink.writer,
            .extra_headers = &headers,
        });
        const body = try sink.toOwnedSlice();
        return .{ .status = result.status, .body = body };
    }

    fn expandHomePath(self: *App, path: []const u8) ![]u8 {
        if (path.len >= 2 and path[0] == '~' and path[1] == '/') {
            const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch |err| {
                if (err == error.EnvironmentVariableNotFound) {
                    return try self.allocator.dupe(u8, path);
                }
                return err;
            };
            defer self.allocator.free(home);
            return std.fs.path.join(self.allocator, &.{ home, path[2..] });
        }
        return try self.allocator.dupe(u8, path);
    }

    fn setImportError(self: *App, message: []const u8) !void {
        self.clearImportError();
        self.ui.import_error = try self.allocator.dupe(u8, message);
    }

    fn setImportErrorFmt(self: *App, comptime fmt: []const u8, args: anytype) !void {
        self.clearImportError();
        self.ui.import_error = try std.fmt.allocPrint(self.allocator, fmt, args);
    }

    fn clearImportError(self: *App) void {
        if (self.ui.import_error) |message| {
            self.allocator.free(message);
            self.ui.import_error = null;
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
                switch (self.ui.selected_field) {
                    .headers => |idx| {
                        if (idx >= self.current_command.headers.items.len) {
                            try self.beginNewHeader();
                            return;
                        }
                        self.state = .editing;
                        self.editing_field = .header_value;
                        try self.ui.edit_input.reset(self.current_command.headers.items[idx].value);
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
                            self.ui.body_mode = .insert;
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
                self.ensureTemplateSelection();
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
            .templates => if (self.ui.selected_template_row) |idx| {
                if (idx > 0) {
                    self.ui.selected_template_row = idx - 1;
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
            .templates => if (self.ui.selected_template_row) |idx| {
                const row_count = self.templateRowCount() catch 0;
                if (idx + 1 < row_count) {
                    self.ui.selected_template_row = idx + 1;
                }
            },
            .environments => if (self.ui.selected_environment) |idx| {
                if (idx + 1 < self.environments.items.len) {
                    self.ui.selected_environment = idx + 1;
                } else if (self.ui.templates_expanded and self.templates.items.len > 0) {
                    self.focusLeftPanel(.templates);
                    self.ui.selected_template_row = 0;
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
        if (self.ui.selected_template_row) |idx| {
            if (idx > 0) self.ui.selected_template_row = idx - 1;
        }
    }

    fn navigateTemplateDown(self: *App) void {
        if (self.ui.selected_template_row) |idx| {
            const row_count = self.templateRowCount() catch 0;
            if (idx + 1 < row_count) self.ui.selected_template_row = idx + 1;
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
                if (idx + 1 <= self.current_command.headers.items.len) {
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

    pub fn updateOutputMetrics(self: *App, total_lines: usize, view_height: u16) void {
        self.ui.output_total_lines = total_lines;
        self.ui.output_view_height = view_height;
        const max_scroll = self.outputMaxScroll();
        if (self.ui.output_follow) {
            self.ui.output_scroll = max_scroll;
        } else if (self.ui.output_scroll > max_scroll) {
            self.ui.output_scroll = max_scroll;
        }
    }

    pub fn resetOutputScroll(self: *App) void {
        self.ui.output_scroll = 0;
        self.ui.output_follow = false;
    }

    pub fn scrollOutputLines(self: *App, delta: i32) void {
        const max_scroll = self.outputMaxScroll();
        var next: i64 = @intCast(self.ui.output_scroll);
        next += delta;
        if (next < 0) next = 0;
        if (next > @as(i64, @intCast(max_scroll))) next = @intCast(max_scroll);
        self.ui.output_scroll = @intCast(next);
        self.ui.output_follow = self.ui.output_scroll == max_scroll;
    }

    pub fn scrollOutputPage(self: *App, direction: i32) void {
        const view = if (self.ui.output_view_height > 1) self.ui.output_view_height - 1 else 1;
        var step: u16 = view / 3;
        if (step < 3) step = 3;
        if (step > view) step = view;
        const delta: i32 = direction * @as(i32, @intCast(step));
        self.scrollOutputLines(delta);
    }

    pub fn scrollOutputToStart(self: *App) void {
        self.ui.output_scroll = 0;
        self.ui.output_follow = false;
    }

    pub fn scrollOutputToEnd(self: *App) void {
        const max_scroll = self.outputMaxScroll();
        self.ui.output_scroll = max_scroll;
        self.ui.output_follow = true;
    }

    fn outputMaxScroll(self: *App) usize {
        const view: usize = self.ui.output_view_height;
        if (view == 0) return 0;
        return if (self.ui.output_total_lines > view)
            self.ui.output_total_lines - view
        else
            0;
    }

    pub fn markOutputCopied(self: *App) void {
        self.ui.output_copy_until_ms = std.time.milliTimestamp() + 2000;
    }

    fn handleSingleLineEditingKey(self: *App, input: KeyInput) !bool {
        switch (input.code) {
            .enter => {
                try self.commitSingleLineEdit();
                return false;
            },
            .paste => |text| {
                try self.ui.edit_input.insertSlice(firstLine(text));
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
                if (self.editing_field) |field| {
                    if (field == .header_key or field == .header_value) {
                        try self.switchHeaderEditField(.left);
                        return false;
                    }
                }
                self.ui.edit_input.moveLeft();
                return false;
            },
            .right => {
                if (self.editing_field) |field| {
                    if (field == .header_key or field == .header_value) {
                        try self.switchHeaderEditField(.right);
                        return false;
                    }
                }
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

        if (self.ui.body_mode == .normal) {
            switch (input.code) {
                .escape => {
                    try self.commitBodyEdit();
                    return false;
                },
                .left => self.ui.body_input.moveLeft(),
                .right => self.ui.body_input.moveRight(),
                .up => self.ui.body_input.moveUp(),
                .down => self.ui.body_input.moveDown(),
                .home => self.ui.body_input.moveLineHome(),
                .end => self.ui.body_input.moveLineEnd(),
                .char => |ch| {
                    if (input.mods.ctrl) return false;
                    switch (ch) {
                        'h' => self.ui.body_input.moveLeft(),
                        'j' => self.ui.body_input.moveDown(),
                        'k' => self.ui.body_input.moveUp(),
                        'l' => self.ui.body_input.moveRight(),
                        '0' => self.ui.body_input.moveLineHome(),
                        '$' => self.ui.body_input.moveLineEnd(),
                        'w' => self.ui.body_input.moveWordForward(),
                        'b' => self.ui.body_input.moveWordBackward(),
                        'x' => self.ui.body_input.delete(),
                        'i' => self.ui.body_mode = .insert,
                        'a' => {
                            self.ui.body_input.moveRight();
                            self.ui.body_mode = .insert;
                        },
                        'o' => {
                            const line_end = self.ui.body_input.currentLineEnd();
                            const buf = self.ui.body_input.slice();
                            if (line_end < buf.len and buf[line_end] == '\n') {
                                self.ui.body_input.setCursor(line_end + 1);
                            } else {
                                self.ui.body_input.setCursor(line_end);
                            }
                            try self.ui.body_input.insertByte('\n');
                            self.ui.body_mode = .insert;
                        },
                        'O' => {
                            const line_start = self.ui.body_input.currentLineStart();
                            self.ui.body_input.setCursor(line_start);
                            try self.ui.body_input.insertByte('\n');
                            self.ui.body_input.moveLeft();
                            self.ui.body_mode = .insert;
                        },
                        'G' => self.ui.body_input.moveEnd(),
                        else => {},
                    }
                    return false;
                },
                else => return false,
            }
            return false;
        }

        switch (input.code) {
            .escape => {
                self.ui.body_mode = .normal;
                return false;
            },
            .enter => {
                try self.ui.body_input.insertByte('\n');
                return false;
            },
            .paste => |text| {
                try self.ui.body_input.insertSlice(text);
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
                self.ui.body_input.moveLineHome();
                return false;
            },
            .end => {
                self.ui.body_input.moveLineEnd();
                return false;
            },
            .char => |ch| {
                if (input.mods.ctrl) return false;
                switch (ch) {
                    '"', '\'', '{', '[', '(' => {
                        const close = switch (ch) {
                            '"' => '"',
                            '\'' => '\'',
                            '{' => '}',
                            '[' => ']',
                            '(' => ')',
                            else => ch,
                        };
                        if (ch == '"' or ch == '\'') {
                            if (!self.ui.body_input.skipIfNext(ch)) {
                                try self.ui.body_input.insertPair(ch, close);
                            }
                        } else {
                            try self.ui.body_input.insertPair(ch, close);
                        }
                    },
                    '}', ']', ')' => {
                        if (!self.ui.body_input.skipIfNext(ch)) {
                            try self.ui.body_input.insertByte(ch);
                        }
                    },
                    else => try self.ui.body_input.insertByte(ch),
                }
                return false;
            },
            else => return false,
        }
    }

    fn commitSingleLineEdit(self: *App) !void {
        const value = self.ui.edit_input.slice();
        if (self.editing_field) |field| {
            if (field == .template_name) {
                if (self.ui.editing_template_index) |idx| {
                    if (idx < self.templates.items.len) {
                        var template = &self.templates.items[idx];
                        template.allocator.free(template.name);
                        template.name = try template.allocator.dupe(u8, value);
                        template.command.allocator.free(template.command.name);
                        template.command.name = try template.command.allocator.dupe(u8, value);
                        template.updated_at = core.nowTimestamp();
                        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
                    }
                }
                self.state = .normal;
                self.editing_field = null;
                self.ui.editing_template_index = null;
                return;
            }
            if (field == .template_folder) {
                const trimmed = std.mem.trim(u8, value, " \t\r\n");
                if (self.ui.new_folder_active) {
                    if (trimmed.len > 0 and !self.hasTemplateFolder(trimmed)) {
                        try self.templates_folders.append(self.allocator, try self.allocator.dupe(u8, trimmed));
                        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
                    }
                } else if (trimmed.len > 0) {
                    if (try self.selectedTemplateRow()) |row| {
                        if (row.kind == .folder and !std.mem.eql(u8, row.category, trimmed)) {
                            try self.renameTemplateFolder(row.category, trimmed);
                            try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
                        } else if (row.kind != .folder and !self.hasTemplateFolder(trimmed)) {
                            try self.templates_folders.append(self.allocator, try self.allocator.dupe(u8, trimmed));
                            try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
                        }
                    } else if (!self.hasTemplateFolder(trimmed)) {
                        try self.templates_folders.append(self.allocator, try self.allocator.dupe(u8, trimmed));
                        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
                    }
                }
                self.state = .normal;
                self.editing_field = null;
                self.ui.editing_template_index = null;
                self.ui.new_folder_active = false;
                return;
            }
        }

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
                    if (self.editing_field) |field| {
                        switch (field) {
                            .header_key => {
                                const trimmed = std.mem.trim(u8, value, " \t\r\n");
                                if (trimmed.len == 0) {
                                    if (self.ui.header_new_pending) {
                                        self.cancelNewHeader();
                                        return;
                                    }
                                    self.state = .normal;
                                    self.editing_field = null;
                                    return;
                                }
                                self.allocator.free(header.key);
                                header.key = try self.allocator.dupe(u8, trimmed);
                                self.editing_field = .header_value;
                                try self.ui.edit_input.reset(header.value);
                                return;
                            },
                            .header_value => {
                                self.allocator.free(header.value);
                                header.value = try self.allocator.dupe(u8, value);
                                if (self.ui.header_new_pending) {
                                    self.ui.header_new_pending = false;
                                    self.ui.header_new_index = null;
                                    self.ui.header_prev_selection = null;
                                }
                            },
                            else => {},
                        }
                    } else {
                        self.allocator.free(header.value);
                        header.value = try self.allocator.dupe(u8, value);
                    }
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

    fn templateCategory(template: core.models.template.CommandTemplate) []const u8 {
        return template.category orelse "Ungrouped";
    }

    pub fn buildTemplateRows(self: *App, allocator: std.mem.Allocator) !std.ArrayList(TemplateRow) {
        var categories = try std.ArrayList([]const u8).initCapacity(allocator, self.templates_folders.items.len + 4);
        defer categories.deinit(allocator);

        for (self.templates_folders.items) |folder| {
            try categories.append(allocator, folder);
        }
        for (self.templates.items) |template| {
            const category = templateCategory(template);
            var exists = false;
            for (categories.items) |existing| {
                if (std.mem.eql(u8, existing, category)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                try categories.append(allocator, category);
            }
        }

        var rows = try std.ArrayList(TemplateRow).initCapacity(allocator, self.templates.items.len + categories.items.len + 1);
        if (self.ui.new_folder_active) {
            const label = if (self.ui.edit_input.slice().len > 0) self.ui.edit_input.slice() else "New Folder";
            try rows.append(allocator, .{
                .kind = .folder,
                .category = label,
                .template_index = null,
                .collapsed = false,
            });
        }
        for (categories.items) |category| {
            const collapsed = self.templates_collapsed.get(category) orelse false;
            try rows.append(allocator, .{
                .kind = .folder,
                .category = category,
                .template_index = null,
                .collapsed = collapsed,
            });
            if (!collapsed) {
                for (self.templates.items, 0..) |template, idx| {
                    if (std.mem.eql(u8, templateCategory(template), category)) {
                        try rows.append(allocator, .{
                            .kind = .template,
                            .category = category,
                            .template_index = idx,
                            .collapsed = false,
                        });
                    }
                }
            }
        }
        return rows;
    }

    fn templateRowCount(self: *App) !usize {
        var rows = try self.buildTemplateRows(self.allocator);
        defer rows.deinit(self.allocator);
        return rows.items.len;
    }

    fn selectedTemplateRow(self: *App) !?TemplateRow {
        const row_index = self.ui.selected_template_row orelse return null;
        var rows = try self.buildTemplateRows(self.allocator);
        defer rows.deinit(self.allocator);
        if (row_index >= rows.items.len) return null;
        return rows.items[row_index];
    }

    fn selectedTemplateIndex(self: *App) !?usize {
        if (try self.selectedTemplateRow()) |row| {
            if (row.kind == .template) return row.template_index;
        }
        return null;
    }

    fn selectedTemplateCategory(self: *App) !?[]const u8 {
        if (try self.selectedTemplateRow()) |row| {
            return row.category;
        }
        return null;
    }

    fn toggleTemplateFolder(self: *App, category: []const u8) !void {
        const current = self.templates_collapsed.get(category) orelse false;
        if (current) {
            _ = self.templates_collapsed.remove(category);
        } else {
            try self.templates_collapsed.put(category, true);
        }
    }

    fn saveTemplateFromCurrent(self: *App) !void {
        var cloned = try cloneCommand(self.allocator, &self.id_generator, &self.current_command);
        errdefer cloned.deinit();
        const base_name = if (std.mem.eql(u8, cloned.name, "New Command")) "New Template" else cloned.name;
        var template = try core.models.template.CommandTemplate.init(self.allocator, &self.id_generator, base_name, cloned);
        if (try self.selectedTemplateCategory()) |category| {
            try template.setCategory(category);
        }
        if (!std.mem.eql(u8, template.command.name, template.name)) {
            template.command.allocator.free(template.command.name);
            template.command.name = try template.command.allocator.dupe(u8, template.name);
        }
        try self.templates.append(self.allocator, template);
        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
    }

    fn ensureTemplateSelection(self: *App) void {
        const row_count = self.templateRowCount() catch 0;
        if (row_count == 0) {
            self.ui.selected_template_row = null;
        } else if (self.ui.selected_template_row == null or self.ui.selected_template_row.? >= row_count) {
            self.ui.selected_template_row = 0;
        }
    }

    fn renameTemplateFolder(self: *App, from: []const u8, to: []const u8) !void {
        for (self.templates_folders.items) |*folder| {
            if (std.mem.eql(u8, folder.*, from)) {
                self.allocator.free(folder.*);
                folder.* = try self.allocator.dupe(u8, to);
                break;
            }
        }
        for (self.templates.items) |*template| {
            if (template.category) |category| {
                if (std.mem.eql(u8, category, from)) {
                    template.allocator.free(category);
                    template.category = try template.allocator.dupe(u8, to);
                    template.updated_at = core.nowTimestamp();
                }
            }
        }
        _ = self.templates_collapsed.remove(from);
    }

    fn deleteTemplateFolder(self: *App, name: []const u8) !usize {
        var idx: usize = 0;
        var removed_index: ?usize = null;
        while (idx < self.templates_folders.items.len) : (idx += 1) {
            if (std.mem.eql(u8, self.templates_folders.items[idx], name)) {
                const removed = self.templates_folders.orderedRemove(idx);
                self.allocator.free(removed);
                removed_index = idx;
                break;
            }
        }
        for (self.templates.items) |*template| {
            if (template.category) |category| {
                if (std.mem.eql(u8, category, name)) {
                    template.allocator.free(category);
                    template.category = null;
                    template.updated_at = core.nowTimestamp();
                }
            }
        }
        _ = self.templates_collapsed.remove(name);
        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
        return removed_index orelse 0;
    }

    fn deleteTemplate(self: *App, idx: usize) !core.models.template.CommandTemplate {
        if (idx >= self.templates.items.len) return error.InvalidTemplateIndex;
        return self.templates.orderedRemove(idx);
    }

    fn deleteSelectedTemplateOrFolder(self: *App) !void {
        if (try self.selectedTemplateRow()) |row| {
            switch (row.kind) {
                .template => if (row.template_index) |idx| {
                    try self.deleteTemplateWithUndo(idx);
                },
                .folder => {
                    try self.deleteFolderWithUndo(row.category);
                },
            }
        }
    }

    fn deleteTemplateWithUndo(self: *App, idx: usize) !void {
        var removed = try self.deleteTemplate(idx);
        errdefer removed.deinit();
        try self.pushUndo(.{ .template = .{ .template = removed, .index = idx } });
        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
    }

    fn deleteFolderWithUndo(self: *App, name: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        var ids = try std.ArrayList(u64).initCapacity(self.allocator, 0);
        defer ids.deinit(self.allocator);
        for (self.templates.items) |template| {
            if (template.category) |category| {
                if (std.mem.eql(u8, category, name)) {
                    try ids.append(self.allocator, template.id);
                }
            }
        }
        const id_slice = try ids.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(id_slice);

        const removed_index = try self.deleteTemplateFolder(name);
        try self.pushUndo(.{ .folder = .{ .name = name_copy, .index = removed_index, .template_ids = id_slice } });
    }

    fn undoDelete(self: *App) !void {
        if (self.undo_stack.items.len == 0) return;
        const entry = self.undo_stack.pop() orelse return;
        errdefer {
            var entry_mut = entry;
            entry_mut.deinit(self.allocator);
        }
        switch (entry) {
            .template => |item| {
                if (item.template.category) |category| {
                    if (!self.hasTemplateFolder(category)) {
                        try self.templates_folders.append(self.allocator, try self.allocator.dupe(u8, category));
                    }
                }
                const idx = @min(item.index, self.templates.items.len);
                try self.templates.insert(self.allocator, idx, item.template);
                try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
            },
            .folder => |item| {
                if (!self.hasTemplateFolder(item.name)) {
                    const idx = @min(item.index, self.templates_folders.items.len);
                    try self.templates_folders.insert(self.allocator, idx, try self.allocator.dupe(u8, item.name));
                }
                for (item.template_ids) |template_id| {
                    if (self.findTemplateIndexById(template_id)) |tidx| {
                        try self.templates.items[tidx].setCategory(item.name);
                    }
                }
                try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
                var entry_mut = entry;
                entry_mut.deinit(self.allocator);
            },
        }
    }

    fn findTemplateIndexById(self: *App, id: u64) ?usize {
        for (self.templates.items, 0..) |template, idx| {
            if (template.id == id) return idx;
        }
        return null;
    }

    fn pushUndo(self: *App, entry: UndoEntry) !void {
        const max_depth: usize = 10;
        if (self.undo_stack.items.len >= max_depth) {
            var oldest = self.undo_stack.orderedRemove(0);
            oldest.deinit(self.allocator);
        }
        try self.undo_stack.append(self.allocator, entry);
    }

    fn duplicateSelectedTemplate(self: *App) !void {
        const row = try self.selectedTemplateRow() orelse return;
        if (row.kind != .template) return;
        const idx = row.template_index orelse return;
        if (idx >= self.templates.items.len) return;
        const source = &self.templates.items[idx];

        const new_name = try self.makeTemplateCopyName(source.name);
        defer self.allocator.free(new_name);
        var cloned_command = try cloneCommand(self.allocator, &self.id_generator, &source.command);
        errdefer cloned_command.deinit();

        var new_template = try core.models.template.CommandTemplate.init(self.allocator, &self.id_generator, new_name, cloned_command);
        errdefer new_template.deinit();

        if (source.description) |desc| {
            try new_template.setDescription(desc);
        }
        if (source.category) |category| {
            try new_template.setCategory(category);
        }
        if (!std.mem.eql(u8, new_template.command.name, new_template.name)) {
            new_template.command.allocator.free(new_template.command.name);
            new_template.command.name = try new_template.command.allocator.dupe(u8, new_template.name);
        }

        const insert_idx = @min(idx + 1, self.templates.items.len);
        try self.templates.insert(self.allocator, insert_idx, new_template);
        try persistence.saveTemplates(self.allocator, self.templates.items, self.templates_folders.items);
    }

    fn makeTemplateCopyName(self: *App, base: []const u8) ![]u8 {
        var idx: usize = 1;
        while (true) : (idx += 1) {
            const candidate = if (idx == 1)
                try std.fmt.allocPrint(self.allocator, "{s} Copy", .{base})
            else
                try std.fmt.allocPrint(self.allocator, "{s} Copy {d}", .{ base, idx });
            if (!self.templateNameExists(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }
    }

    fn templateNameExists(self: *App, name: []const u8) bool {
        for (self.templates.items) |template| {
            if (std.mem.eql(u8, template.name, name)) return true;
        }
        return false;
    }

    fn toggleSelectedHeader(self: *App) !void {
        if (self.ui.left_panel != null) return;
        const selected = switch (self.ui.selected_field) {
            .headers => |idx| idx,
            else => return,
        };
        if (selected >= self.current_command.headers.items.len) return;
        var header = &self.current_command.headers.items[selected];
        header.enabled = !header.enabled;
    }

    fn appendHeader(self: *App, key: []const u8, value: []const u8, enabled: bool) !usize {
        const header = core.models.command.Header{
            .id = self.id_generator.nextId(),
            .key = try self.allocator.dupe(u8, key),
            .value = try self.allocator.dupe(u8, value),
            .enabled = enabled,
        };
        errdefer {
            self.allocator.free(header.key);
            self.allocator.free(header.value);
        }
        try self.current_command.headers.append(self.allocator, header);
        return self.current_command.headers.items.len - 1;
    }

    fn beginNewHeader(self: *App) !void {
        const prev = if (self.current_command.headers.items.len > 0)
            self.current_command.headers.items.len - 1
        else
            null;
        const new_idx = try self.appendHeader("", "", true);
        self.ui.selected_field = .{ .headers = new_idx };
        self.ui.header_new_pending = true;
        self.ui.header_new_index = new_idx;
        self.ui.header_prev_selection = prev;
        self.state = .editing;
        self.editing_field = .header_key;
        try self.ui.edit_input.reset("");
    }

    fn cancelNewHeader(self: *App) void {
        if (self.ui.header_new_index) |idx| {
            if (idx < self.current_command.headers.items.len) {
                var removed = self.current_command.headers.orderedRemove(idx);
                removed.deinit(self.allocator);
            }
        }
        if (self.ui.header_prev_selection) |idx| {
            self.ui.selected_field = .{ .headers = idx };
        }
        self.ui.header_new_pending = false;
        self.ui.header_new_index = null;
        self.ui.header_prev_selection = null;
        self.state = .normal;
        self.editing_field = null;
    }

    fn switchHeaderEditField(self: *App, direction: enum { left, right }) !void {
        const idx = switch (self.ui.selected_field) {
            .headers => |sel| sel,
            else => return,
        };
        if (idx >= self.current_command.headers.items.len) return;
        const header = &self.current_command.headers.items[idx];
        const value = self.ui.edit_input.slice();
        const field = self.editing_field orelse return;

        if (field == .header_key) {
            const trimmed = std.mem.trim(u8, value, " \t\r\n");
            if (trimmed.len == 0) {
                if (self.ui.header_new_pending) {
                    self.cancelNewHeader();
                }
                return;
            }
            self.allocator.free(header.key);
            header.key = try self.allocator.dupe(u8, trimmed);
            if (direction == .right) {
                self.editing_field = .header_value;
                try self.ui.edit_input.reset(header.value);
            }
            return;
        }

        if (field == .header_value) {
            self.allocator.free(header.value);
            header.value = try self.allocator.dupe(u8, value);
            if (self.ui.header_new_pending) {
                self.ui.header_new_pending = false;
                self.ui.header_new_index = null;
                self.ui.header_prev_selection = null;
            }
            if (direction == .left) {
                self.editing_field = .header_key;
                try self.ui.edit_input.reset(header.key);
            }
        }
    }

    fn hasTemplateFolder(self: *App, name: []const u8) bool {
        for (self.templates_folders.items) |folder| {
            if (std.mem.eql(u8, folder, name)) return true;
        }
        return false;
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
        "lazycurl Zig workspace initialized.\n{s}\n",
        .{summary},
    );

    // Placeholder use to ensure the libvaxis dependency is wired up.
    _ = vaxis;
}
