const std = @import("std");
const core = @import("zvrl_core");
const vaxis = @import("vaxis");
const execution = @import("zvrl_execution");

pub const App = struct {
    allocator: std.mem.Allocator,
    executor: execution.executor.CommandExecutor,
    active_job: ?execution.executor.ExecutionJob = null,
    last_result: ?execution.executor.ExecutionResult = null,
    stream_stdout: std.ArrayList(u8),
    stream_stderr: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !App {
        return .{
            .allocator = allocator,
            .executor = execution.executor.CommandExecutor.init(allocator),
            .stream_stdout = try std.ArrayList(u8).initCapacity(allocator, 0),
            .stream_stderr = try std.ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *App) void {
        if (self.active_job) |*job| {
            job.deinit();
        }
        if (self.last_result) |*result| {
            result.deinit(self.allocator);
        }
        self.stream_stdout.deinit(self.allocator);
        self.stream_stderr.deinit(self.allocator);
    }

    pub fn startExecution(self: *App, command: []const u8) !void {
        if (self.active_job != null) return error.ExecutionInProgress;
        self.clearStreamBuffers();
        self.clearLastResult();
        self.active_job = try self.executor.start(command);
    }

    pub fn tick(self: *App) !void {
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

    fn clearStreamBuffers(self: *App) void {
        self.stream_stdout.clearRetainingCapacity();
        self.stream_stderr.clearRetainingCapacity();
    }

    fn clearLastResult(self: *App) void {
        if (self.last_result) |*result| {
            result.deinit(self.allocator);
            self.last_result = null;
        }
    }

    fn handleOutput(ctx: ?*anyopaque, stream: execution.executor.Stream, chunk: []const u8) void {
        const app: *App = @ptrCast(@alignCast(ctx.?));
        switch (stream) {
            .stdout => _ = app.stream_stdout.appendSlice(app.allocator, chunk) catch {},
            .stderr => _ = app.stream_stderr.appendSlice(app.allocator, chunk) catch {},
        }
    }
};

/// Temporary bootstrap entry point for the Zig rewrite.
pub fn run(allocator: std.mem.Allocator) !void {
    const summary = try core.describe(allocator);
    defer allocator.free(summary);

    var app = try App.init(allocator);
    defer app.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print(
        "TVRL Zig workspace initialized.\n{s}\n",
        .{summary},
    );

    // Placeholder use to ensure the libvaxis dependency is wired up.
    _ = vaxis;
}
