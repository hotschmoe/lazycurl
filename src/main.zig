const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("zvrl_app");
const ui = @import("zvrl_ui");

const Event = vaxis.Event;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) std.log.warn("memory leaked during shutdown", .{});
    }

    const allocator = gpa.allocator();

    var app = try app_mod.App.init(allocator);
    defer app.deinit();

    var runtime = try app_mod.Runtime.init(allocator);
    defer runtime.deinit();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{
        .system_clipboard_allocator = allocator,
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    if (!vx.state.in_band_resize) {
        try loop.init();
    }
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    defer vx.exitAltScreen(tty.writer()) catch {};

    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);
    try vx.setBracketedPaste(tty.writer(), true);
    defer vx.setBracketedPaste(tty.writer(), false) catch {};

    try vx.setMouseMode(tty.writer(), true);
    defer vx.setMouseMode(tty.writer(), false) catch {};

    const tick_ms: u64 = 33;
    var next_frame_ms: u64 = @intCast(std.time.milliTimestamp());

    var running = true;
    while (running) {
        const now_ms: u64 = @intCast(std.time.milliTimestamp());
        if (now_ms < next_frame_ms) {
            std.Thread.sleep((next_frame_ms - now_ms) * std.time.ns_per_ms);
        }
        next_frame_ms = @as(u64, @intCast(std.time.milliTimestamp())) + tick_ms;

        loop.queue.lock();
        while (loop.queue.drain()) |event| {
            handleEvent(allocator, &vx, tty.writer(), &app, &runtime, event, &running) catch {};
        }
        loop.queue.unlock();

        try runtime.tick();
        app.toggleCursor();
        try render(allocator, &vx, tty.writer(), &app, &runtime);
    }
}

fn handleEvent(
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,
    tty: *std.Io.Writer,
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
    event: Event,
    running: *bool,
) !void {
    switch (event) {
        .winsize => |winsize| {
            try vx.resize(allocator, tty, winsize);
            vx.queueRefresh();
        },
        .key_press => |key| {
            if (key.matchShortcut('x', .{ .ctrl = true })) {
                running.* = false;
                return;
            }

            if (key.matchShortcut('r', .{ .ctrl = true }) or key.codepoint == vaxis.Key.f5) {
                const command = try app.executeCommand();
                defer app.allocator.free(command);
                _ = runtime.startExecution(command) catch {};
            }

            if (toKeyInput(key)) |input| {
                const should_exit = try app.handleKey(input);
                if (should_exit) {
                running.* = false;
                }
            }
        },
        else => {},
    }
}

fn render(
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,
    tty: *std.Io.Writer,
    app: *app_mod.App,
    runtime: *app_mod.Runtime,
) !void {
    const win = vx.window();
    win.clear();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const frame_alloc = arena.allocator();
    try ui.render(frame_alloc, win, app, runtime);
    try vx.render(tty);
}

fn toKeyInput(key: vaxis.Key) ?app_mod.KeyInput {
    if (key.codepoint == vaxis.Key.tab) {
        return .{ .code = if (key.mods.shift) .back_tab else .tab, .mods = modsFromKey(key) };
    }
    if (key.codepoint == vaxis.Key.up) return .{ .code = .up, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.down) return .{ .code = .down, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.left) return .{ .code = .left, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.right) return .{ .code = .right, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.enter) return .{ .code = .enter, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.escape) return .{ .code = .escape, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.backspace) return .{ .code = .backspace, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.delete) return .{ .code = .delete, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.home) return .{ .code = .home, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.end) return .{ .code = .end, .mods = modsFromKey(key) };
    if (key.codepoint == vaxis.Key.f2) return .{ .code = .f2, .mods = modsFromKey(key) };

    const codepoint: u21 = if (key.mods.ctrl and key.base_layout_codepoint != null)
        key.base_layout_codepoint.?
    else
        key.codepoint;

    if (codepoint <= 0x7f) {
        const byte: u8 = @intCast(codepoint);
        if (std.ascii.isPrint(byte)) {
            return .{ .code = .{ .char = byte }, .mods = modsFromKey(key) };
        }
    }

    return null;
}

fn modsFromKey(key: vaxis.Key) app_mod.Modifiers {
    return .{
        .ctrl = key.mods.ctrl,
        .shift = key.mods.shift,
    };
}
