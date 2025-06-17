use crate::app::{App, AppState, Tab};
use crate::ui::theme::Theme;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

/// Status bar component that displays application state and available shortcuts
pub struct StatusBar<'a> {
    app: &'a App,
    theme: &'a Theme,
}

impl<'a> StatusBar<'a> {
    /// Create a new status bar
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        Self { app, theme }
    }

    /// Render the status bar
    pub fn render(&self, f: &mut Frame, area: Rect) {
        // Split the status bar into three sections: left, center, right
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(30), // Left: Application state
                Constraint::Percentage(40), // Center: Available shortcuts
                Constraint::Percentage(30), // Right: Environment and other info
            ])
            .split(area);

        // Render left section (application state)
        self.render_app_state(f, chunks[0]);

        // Render center section (shortcuts)
        self.render_shortcuts(f, chunks[1]);

        // Render right section (environment info)
        self.render_environment_info(f, chunks[2]);
    }

    /// Render the application state section
    fn render_app_state(&self, f: &mut Frame, area: Rect) {
        let state_text = self.get_state_text();
        let tab_text = self.get_current_tab_text();
        
        let content = vec![
            Line::from(vec![
                Span::styled("State: ", Style::default().fg(self.theme.secondary)),
                Span::styled(state_text, Style::default().fg(self.theme.accent).add_modifier(Modifier::BOLD)),
            ]),
            Line::from(vec![
                Span::styled("Tab: ", Style::default().fg(self.theme.secondary)),
                Span::styled(tab_text, Style::default().fg(self.theme.primary)),
            ]),
        ];

        let paragraph = Paragraph::new(content)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(self.theme.border_style())
                    .title("Status")
                    .title_style(self.theme.title_style())
            )
            .style(Style::default().bg(self.theme.background));

        f.render_widget(paragraph, area);
    }

    /// Render the shortcuts section
    fn render_shortcuts(&self, f: &mut Frame, area: Rect) {
        let shortcuts = self.get_available_shortcuts();
        
        let content: Vec<Line> = shortcuts
            .chunks(2) // Display 2 shortcuts per line
            .map(|chunk| {
                let spans: Vec<Span> = chunk
                    .iter()
                    .enumerate()
                    .flat_map(|(i, (key, desc))| {
                        let mut spans = vec![
                            Span::styled(key.clone(), Style::default().fg(self.theme.accent).add_modifier(Modifier::BOLD)),
                            Span::styled(format!(":{} ", desc), Style::default().fg(self.theme.foreground)),
                        ];
                        
                        // Add separator if not the last item in the chunk
                        if i < chunk.len() - 1 {
                            spans.push(Span::styled("│ ", Style::default().fg(self.theme.secondary)));
                        }
                        
                        spans
                    })
                    .collect();
                Line::from(spans)
            })
            .collect();

        let paragraph = Paragraph::new(content)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(self.theme.border_style())
                    .title("Shortcuts")
                    .title_style(self.theme.title_style())
            )
            .style(Style::default().bg(self.theme.background))
            .alignment(Alignment::Center);

        f.render_widget(paragraph, area);
    }

    /// Render the environment info section
    fn render_environment_info(&self, f: &mut Frame, area: Rect) {
        let method = self.app.current_command.method
            .as_ref()
            .map(|m| m.to_string())
            .unwrap_or_else(|| "GET".to_string());
        
        let url_status = if self.app.current_command.url.is_empty() {
            "No URL"
        } else {
            "URL Set"
        };

        let execution_status = match &self.app.execution_result {
            Some(result) => {
                if result.exit_code == Some(0) {
                    "✓ Success"
                } else {
                    "✗ Failed"
                }
            }
            None => "Ready"
        };

        let content = vec![
            Line::from(vec![
                Span::styled("Env: ", Style::default().fg(self.theme.secondary)),
                Span::styled(&self.app.current_environment, Style::default().fg(self.theme.primary)),
            ]),
            Line::from(vec![
                Span::styled("Method: ", Style::default().fg(self.theme.secondary)),
                Span::styled(method, Style::default().fg(self.theme.accent)),
                Span::styled(" │ ", Style::default().fg(self.theme.secondary)),
                Span::styled(url_status, Style::default().fg(
                    if self.app.current_command.url.is_empty() {
                        self.theme.error
                    } else {
                        self.theme.success
                    }
                )),
            ]),
            Line::from(vec![
                Span::styled("Status: ", Style::default().fg(self.theme.secondary)),
                Span::styled(execution_status, Style::default().fg(
                    match &self.app.execution_result {
                        Some(result) if result.exit_code == Some(0) => self.theme.success,
                        Some(_) => self.theme.error,
                        None => self.theme.foreground,
                    }
                )),
            ]),
        ];

        let paragraph = Paragraph::new(content)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(self.theme.border_style())
                    .title("Info")
                    .title_style(self.theme.title_style())
            )
            .style(Style::default().bg(self.theme.background));

        f.render_widget(paragraph, area);
    }

    /// Get the current application state as a string
    fn get_state_text(&self) -> String {
        match &self.app.state {
            AppState::Normal => "Normal".to_string(),
            AppState::Editing(field) => {
                match field {
                    crate::app::EditField::Url => "Editing URL".to_string(),
                    crate::app::EditField::Method => "Editing Method".to_string(),
                    crate::app::EditField::HeaderKey(_) => "Editing Header Key".to_string(),
                    crate::app::EditField::HeaderValue(_) => "Editing Header Value".to_string(),
                    crate::app::EditField::QueryParamKey(_) => "Editing Query Key".to_string(),
                    crate::app::EditField::QueryParamValue(_) => "Editing Query Value".to_string(),
                    crate::app::EditField::Body => "Editing Body".to_string(),
                    crate::app::EditField::OptionValue(_) => "Editing Option".to_string(),
                }
            },
            AppState::MethodDropdown => "Method Selection".to_string(),
            AppState::EditingTemplateName => "Editing Template".to_string(),
            AppState::EditingEnvironment => "Editing Environment".to_string(),
            AppState::Help => "Help".to_string(),
            AppState::Exiting => "Exiting".to_string(),
        }
    }

    /// Get the current tab as a string
    fn get_current_tab_text(&self) -> String {
        match &self.app.ui_state.active_tab {
            Tab::Url => "URL".to_string(),
            Tab::Headers => "Headers".to_string(),
            Tab::Body => "Body".to_string(),
            Tab::Options => "Options".to_string(),
        }
    }

    /// Get available shortcuts based on current state
    fn get_available_shortcuts(&self) -> Vec<(String, String)> {
        match &self.app.state {
            AppState::Normal => {
                vec![
                    ("F5".to_string(), "Execute".to_string()),
                    ("Tab".to_string(), "Next Tab".to_string()),
                    ("↑↓".to_string(), "Navigate".to_string()),
                    ("Enter".to_string(), "Edit".to_string()),
                    ("F1".to_string(), "Help".to_string()),
                    ("Ctrl+Q".to_string(), "Quit".to_string()),
                ]
            }
            AppState::Editing(_) => {
                vec![
                    ("Enter".to_string(), "Save".to_string()),
                    ("Esc".to_string(), "Cancel".to_string()),
                ]
            }
            AppState::MethodDropdown => {
                vec![
                    ("↑↓".to_string(), "Select".to_string()),
                    ("Enter".to_string(), "Confirm".to_string()),
                    ("Esc".to_string(), "Cancel".to_string()),
                ]
            }
            AppState::Help => {
                vec![
                    ("F1".to_string(), "Close Help".to_string()),
                    ("Esc".to_string(), "Close Help".to_string()),
                ]
            }
            AppState::EditingTemplateName | AppState::EditingEnvironment => {
                vec![
                    ("Esc".to_string(), "Cancel".to_string()),
                ]
            }
            AppState::Exiting => {
                vec![
                    ("".to_string(), "Goodbye!".to_string()),
                ]
            }
        }
    }
}