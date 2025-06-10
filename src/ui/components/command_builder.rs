use crate::app::{App, Tab};
use crate::models::command::{CurlCommand, HttpMethod};
use crate::ui::theme::Theme;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Paragraph, Tabs};
use ratatui::Frame;

/// Command builder component
pub struct CommandBuilder<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
}

impl<'a> CommandBuilder<'a> {
    /// Create a new command builder component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        Self { app, theme }
    }

    /// Render the command builder
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        // Create layout
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),  // URL input
                Constraint::Length(3),  // Tabs
                Constraint::Min(0),     // Tab content
            ])
            .split(area);

        // Render URL input
        self.render_url_input(frame, chunks[0]);

        // Render tabs
        self.render_tabs(frame, chunks[1]);

        // Render tab content
        match self.app.ui_state.active_tab {
            Tab::Url => self.render_url_tab(frame, chunks[2]),
            Tab::Headers => self.render_headers_tab(frame, chunks[2]),
            Tab::Body => self.render_body_tab(frame, chunks[2]),
            Tab::Options => self.render_options_tab(frame, chunks[2]),
        }
    }

    /// Render URL input
    fn render_url_input(&self, frame: &mut Frame, area: Rect) {
        let method = self.app.current_command.method.as_ref().unwrap_or(&HttpMethod::GET);
        let url = &self.app.current_command.url;

        let text = Text::from(vec![
            Line::from(vec![
                Span::styled(
                    format!("{} ", method),
                    Style::default()
                        .fg(self.theme.primary)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::raw(url),
            ]),
        ]);

        let block = Block::default()
            .title("URL")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }

    /// Render tabs
    fn render_tabs(&self, frame: &mut Frame, area: Rect) {
        let titles = vec!["URL", "Headers", "Body", "Curl Options"];
        let titles = titles
            .iter()
            .map(|t| Line::from(Span::styled(*t, self.theme.text_style())))
            .collect();

        let tabs = Tabs::new(titles)
            .block(Block::default().borders(Borders::ALL).style(self.theme.border_style()))
            .select(match self.app.ui_state.active_tab {
                Tab::Url => 0,
                Tab::Headers => 1,
                Tab::Body => 2,
                Tab::Options => 3,
            })
            .style(self.theme.inactive_style())
            .highlight_style(self.theme.active_style());

        frame.render_widget(tabs, area);
    }

    /// Render URL tab
    fn render_url_tab(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),  // Method selection
                Constraint::Min(0),     // Query parameters
            ])
            .split(area);

        // Render method selection
        let methods = vec!["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];
        let current_method = self.app.current_command.method.as_ref().unwrap_or(&HttpMethod::GET).to_string();
        
        let method_text = Text::from(vec![
            Line::from(vec![
                Span::raw("HTTP Method: "),
                Span::styled(current_method, self.theme.selected_style()),
            ]),
        ]);

        let method_block = Block::default()
            .title("Method")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        let method_paragraph = Paragraph::new(method_text).block(method_block);
        frame.render_widget(method_paragraph, chunks[0]);

        // Render query parameters
        let query_block = Block::default()
            .title("Query Parameters")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        let query_text = if self.app.current_command.query_params.is_empty() {
            Text::from(vec![Line::from(Span::raw("No query parameters"))])
        } else {
            let mut lines = Vec::new();
            for param in &self.app.current_command.query_params {
                let enabled = if param.enabled { "✓" } else { "✗" };
                lines.push(Line::from(vec![
                    Span::styled(enabled, self.theme.text_style()),
                    Span::raw(" "),
                    Span::styled(&param.key, self.theme.text_style()),
                    Span::raw(": "),
                    Span::styled(&param.value, self.theme.text_style()),
                ]));
            }
            Text::from(lines)
        };

        let query_paragraph = Paragraph::new(query_text).block(query_block);
        frame.render_widget(query_paragraph, chunks[1]);
    }

    /// Render headers tab
    fn render_headers_tab(&self, frame: &mut Frame, area: Rect) {
        let block = Block::default()
            .title("Headers")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        let text = if self.app.current_command.headers.is_empty() {
            Text::from(vec![Line::from(Span::raw("No headers"))])
        } else {
            let mut lines = Vec::new();
            for header in &self.app.current_command.headers {
                let enabled = if header.enabled { "✓" } else { "✗" };
                lines.push(Line::from(vec![
                    Span::styled(enabled, self.theme.text_style()),
                    Span::raw(" "),
                    Span::styled(&header.key, self.theme.text_style()),
                    Span::raw(": "),
                    Span::styled(&header.value, self.theme.text_style()),
                ]));
            }
            Text::from(lines)
        };

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }

    /// Render body tab
    fn render_body_tab(&self, frame: &mut Frame, area: Rect) {
        let block = Block::default()
            .title("Request Body")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        let text = match &self.app.current_command.body {
            Some(body) => match body {
                crate::models::command::RequestBody::Raw(content) => {
                    Text::from(content.clone())
                }
                crate::models::command::RequestBody::FormData(items) => {
                    let mut lines = Vec::new();
                    for item in items {
                        let enabled = if item.enabled { "✓" } else { "✗" };
                        lines.push(Line::from(vec![
                            Span::styled(enabled, self.theme.text_style()),
                            Span::raw(" "),
                            Span::styled(&item.key, self.theme.text_style()),
                            Span::raw(": "),
                            Span::styled(&item.value, self.theme.text_style()),
                        ]));
                    }
                    Text::from(lines)
                }
                crate::models::command::RequestBody::Binary(path) => {
                    Text::from(format!("Binary file: {}", path.display()))
                }
                crate::models::command::RequestBody::None => {
                    Text::from("No request body")
                }
            },
            None => Text::from("No request body"),
        };

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }

    /// Render options tab
    fn render_options_tab(&self, frame: &mut Frame, area: Rect) {
        let block = Block::default()
            .title("Curl Options")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        let text = if self.app.current_command.options.is_empty() {
            Text::from(vec![Line::from(Span::raw("No options"))])
        } else {
            let mut lines = Vec::new();
            for option in &self.app.current_command.options {
                let enabled = if option.enabled { "✓" } else { "✗" };
                let value = match &option.value {
                    Some(val) => format!(": {}", val),
                    None => String::new(),
                };
                lines.push(Line::from(vec![
                    Span::styled(enabled, self.theme.text_style()),
                    Span::raw(" "),
                    Span::styled(&option.flag, self.theme.text_style()),
                    Span::raw(value),
                ]));
            }
            Text::from(lines)
        };

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }
}