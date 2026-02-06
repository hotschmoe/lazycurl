const zithril = @import("zithril");
const Style = zithril.Style;
const Color = zithril.Color;

pub const Theme = struct {
    border: Style = Style.init().fg(Color.from256(244)),
    title: Style = Style.init().fg(Color.from256(111)).bold(),
    text: Style = Style.init().fg(Color.from256(252)),
    muted: Style = Style.init().fg(Color.from256(245)),
    accent: Style = Style.init().fg(Color.from256(81)).bold(),
    error_style: Style = Style.init().fg(Color.from256(203)).bold(),
    success: Style = Style.init().fg(Color.from256(114)).bold(),
    warning: Style = Style.init().fg(Color.from256(178)).bold(),
};
