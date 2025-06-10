use crate::app::{App, Tab, AppState, EditField, SelectedField, UrlField, BodyField};
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

        // Check if we're editing the URL
        let url_text = match &self.app.state {
            AppState::Editing(EditField::Url) => &self.app.ui_state.edit_buffer,
            _ => url,
        };

        // Determine if URL is selected
        let is_url_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Url(UrlField::Url)
        );

        // Style for URL based on selection
        let url_style = if is_url_selected {
            Style::default()
                .fg(self.theme.accent)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };

        let text = Text::from(vec![
            Line::from(vec![
                Span::styled(
                    format!("{} ", method),
                    Style::default()
                        .fg(self.theme.primary)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::styled(url_text, url_style),
            ]),
        ]);

        let block = Block::default()
            .title("URL")
            .borders(Borders::ALL)
            .style(if is_url_selected {
                self.theme.active_border_style()
            } else {
                self.theme.border_style()
            });

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
        
        // Check if we're editing the method
        let method_text = match &self.app.state {
            AppState::Editing(EditField::Method) => &self.app.ui_state.edit_buffer,
            _ => &current_method,
        };

        // Determine if method is selected
        let is_method_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Url(UrlField::Method)
        );

        // Style for method based on selection
        let method_style = if is_method_selected {
            self.theme.highlight_style()
        } else {
            self.theme.selected_style()
        };

        let method_text = Text::from(vec![
            Line::from(vec![
                Span::raw("HTTP Method: "),
                Span::styled(method_text, method_style),
            ]),
        ]);

        let method_block = Block::default()
            .title("Method")
            .borders(Borders::ALL)
            .style(if is_method_selected {
                self.theme.active_border_style()
            } else {
                self.theme.border_style()
            });

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
            for (idx, param) in self.app.current_command.query_params.iter().enumerate() {
                let enabled = if param.enabled { "✓" } else { "✗" };
                
                // Determine if this query param is selected
                let is_selected = matches!(
                    self.app.ui_state.selected_field,
                    SelectedField::Url(UrlField::QueryParam(selected_idx)) if selected_idx == idx
                );

                // Check if we're editing this query param
                let value_text = match &self.app.state {
                    AppState::Editing(EditField::QueryParamValue(edit_idx)) if *edit_idx == idx =>
                        &self.app.ui_state.edit_buffer,
                    _ => &param.value,
                };

                // Style based on selection
                let style = if is_selected {
                    self.theme.highlight_style()
                } else {
                    self.theme.text_style()
                };

                lines.push(Line::from(vec![
                    Span::styled(enabled, style),
                    Span::raw(" "),
                    Span::styled(&param.key, style),
                    Span::raw(": "),
                    Span::styled(value_text, style),
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
            for (idx, header) in self.app.current_command.headers.iter().enumerate() {
                let enabled = if header.enabled { "✓" } else { "✗" };
                
                // Determine if this header is selected
                let is_selected = matches!(
                    self.app.ui_state.selected_field,
                    SelectedField::Headers(selected_idx) if selected_idx == idx
                );

                // Check if we're editing this header
                let value_text = match &self.app.state {
                    AppState::Editing(EditField::HeaderValue(edit_idx)) if *edit_idx == idx =>
                        &self.app.ui_state.edit_buffer,
                    _ => &header.value,
                };

                // Style based on selection
                let style = if is_selected {
                    self.theme.highlight_style()
                } else {
                    self.theme.text_style()
                };

                lines.push(Line::from(vec![
                    Span::styled(enabled, style),
                    Span::raw(" "),
                    Span::styled(&header.key, style),
                    Span::raw(": "),
                    Span::styled(value_text, style),
                ]));
            }
            Text::from(lines)
        };

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }

    /// Render body tab
    fn render_body_tab(&self, frame: &mut Frame, area: Rect) {
        // Determine if body content is selected
        let is_content_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Body(BodyField::Content)
        );

        let block = Block::default()
            .title("Request Body")
            .borders(Borders::ALL)
            .style(if is_content_selected {
                self.theme.active_border_style()
            } else {
                self.theme.border_style()
            });

        // Check if we're editing the body
        let text = match &self.app.state {
            AppState::Editing(EditField::Body) => {
                Text::from(self.app.ui_state.edit_buffer.clone())
            },
            _ => match &self.app.current_command.body {
                Some(body) => match body {
                    crate::models::command::RequestBody::Raw(content) => {
                        let style = if is_content_selected {
                            self.theme.highlight_style()
                        } else {
                            Style::default()
                        };
                        Text::from(vec![Line::from(Span::styled(content, style))])
                    }
                    crate::models::command::RequestBody::FormData(items) => {
                        let mut lines = Vec::new();
                        for item in items {
                            let enabled = if item.enabled { "✓" } else { "✗" };
                            let style = if is_content_selected {
                                self.theme.highlight_style()
                            } else {
                                self.theme.text_style()
                            };
                            lines.push(Line::from(vec![
                                Span::styled(enabled, style),
                                Span::raw(" "),
                                Span::styled(&item.key, style),
                                Span::raw(": "),
                                Span::styled(&item.value, style),
                            ]));
                        }
                        Text::from(lines)
                    }
                    crate::models::command::RequestBody::Binary(path) => {
                        let style = if is_content_selected {
                            self.theme.highlight_style()
                        } else {
                            Style::default()
                        };
                        Text::from(vec![Line::from(Span::styled(
                            format!("Binary file: {}", path.display()),
                            style
                        ))])
                    }
                    crate::models::command::RequestBody::None => {
                        let style = if is_content_selected {
                            self.theme.highlight_style()
                        } else {
                            Style::default()
                        };
                        Text::from(vec![Line::from(Span::styled("No request body", style))])
                    }
                },
                None => {
                    let style = if is_content_selected {
                        self.theme.highlight_style()
                    } else {
                        Style::default()
                    };
                    Text::from(vec![Line::from(Span::styled("No request body", style))])
                },
            },
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
            for (idx, option) in self.app.current_command.options.iter().enumerate() {
                let enabled = if option.enabled { "✓" } else { "✗" };
                
                // Determine if this option is selected
                let is_selected = matches!(
                    self.app.ui_state.selected_field,
                    SelectedField::Options(selected_idx) if selected_idx == idx
                );

                // Style based on selection
                let style = if is_selected {
                    self.theme.highlight_style()
                } else {
                    self.theme.text_style()
                };

                // Check if we're editing this option
                let value_display = match &self.app.state {
                    AppState::Editing(EditField::OptionValue(edit_idx)) if *edit_idx == idx => {
                        format!(": {}", self.app.ui_state.edit_buffer)
                    },
                    _ => match &option.value {
                        Some(val) => format!(": {}", val),
                        None => String::new(),
                    },
                };

                lines.push(Line::from(vec![
                    Span::styled(enabled, style),
                    Span::raw(" "),
                    Span::styled(&option.flag, style),
                    Span::styled(value_display, style),
                ]));
            }
            Text::from(lines)
        };

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }
}