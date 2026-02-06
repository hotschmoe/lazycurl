const std = @import("std");
const vaxis = @import("vaxis");
const boxed = @import("boxed.zig");

pub const Options = struct {
    title: []const u8,
    right_label: []const u8 = "",
    border_style: vaxis.Style,
    title_style: vaxis.Style,
    right_style: vaxis.Style,
    max_width: u16 = 84,
    max_height: u16 = 24,
    min_width: u16 = 24,
    min_height: u16 = 8,
    margin: u16 = 2,
};

pub fn begin(allocator: std.mem.Allocator, win: vaxis.Window, options: Options) ?vaxis.Window {
    if (win.width == 0 or win.height == 0) return null;
    const margin = options.margin;
    const modal_w: u16 = if (win.width > margin * 2 + 2)
        @min(win.width - margin * 2, options.max_width)
    else
        win.width;
    const modal_h: u16 = if (win.height > margin * 2 + 2)
        @min(win.height - margin * 2, options.max_height)
    else
        win.height;
    if (modal_w < options.min_width or modal_h < options.min_height) return null;

    const x_off: u16 = if (win.width > modal_w) (win.width - modal_w) / 2 else 0;
    const y_off: u16 = if (win.height > modal_h) (win.height - modal_h) / 2 else 0;

    const modal = win.child(.{
        .x_off = x_off,
        .y_off = y_off,
        .width = modal_w,
        .height = modal_h,
        .border = .{ .where = .none },
    });

    const inner = boxed.begin(
        allocator,
        modal,
        options.title,
        options.right_label,
        options.border_style,
        options.title_style,
        options.right_style,
    );
    if (inner.width == 0 or inner.height == 0) return null;
    return inner;
}
