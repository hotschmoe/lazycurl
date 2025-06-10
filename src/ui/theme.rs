use ratatui::style::{Color, Modifier, Style};

/// UI theme
pub struct Theme {
    /// Primary color
    pub primary: Color,
    /// Secondary color
    pub secondary: Color,
    /// Accent color
    pub accent: Color,
    /// Background color
    pub background: Color,
    /// Foreground color
    pub foreground: Color,
    /// Error color
    pub error: Color,
    /// Warning color
    pub warning: Color,
    /// Success color
    pub success: Color,
}

impl Theme {
    /// Create a new theme with default colors
    pub fn new() -> Self {
        Self {
            primary: Color::Cyan,
            secondary: Color::Blue,
            accent: Color::Yellow,
            background: Color::Black,
            foreground: Color::White,
            error: Color::Red,
            warning: Color::Yellow,
            success: Color::Green,
        }
    }

    /// Create a dark theme
    pub fn dark() -> Self {
        Self::new()
    }

    /// Create a light theme
    pub fn light() -> Self {
        Self {
            primary: Color::Blue,
            secondary: Color::Cyan,
            accent: Color::Magenta,
            background: Color::White,
            foreground: Color::Black,
            error: Color::Red,
            warning: Color::Yellow,
            success: Color::Green,
        }
    }

    /// Get title style
    pub fn title_style(&self) -> Style {
        Style::default()
            .fg(self.primary)
            .add_modifier(Modifier::BOLD)
    }

    /// Get header style
    pub fn header_style(&self) -> Style {
        Style::default()
            .fg(self.secondary)
            .add_modifier(Modifier::BOLD)
    }

    /// Get text style
    pub fn text_style(&self) -> Style {
        Style::default().fg(self.foreground)
    }

    /// Get highlight style
    pub fn highlight_style(&self) -> Style {
        Style::default()
            .fg(self.background)
            .bg(self.primary)
            .add_modifier(Modifier::BOLD)
    }

    /// Get selected style
    pub fn selected_style(&self) -> Style {
        Style::default()
            .fg(self.primary)
            .add_modifier(Modifier::BOLD)
    }

    /// Get active style
    pub fn active_style(&self) -> Style {
        Style::default()
            .fg(self.accent)
            .add_modifier(Modifier::BOLD)
    }

    /// Get inactive style
    pub fn inactive_style(&self) -> Style {
        Style::default().fg(self.foreground)
    }

    /// Get error style
    pub fn error_style(&self) -> Style {
        Style::default().fg(self.error)
    }

    /// Get warning style
    pub fn warning_style(&self) -> Style {
        Style::default().fg(self.warning)
    }

    /// Get success style
    pub fn success_style(&self) -> Style {
        Style::default().fg(self.success)
    }

    /// Get border style
    pub fn border_style(&self) -> Style {
        Style::default().fg(self.secondary)
    }

    /// Get help style
    pub fn help_style(&self) -> Style {
        Style::default()
            .fg(self.secondary)
            .add_modifier(Modifier::ITALIC)
    }
}

impl Default for Theme {
    fn default() -> Self {
        Self::new()
    }
}