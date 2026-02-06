const std = @import("std");
const zithril = @import("zithril");
const boxed = @import("boxed.zig");

pub const Options = struct {
    title: []const u8,
    right_label: []const u8 = "",
    border_style: zithril.Style,
    title_style: zithril.Style,
    right_style: zithril.Style,
    max_width: u16 = 84,
    max_height: u16 = 24,
    min_width: u16 = 24,
    min_height: u16 = 8,
    margin: u16 = 2,
};

pub fn begin(allocator: std.mem.Allocator, area: zithril.Rect, buf: *zithril.Buffer, options: Options) ?zithril.Rect {
    if (area.width == 0 or area.height == 0) return null;
    const margin = options.margin;
    const modal_w: u16 = if (area.width > margin * 2 + 2)
        @min(area.width - margin * 2, options.max_width)
    else
        area.width;
    const modal_h: u16 = if (area.height > margin * 2 + 2)
        @min(area.height - margin * 2, options.max_height)
    else
        area.height;
    if (modal_w < options.min_width or modal_h < options.min_height) return null;

    const x_off: u16 = if (area.width > modal_w) (area.width - modal_w) / 2 else 0;
    const y_off: u16 = if (area.height > modal_h) (area.height - modal_h) / 2 else 0;

    const modal_area = zithril.Rect.init(
        area.x + x_off,
        area.y + y_off,
        modal_w,
        modal_h,
    );

    // Clear the modal background
    buf.fill(modal_area, zithril.Cell.styled(' ', zithril.Style.empty));

    const inner = boxed.begin(
        allocator,
        modal_area,
        buf,
        options.title,
        options.right_label,
        options.border_style,
        options.title_style,
        options.right_style,
    );
    if (inner.width == 0 or inner.height == 0) return null;
    return inner;
}
