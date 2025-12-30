const vaxis = @import("vaxis");

pub const Theme = struct {
    border: vaxis.Style = .{ .fg = .{ .index = 244 } },
    title: vaxis.Style = .{ .fg = .{ .index = 111 }, .bold = true },
    text: vaxis.Style = .{ .fg = .{ .index = 252 } },
    muted: vaxis.Style = .{ .fg = .{ .index = 245 } },
    accent: vaxis.Style = .{ .fg = .{ .index = 81 }, .bold = true },
    error_style: vaxis.Style = .{ .fg = .{ .index = 203 }, .bold = true },
    success: vaxis.Style = .{ .fg = .{ .index = 114 }, .bold = true },
};
