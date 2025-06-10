use crate::app::App;
use crate::ui::theme::Theme;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Paragraph, Wrap};
use ratatui::Frame;

/// Output panel component
pub struct OutputPanel<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
}

impl<'a> OutputPanel<'a> {
    /// Create a new output panel component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        Self { app, theme }
    }

    /// Render the output panel
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        // Create block
        let block = Block::default()
            .title("Output")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        // Create text
        let text = match &self.app.output {
            Some(output) => self.format_output(output),
            None => Text::from("No output"),
        };

        // Create paragraph
        let paragraph = Paragraph::new(text)
            .block(block)
            .wrap(Wrap { trim: false });

        // Render paragraph
        frame.render_widget(paragraph, area);
    }

    /// Format the output with syntax highlighting
    fn format_output<'b>(&self, output: &'b str) -> Text<'b> {
        let mut lines = Vec::new();
        let mut in_headers = true;

        for line in output.lines() {
            // Check if we're transitioning from headers to body
            if in_headers && line.is_empty() {
                in_headers = false;
                lines.push(Line::from(""));
                continue;
            }

            if in_headers {
                // Format header line
                if line.starts_with("HTTP/") {
                    // Status line
                    let parts: Vec<&str> = line.splitn(3, ' ').collect();
                    if parts.len() >= 3 {
                        let status_code = parts[1];
                        let status_style = match status_code.chars().next() {
                            Some('2') => self.theme.success_style(),
                            Some('3') => self.theme.warning_style(),
                            Some('4') | Some('5') => self.theme.error_style(),
                            _ => self.theme.text_style(),
                        };

                        lines.push(Line::from(vec![
                            Span::styled(parts[0], Style::default().fg(self.theme.primary)),
                            Span::raw(" "),
                            Span::styled(status_code, status_style),
                            Span::raw(" "),
                            Span::styled(parts[2], self.theme.text_style()),
                        ]));
                    } else {
                        lines.push(Line::from(Span::raw(line)));
                    }
                } else if let Some(colon_pos) = line.find(':') {
                    // Header line
                    let (key, value) = line.split_at(colon_pos + 1);
                    lines.push(Line::from(vec![
                        Span::styled(key, Style::default().fg(self.theme.secondary)),
                        Span::styled(value, self.theme.text_style()),
                    ]));
                } else {
                    // Unknown header line
                    lines.push(Line::from(Span::raw(line)));
                }
            } else {
                // Format body line
                if line.trim().starts_with('{') || line.trim().starts_with('[') {
                    // JSON content
                    lines.push(Line::from(Span::styled(line, self.theme.text_style())));
                } else if line.trim().starts_with('<') {
                    // XML/HTML content
                    lines.push(Line::from(Span::styled(line, self.theme.text_style())));
                } else {
                    // Plain text
                    lines.push(Line::from(Span::raw(line)));
                }
            }
        }

        Text::from(lines)
    }
}