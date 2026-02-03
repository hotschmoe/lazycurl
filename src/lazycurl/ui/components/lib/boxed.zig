const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const EmptyWidget = struct {
    pub fn widget(self: *@This()) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = @This().typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        return .{
            .size = ctx.min,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &.{},
        };
    }
};

fn renderBorder(allocator: std.mem.Allocator, win: vaxis.Window, style: vaxis.Style) void {
    if (win.width <= 2 or win.height <= 2) return;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    vxfw.DrawContext.init(.unicode);

    const inner_w: u16 = win.width - 2;
    const inner_h: u16 = win.height - 2;
    var empty = EmptyWidget{};
    const sized = vxfw.SizedBox{
        .child = empty.widget(),
        .size = .{ .width = inner_w, .height = inner_h },
    };

    const border = vxfw.Border{
        .child = sized.widget(),
        .style = style,
        .labels = &.{},
    };

    const draw_ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = win.width, .height = win.height },
        .cell_size = .{ .width = 1, .height = 1 },
    };

    const surface = border.widget().draw(draw_ctx) catch return;
    surface.render(win, border.widget());
}

fn labelWidth(text: []const u8, padded: bool) u16 {
    if (text.len == 0) return 0;
    const base: u16 = @intCast(text.len);
    return if (padded) base + 2 else base;
}

fn drawLabel(
    win: vaxis.Window,
    col: u16,
    text: []const u8,
    text_style: vaxis.Style,
    border_style: vaxis.Style,
    padded: bool,
) void {
    if (text.len == 0 or col >= win.width) return;
    if (padded) {
        const segments = [_]vaxis.Segment{
            .{ .text = " ", .style = border_style },
            .{ .text = text, .style = text_style },
            .{ .text = " ", .style = border_style },
        };
        _ = win.print(segments[0..], .{ .row_offset = 0, .col_offset = col, .wrap = .none });
        return;
    }
    const segments = [_]vaxis.Segment{
        .{ .text = text, .style = text_style },
    };
    _ = win.print(segments[0..], .{ .row_offset = 0, .col_offset = col, .wrap = .none });
}

fn drawBottomLabel(
    win: vaxis.Window,
    col: u16,
    text: []const u8,
    text_style: vaxis.Style,
    border_style: vaxis.Style,
    padded: bool,
) void {
    if (text.len == 0 or col >= win.width or win.height == 0) return;
    const row: u16 = win.height - 1;
    if (padded) {
        const segments = [_]vaxis.Segment{
            .{ .text = " ", .style = border_style },
            .{ .text = text, .style = text_style },
            .{ .text = " ", .style = border_style },
        };
        _ = win.print(segments[0..], .{ .row_offset = row, .col_offset = col, .wrap = .none });
        return;
    }
    const segments = [_]vaxis.Segment{
        .{ .text = text, .style = text_style },
    };
    _ = win.print(segments[0..], .{ .row_offset = row, .col_offset = col, .wrap = .none });
}

pub const RightLabel = struct {
    text: []const u8,
    style: vaxis.Style,
};

fn rightLabelsWidth(labels: []const RightLabel) usize {
    if (labels.len == 0) return 0;
    var width: usize = 0;
    for (labels, 0..) |label, idx| {
        if (idx > 0) width += 3;
        width += label.text.len;
    }
    return width;
}

fn fitRightLabels(win: vaxis.Window, left_width: u16, labels: []const RightLabel) []const RightLabel {
    var count = labels.len;
    while (count > 0) : (count -= 1) {
        const subset = labels[0..count];
        const raw_width = rightLabelsWidth(subset);
        const padded_right = raw_width + 4 < win.width;
        var right_width: usize = raw_width;
        if (padded_right) right_width += 2;
        if (right_width == 0) continue;
        const win_width: usize = win.width;
        if (right_width + 1 >= win_width) continue;
        const right_col: u16 = @intCast(@max(@as(usize, 1), win_width - 1 - right_width));
        if (right_col > 1 + left_width) return subset;
    }
    return &[_]RightLabel{};
}

fn drawRightLabels(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    left_width: u16,
    labels: []const RightLabel,
    border_style: vaxis.Style,
) void {
    if (labels.len == 0) return;
    const raw_width = rightLabelsWidth(labels);
    const padded_right = raw_width + 4 < win.width;
    var right_width: usize = raw_width;
    if (padded_right) right_width += 2;
    if (right_width == 0) return;
    const win_width: usize = win.width;
    if (right_width + 1 >= win_width) return;
    const right_col: u16 = @intCast(@max(@as(usize, 1), win_width - 1 - right_width));
    if (right_col <= 1 + left_width) return;

    var segments = std.ArrayList(vaxis.Segment).empty;
    defer segments.deinit(allocator);
    if (padded_right) {
        _ = segments.append(allocator, .{ .text = " ", .style = border_style }) catch return;
    }
    for (labels, 0..) |label, idx| {
        if (idx > 0) {
            _ = segments.append(allocator, .{ .text = " | ", .style = border_style }) catch return;
        }
        _ = segments.append(allocator, .{ .text = label.text, .style = label.style }) catch return;
    }
    if (padded_right) {
        _ = segments.append(allocator, .{ .text = " ", .style = border_style }) catch return;
    }
    _ = win.print(segments.items, .{ .row_offset = 0, .col_offset = right_col, .wrap = .none });
}

pub fn begin(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    title: []const u8,
    right_label: []const u8,
    border_style: vaxis.Style,
    title_style: vaxis.Style,
    right_style: vaxis.Style,
) vaxis.Window {
    if (win.width == 0 or win.height == 0) return win;

    renderBorder(allocator, win, border_style);

    const padded_left = title.len + 2 + 2 < win.width;
    const left_width = labelWidth(title, padded_left);
    if (left_width > 0 and 1 + left_width < win.width) {
        drawLabel(win, 1, title, title_style, border_style, padded_left);
    }

    const padded_right = right_label.len + 2 + 2 < win.width;
    const right_width = labelWidth(right_label, padded_right);
    if (right_width > 0) {
        const right_col: u16 = @intCast(@max(@as(usize, 1), win.width - 1 - right_width));
        if (right_col > 1 + left_width) {
            drawLabel(win, right_col, right_label, right_style, border_style, padded_right);
        }
    }

    if (win.width <= 2 or win.height <= 2) return win;
    return win.child(.{
        .x_off = 1,
        .y_off = 1,
        .width = win.width - 2,
        .height = win.height - 2,
        .border = .{ .where = .none },
    });
}

pub fn beginWithBottomLabel(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    title: []const u8,
    right_label: []const u8,
    bottom_left_label: []const u8,
    border_style: vaxis.Style,
    title_style: vaxis.Style,
    right_style: vaxis.Style,
    bottom_style: vaxis.Style,
) vaxis.Window {
    if (win.width == 0 or win.height == 0) return win;

    renderBorder(allocator, win, border_style);

    const padded_left = title.len + 2 + 2 < win.width;
    const left_width = labelWidth(title, padded_left);
    if (left_width > 0 and 1 + left_width < win.width) {
        drawLabel(win, 1, title, title_style, border_style, padded_left);
    }

    const padded_right = right_label.len + 2 + 2 < win.width;
    const right_width = labelWidth(right_label, padded_right);
    if (right_width > 0) {
        const right_col: u16 = @intCast(@max(@as(usize, 1), win.width - 1 - right_width));
        if (right_col > 1 + left_width) {
            drawLabel(win, right_col, right_label, right_style, border_style, padded_right);
        }
    }

    const padded_bottom = bottom_left_label.len + 2 + 2 < win.width;
    const bottom_width = labelWidth(bottom_left_label, padded_bottom);
    if (bottom_width > 0 and 1 + bottom_width < win.width) {
        drawBottomLabel(win, 1, bottom_left_label, bottom_style, border_style, padded_bottom);
    }

    if (win.width <= 2 or win.height <= 2) return win;
    return win.child(.{
        .x_off = 1,
        .y_off = 1,
        .width = win.width - 2,
        .height = win.height - 2,
        .border = .{ .where = .none },
    });
}

pub fn beginWithBottomLabelRightLabels(
    allocator: std.mem.Allocator,
    win: vaxis.Window,
    title: []const u8,
    right_labels: []const RightLabel,
    bottom_left_label: []const u8,
    border_style: vaxis.Style,
    title_style: vaxis.Style,
    bottom_style: vaxis.Style,
) vaxis.Window {
    if (win.width == 0 or win.height == 0) return win;

    renderBorder(allocator, win, border_style);

    const padded_left = title.len + 2 + 2 < win.width;
    const left_width = labelWidth(title, padded_left);
    if (left_width > 0 and 1 + left_width < win.width) {
        drawLabel(win, 1, title, title_style, border_style, padded_left);
    }

    const fitted = fitRightLabels(win, left_width, right_labels);
    drawRightLabels(allocator, win, left_width, fitted, border_style);

    const padded_bottom = bottom_left_label.len + 2 + 2 < win.width;
    const bottom_width = labelWidth(bottom_left_label, padded_bottom);
    if (bottom_width > 0 and 1 + bottom_width < win.width) {
        drawBottomLabel(win, 1, bottom_left_label, bottom_style, border_style, padded_bottom);
    }

    if (win.width <= 2 or win.height <= 2) return win;
    return win.child(.{
        .x_off = 1,
        .y_off = 1,
        .width = win.width - 2,
        .height = win.height - 2,
        .border = .{ .where = .none },
    });
}
