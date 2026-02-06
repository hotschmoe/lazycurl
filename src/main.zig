const std = @import("std");
const zithril = @import("zithril");
const app_mod = @import("lazycurl_app");
const ui = @import("lazycurl_ui");

pub const panic = zithril.terminal_panic;

const State = struct {
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
    allocator: std.mem.Allocator,

    fn update(state: *State, event: zithril.Event) zithril.Action {
        switch (event) {
            .key => |key| {
                const allow_base = state.app.state == .normal;

                // Ctrl+X / F10: quit, Ctrl+R / F5: execute
                if (allow_base) {
                    switch (key.code) {
                        .char => |c| {
                            if (c == 'x' and key.modifiers.ctrl) return zithril.Action.quit_action;
                            if (c == 'r' and key.modifiers.ctrl) {
                                executeRequest(state);
                            }
                        },
                        .f => |n| {
                            if (n == 10) return zithril.Action.quit_action;
                            if (n == 5) {
                                executeRequest(state);
                            }
                        },
                        else => {},
                    }
                }

                if (toKeyInput(key)) |input| {
                    const should_exit = state.app.handleKey(input, state.runtime) catch false;
                    if (should_exit) {
                        return zithril.Action.quit_action;
                    }
                }
            },
            .mouse => |mouse| {
                handleMouse(state, mouse);
            },
            .tick => {
                state.runtime.tick() catch {};
                if (state.runtime.last_result != null and !state.runtime.last_result_handled) {
                    _ = state.app.addHistoryFromCurrent(state.runtime) catch {};
                    state.runtime.last_result_handled = true;
                }
                state.app.toggleCursor();
            },
            .resize => {},
            .command_result => {},
        }
        return zithril.Action.none_action;
    }

    fn view(state: *State, frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets)) void {
        const area = frame.size();
        var arena = std.heap.ArenaAllocator.init(state.allocator);
        defer arena.deinit();
        const frame_alloc = arena.allocator();
        ui.render(frame_alloc, area, frame.buffer, state.app, state.runtime) catch {};
    }

    fn executeRequest(state: *State) void {
        state.app.applyMethodDropdownSelection();
        const command = state.app.executeCommand() catch return;
        defer state.app.allocator.free(command);
        _ = state.app.prepareHistorySnapshot() catch {};
        state.app.clearOutputOverride();
        state.app.resetOutputScroll();
        state.runtime.startExecution(command) catch {
            state.app.clearPendingHistorySnapshot();
        };
    }

    fn handleMouse(state: *State, mouse: zithril.Mouse) void {
        if (state.app.ui.output_rect) |rect| {
            if (rect.contains(@intCast(mouse.x), @intCast(mouse.y))) {
                switch (mouse.kind) {
                    .scroll_up => state.app.scrollOutputLines(-3),
                    .scroll_down => state.app.scrollOutputLines(3),
                    .down => {
                        if (state.app.ui.output_copy_rect) |copy_rect| {
                            if (copy_rect.contains(@intCast(mouse.x), @intCast(mouse.y))) {
                                // TODO: clipboard support - zithril does not expose copyToSystemClipboard
                                const body = state.app.ui.output_override orelse state.runtime.outputBody();
                                if (body.len > 0) {
                                    state.app.markOutputCopied();
                                }
                            }
                        }
                        if (state.app.ui.output_format_rect) |format_rect| {
                            if (format_rect.contains(@intCast(mouse.x), @intCast(mouse.y))) {
                                state.app.formatOutputJson(state.runtime);
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        if (state.app.ui.command_copy_rect) |rect| {
            if (rect.contains(@intCast(mouse.x), @intCast(mouse.y))) {
                switch (mouse.kind) {
                    .down => {
                        // TODO: clipboard support
                    },
                    else => {},
                }
            }
        }
    }
};

fn toKeyInput(key: zithril.Key) ?app_mod.KeyInput {
    const code: app_mod.KeyCode = switch (key.code) {
        .char => |c| blk: {
            if (c > 0x7f) return null;
            const byte: u8 = @intCast(c);
            if (!std.ascii.isPrint(byte)) return null;
            break :blk .{ .char = byte };
        },
        .enter => .enter,
        .escape => .escape,
        .backspace => .backspace,
        .delete => .delete,
        .tab => if (key.modifiers.shift) .back_tab else .tab,
        .backtab => .back_tab,
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .home => .home,
        .end => .end,
        .page_up => .page_up,
        .page_down => .page_down,
        .f => |n| switch (n) {
            2 => .f2,
            3 => .f3,
            4 => .f4,
            6 => .f6,
            10 => .f10,
            else => return null,
        },
        else => return null,
    };
    return .{
        .code = code,
        .mods = .{
            .shift = key.modifiers.shift,
            .ctrl = key.modifiers.ctrl,
        },
    };
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) std.log.warn("memory leaked during shutdown", .{});
    }
    const allocator = gpa.allocator();

    var app = try app_mod.App.init(allocator);
    defer app.deinit();

    var runtime = try app_mod.Runtime.init(allocator);
    defer runtime.deinit();

    var state = State{
        .app = &app,
        .runtime = &runtime,
        .allocator = allocator,
    };

    var zapp = zithril.App(State).init(.{
        .state = &state,
        .update = State.update,
        .view = State.view,
        .tick_rate_ms = 33,
        .mouse_capture = true,
        .paste_bracket = true,
        .alternate_screen = true,
    });

    try zapp.run(allocator);
}
