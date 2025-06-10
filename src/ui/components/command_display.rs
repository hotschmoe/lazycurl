use crate::app::App;
use crate::command::builder::CommandBuilder;
use crate::ui::theme::Theme;
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Paragraph, Wrap};
use ratatui::Frame;

/// Command display component
pub struct CommandDisplay<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
}

impl<'a> CommandDisplay<'a> {
    /// Create a new command display component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        Self { app, theme }
    }

    /// Render the command display
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        // Generate the curl command
        let environment = self.app.environments.get(&self.app.current_environment).unwrap();
        let command = CommandBuilder::build(&self.app.current_command, environment);

        // Create text with syntax highlighting
        let text = self.highlight_command(&command);

        // Create block
        let block = Block::default()
            .title("Generated Command")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        // Create paragraph
        let paragraph = Paragraph::new(text)
            .block(block)
            .wrap(Wrap { trim: true });

        // Render paragraph
        frame.render_widget(paragraph, area);
    }

    /// Highlight the curl command with syntax highlighting
    fn highlight_command(&self, command: &str) -> Text<'static> {
        let mut spans = Vec::new();
        let mut in_quotes = false;
        let mut in_option = false;
        let mut current_word = String::new();

        // Process each character
        for c in command.chars() {
            match c {
                ' ' => {
                    // End of word
                    if !current_word.is_empty() {
                        let style = if in_quotes {
                            self.theme.text_style()
                        } else if in_option {
                            Style::default().fg(self.theme.primary)
                        } else if current_word == "curl" {
                            Style::default().fg(self.theme.accent)
                        } else {
                            self.theme.text_style()
                        };
                        spans.push(Span::styled(current_word.clone(), style));
                        current_word.clear();
                    }
                    spans.push(Span::raw(" "));
                    in_option = false;
                }
                '"' | '\'' => {
                    // Quote
                    if !current_word.is_empty() {
                        let style = if in_quotes {
                            self.theme.text_style()
                        } else if in_option {
                            Style::default().fg(self.theme.primary)
                        } else {
                            self.theme.text_style()
                        };
                        spans.push(Span::styled(current_word.clone(), style));
                        current_word.clear();
                    }
                    spans.push(Span::styled(
                        c.to_string(),
                        Style::default()
                            .fg(self.theme.secondary)
                            .add_modifier(Modifier::BOLD),
                    ));
                    in_quotes = !in_quotes;
                }
                '-' => {
                    // Option
                    if !current_word.is_empty() {
                        let style = if in_quotes {
                            self.theme.text_style()
                        } else if in_option {
                            Style::default().fg(self.theme.primary)
                        } else {
                            self.theme.text_style()
                        };
                        spans.push(Span::styled(current_word.clone(), style));
                        current_word.clear();
                    }
                    current_word.push(c);
                    in_option = true;
                }
                '\\' => {
                    // Line continuation
                    if !current_word.is_empty() {
                        let style = if in_quotes {
                            self.theme.text_style()
                        } else if in_option {
                            Style::default().fg(self.theme.primary)
                        } else {
                            self.theme.text_style()
                        };
                        spans.push(Span::styled(current_word.clone(), style));
                        current_word.clear();
                    }
                    spans.push(Span::styled(
                        c.to_string(),
                        Style::default().fg(self.theme.secondary),
                    ));
                }
                '\n' => {
                    // Newline
                    if !current_word.is_empty() {
                        let style = if in_quotes {
                            self.theme.text_style()
                        } else if in_option {
                            Style::default().fg(self.theme.primary)
                        } else {
                            self.theme.text_style()
                        };
                        spans.push(Span::styled(current_word.clone(), style));
                        current_word.clear();
                    }
                    spans.push(Span::raw("\n"));
                }
                _ => {
                    // Other character
                    current_word.push(c);
                }
            }
        }

        // Add the last word
        if !current_word.is_empty() {
            let style = if in_quotes {
                self.theme.text_style()
            } else if in_option {
                Style::default().fg(self.theme.primary)
            } else if current_word == "curl" {
                Style::default().fg(self.theme.accent)
            } else {
                self.theme.text_style()
            };
            spans.push(Span::styled(current_word, style));
        }

        // Create text
        Text::from(Line::from(spans))
    }
}