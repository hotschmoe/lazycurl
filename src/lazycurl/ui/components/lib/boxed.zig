const zithril = @import("zithril");

fn renderBorder(area: zithril.Rect, buf: *zithril.Buffer, style: zithril.Style) void {
    if (area.width <= 2 or area.height <= 2) return;

    const block = zithril.Block{
        .border = .rounded,
        .border_style = style,
    };
    block.render(area, buf);
}

fn labelWidth(text: []const u8, padded: bool) u16 {
    if (text.len == 0) return 0;
    const base: u16 = @intCast(text.len);
    return if (padded) base + 2 else base;
}

fn drawLabel(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    col: u16,
    text: []const u8,
    text_style: zithril.Style,
    border_style: zithril.Style,
    padded: bool,
) void {
    if (text.len == 0 or col >= area.width) return;
    const x = area.x + col;
    const y = area.y;
    if (padded) {
        buf.setString(x, y, " ", border_style);
        buf.setString(x + 1, y, text, text_style);
        buf.setString(x + 1 + @as(u16, @intCast(text.len)), y, " ", border_style);
        return;
    }
    buf.setString(x, y, text, text_style);
}

fn drawBottomLabel(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    col: u16,
    text: []const u8,
    text_style: zithril.Style,
    border_style: zithril.Style,
    padded: bool,
) void {
    if (text.len == 0 or col >= area.width or area.height == 0) return;
    const x = area.x + col;
    const y = area.y + area.height - 1;
    if (padded) {
        buf.setString(x, y, " ", border_style);
        buf.setString(x + 1, y, text, text_style);
        buf.setString(x + 1 + @as(u16, @intCast(text.len)), y, " ", border_style);
        return;
    }
    buf.setString(x, y, text, text_style);
}

pub const RightLabel = struct {
    text: []const u8,
    style: zithril.Style,
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

fn fitRightLabels(area_width: u16, left_width: u16, labels: []const RightLabel) []const RightLabel {
    var count = labels.len;
    while (count > 0) : (count -= 1) {
        const subset = labels[0..count];
        const raw_width = rightLabelsWidth(subset);
        const padded_right = raw_width + 4 < area_width;
        var right_width: usize = raw_width;
        if (padded_right) right_width += 2;
        if (right_width == 0) continue;
        const win_width: usize = area_width;
        if (right_width + 1 >= win_width) continue;
        const right_col: u16 = @intCast(@max(@as(usize, 1), win_width - 1 - right_width));
        if (right_col > 1 + left_width) return subset;
    }
    return &[_]RightLabel{};
}

fn drawRightLabels(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    left_width: u16,
    labels: []const RightLabel,
    border_style: zithril.Style,
) void {
    if (labels.len == 0) return;
    const raw_width = rightLabelsWidth(labels);
    const padded_right = raw_width + 4 < area.width;
    var right_width: usize = raw_width;
    if (padded_right) right_width += 2;
    if (right_width == 0) return;
    const win_width: usize = area.width;
    if (right_width + 1 >= win_width) return;
    const right_col: u16 = @intCast(@max(@as(usize, 1), win_width - 1 - right_width));
    if (right_col <= 1 + left_width) return;

    var x = area.x + right_col;
    const y = area.y;
    if (padded_right) {
        buf.setString(x, y, " ", border_style);
        x += 1;
    }
    for (labels, 0..) |label, idx| {
        if (idx > 0) {
            buf.setString(x, y, " | ", border_style);
            x += 3;
        }
        buf.setString(x, y, label.text, label.style);
        x += @intCast(label.text.len);
    }
    if (padded_right) {
        buf.setString(x, y, " ", border_style);
    }
}

pub fn begin(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    title: []const u8,
    right_label: []const u8,
    border_style: zithril.Style,
    title_style: zithril.Style,
    right_style: zithril.Style,
) zithril.Rect {
    if (area.width == 0 or area.height == 0) return area;

    renderBorder(area, buf, border_style);

    const padded_left = title.len + 2 + 2 < area.width;
    const left_width = labelWidth(title, padded_left);
    if (left_width > 0 and 1 + left_width < area.width) {
        drawLabel(area, buf, 1, title, title_style, border_style, padded_left);
    }

    const padded_right = right_label.len + 2 + 2 < area.width;
    const right_width = labelWidth(right_label, padded_right);
    if (right_width > 0) {
        const right_col: u16 = @intCast(@max(@as(usize, 1), area.width - 1 - right_width));
        if (right_col > 1 + left_width) {
            drawLabel(area, buf, right_col, right_label, right_style, border_style, padded_right);
        }
    }

    if (area.width <= 2 or area.height <= 2) return area;
    return zithril.Rect.init(
        area.x + 1,
        area.y + 1,
        area.width - 2,
        area.height - 2,
    );
}

pub fn beginWithBottomLabel(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    title: []const u8,
    right_label: []const u8,
    bottom_left_label: []const u8,
    border_style: zithril.Style,
    title_style: zithril.Style,
    right_style: zithril.Style,
    bottom_style: zithril.Style,
) zithril.Rect {
    if (area.width == 0 or area.height == 0) return area;

    renderBorder(area, buf, border_style);

    const padded_left = title.len + 2 + 2 < area.width;
    const left_width = labelWidth(title, padded_left);
    if (left_width > 0 and 1 + left_width < area.width) {
        drawLabel(area, buf, 1, title, title_style, border_style, padded_left);
    }

    const padded_right = right_label.len + 2 + 2 < area.width;
    const right_width = labelWidth(right_label, padded_right);
    if (right_width > 0) {
        const right_col: u16 = @intCast(@max(@as(usize, 1), area.width - 1 - right_width));
        if (right_col > 1 + left_width) {
            drawLabel(area, buf, right_col, right_label, right_style, border_style, padded_right);
        }
    }

    const padded_bottom = bottom_left_label.len + 2 + 2 < area.width;
    const bottom_width = labelWidth(bottom_left_label, padded_bottom);
    if (bottom_width > 0 and 1 + bottom_width < area.width) {
        drawBottomLabel(area, buf, 1, bottom_left_label, bottom_style, border_style, padded_bottom);
    }

    if (area.width <= 2 or area.height <= 2) return area;
    return zithril.Rect.init(
        area.x + 1,
        area.y + 1,
        area.width - 2,
        area.height - 2,
    );
}

pub fn beginWithBottomLabelRightLabels(
    area: zithril.Rect,
    buf: *zithril.Buffer,
    title: []const u8,
    right_labels: []const RightLabel,
    bottom_left_label: []const u8,
    border_style: zithril.Style,
    title_style: zithril.Style,
    bottom_style: zithril.Style,
) zithril.Rect {
    if (area.width == 0 or area.height == 0) return area;

    renderBorder(area, buf, border_style);

    const padded_left = title.len + 2 + 2 < area.width;
    const left_width = labelWidth(title, padded_left);
    if (left_width > 0 and 1 + left_width < area.width) {
        drawLabel(area, buf, 1, title, title_style, border_style, padded_left);
    }

    const fitted = fitRightLabels(area.width, left_width, right_labels);
    drawRightLabels(area, buf, left_width, fitted, border_style);

    const padded_bottom = bottom_left_label.len + 2 + 2 < area.width;
    const bottom_width = labelWidth(bottom_left_label, padded_bottom);
    if (bottom_width > 0 and 1 + bottom_width < area.width) {
        drawBottomLabel(area, buf, 1, bottom_left_label, bottom_style, border_style, padded_bottom);
    }

    if (area.width <= 2 or area.height <= 2) return area;
    return zithril.Rect.init(
        area.x + 1,
        area.y + 1,
        area.width - 2,
        area.height - 2,
    );
}
