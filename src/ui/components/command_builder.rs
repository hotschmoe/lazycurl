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

    /// Render method component (standalone)
    pub fn render_method_component(&self, frame: &mut Frame, area: Rect) {
        // Check if method dropdown is open
        let is_dropdown_open = matches!(&self.app.state, AppState::MethodDropdown);
        
        if is_dropdown_open {
            self.render_method_dropdown(frame, area);
        } else {
            self.render_method_selection(frame, area);
        }
    }

    /// Render URL input (without method)
    fn render_url_input(&self, frame: &mut Frame, area: Rect) {
        let url = &self.app.current_command.url;

        // Check if we're editing the URL
        let is_editing_url = matches!(&self.app.state, AppState::Editing(EditField::Url));
        let url_text = if is_editing_url {
            &self.app.ui_state.edit_buffer
        } else {
            url
        };

        // Determine if URL is selected
        let is_url_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Url(UrlField::Url)
        );

        // Style for URL based on selection and editing state
        let url_style = if is_editing_url {
            self.theme.editing_style()
        } else if is_url_selected {
            self.theme.selected_style()
        } else {
            self.theme.text_style()
        };

        // Add visual indicator for editing mode
        let url_display = if is_editing_url {
            format!("{} █", url_text) // Add cursor indicator
        } else {
            url_text.to_string()
        };

        let text = Text::from(vec![
            Line::from(vec![
                Span::styled(url_display, url_style),
            ]),
        ]);

        // Choose border style based on state
        let border_style = if is_editing_url {
            self.theme.editing_border_style()
        } else if is_url_selected {
            self.theme.active_border_style()
        } else {
            self.theme.border_style()
        };

        // Add title indicator for editing mode
        let title = if is_editing_url {
            "URL [EDIT]"
        } else if is_url_selected {
            "URL [SELECTED]"
        } else {
            "URL"
        };

        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .style(border_style);

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
        // Render query parameters (now takes the full area)
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
                let is_editing = matches!(&self.app.state, AppState::Editing(EditField::QueryParamValue(edit_idx)) if *edit_idx == idx);
                let value_text = if is_editing {
                    &self.app.ui_state.edit_buffer
                } else {
                    &param.value
                };

                // Style based on selection and editing state
                let style = if is_editing {
                    self.theme.editing_style()
                } else if is_selected {
                    self.theme.selected_style()
                } else {
                    self.theme.text_style()
                };

                // Add visual indicator for editing mode
                let value_display = if is_editing {
                    format!("{} █", value_text) // Add cursor indicator
                } else {
                    value_text.to_string()
                };

                // Add status indicator
                let status_indicator = if is_editing {
                    " [EDIT]"
                } else if is_selected {
                    " [SELECTED]"
                } else {
                    ""
                };

                lines.push(Line::from(vec![
                    Span::styled(enabled, style),
                    Span::raw(" "),
                    Span::styled(&param.key, style),
                    Span::raw(": "),
                    Span::styled(value_display, style),
                    Span::styled(status_indicator, if is_editing { self.theme.editing_style() } else { self.theme.selected_style() }),
                ]));
            }
            Text::from(lines)
        };

        let query_paragraph = Paragraph::new(query_text).block(query_block);
        frame.render_widget(query_paragraph, area);
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
                let is_editing = matches!(&self.app.state, AppState::Editing(EditField::HeaderValue(edit_idx)) if *edit_idx == idx);
                let value_text = if is_editing {
                    &self.app.ui_state.edit_buffer
                } else {
                    &header.value
                };

                // Style based on selection and editing state
                let style = if is_editing {
                    self.theme.editing_style()
                } else if is_selected {
                    self.theme.selected_style()
                } else {
                    self.theme.text_style()
                };

                // Add visual indicator for editing mode
                let value_display = if is_editing {
                    format!("{} █", value_text) // Add cursor indicator
                } else {
                    value_text.to_string()
                };

                // Add status indicator
                let status_indicator = if is_editing {
                    " [EDIT]"
                } else if is_selected {
                    " [SELECTED]"
                } else {
                    ""
                };

                lines.push(Line::from(vec![
                    Span::styled(enabled, style),
                    Span::raw(" "),
                    Span::styled(&header.key, style),
                    Span::raw(": "),
                    Span::styled(value_display, style),
                    Span::styled(status_indicator, if is_editing { self.theme.editing_style() } else { self.theme.selected_style() }),
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

        // Check if we're editing the body
        let is_editing_body = matches!(&self.app.state, AppState::Editing(EditField::Body));

        // Choose border style based on state
        let border_style = if is_editing_body {
            self.theme.editing_border_style()
        } else if is_content_selected {
            self.theme.active_border_style()
        } else {
            self.theme.border_style()
        };

        // Add title indicator for editing mode
        let title = if is_editing_body {
            "Request Body [EDIT]"
        } else if is_content_selected {
            "Request Body [SELECTED]"
        } else {
            "Request Body"
        };

        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .style(border_style);

        // Check if we're editing the body
        let text = if is_editing_body {
            // Add cursor indicator for editing mode
            let content_with_cursor = format!("{} █", self.app.ui_state.edit_buffer);
            Text::from(vec![Line::from(Span::styled(content_with_cursor, self.theme.editing_style()))])
        } else {
            match &self.app.current_command.body {
                Some(body) => match body {
                    crate::models::command::RequestBody::Raw(content) => {
                        let style = if is_content_selected {
                            self.theme.selected_style()
                        } else {
                            self.theme.text_style()
                        };
                        Text::from(vec![Line::from(Span::styled(content, style))])
                    }
                    crate::models::command::RequestBody::FormData(items) => {
                        let mut lines = Vec::new();
                        for item in items {
                            let enabled = if item.enabled { "✓" } else { "✗" };
                            let style = if is_content_selected {
                                self.theme.selected_style()
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
                            self.theme.selected_style()
                        } else {
                            self.theme.text_style()
                        };
                        Text::from(vec![Line::from(Span::styled(
                            format!("Binary file: {}", path.display()),
                            style
                        ))])
                    }
                    crate::models::command::RequestBody::None => {
                        let style = if is_content_selected {
                            self.theme.selected_style()
                        } else {
                            self.theme.text_style()
                        };
                        Text::from(vec![Line::from(Span::styled("No request body", style))])
                    }
                },
                None => {
                    let style = if is_content_selected {
                        self.theme.selected_style()
                    } else {
                        self.theme.text_style()
                    };
                    Text::from(vec![Line::from(Span::styled("No request body", style))])
                },
            }
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

                // Check if we're editing this option
                let is_editing = matches!(&self.app.state, AppState::Editing(EditField::OptionValue(edit_idx)) if *edit_idx == idx);

                // Style based on selection and editing state
                let style = if is_editing {
                    self.theme.editing_style()
                } else if is_selected {
                    self.theme.selected_style()
                } else {
                    self.theme.text_style()
                };

                // Check if we're editing this option
                let value_display = if is_editing {
                    format!(": {} █", self.app.ui_state.edit_buffer) // Add cursor indicator
                } else {
                    match &option.value {
                        Some(val) => format!(": {}", val),
                        None => String::new(),
                    }
                };

                // Add status indicator
                let status_indicator = if is_editing {
                    " [EDIT]"
                } else if is_selected {
                    " [SELECTED]"
                } else {
                    ""
                };

                lines.push(Line::from(vec![
                    Span::styled(enabled, style),
                    Span::raw(" "),
                    Span::styled(&option.flag, style),
                    Span::styled(value_display, style),
                    Span::styled(status_indicator, if is_editing { self.theme.editing_style() } else { self.theme.selected_style() }),
                ]));
            }
            Text::from(lines)
        };

        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }

    /// Render method selection (when dropdown is closed)
    fn render_method_selection(&self, frame: &mut Frame, area: Rect) {
        let current_method = self.app.current_command.method.as_ref().unwrap_or(&HttpMethod::GET).to_string();
        
        // Determine if method is selected
        let is_method_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Url(UrlField::Method)
        );

        // Style for method based on selection state
        let method_style = if is_method_selected {
            self.theme.selected_style()
        } else {
            self.theme.text_style()
        };

        let method_text = Text::from(vec![
            Line::from(vec![
                Span::styled(&current_method, method_style),
                Span::raw(" ▼"), // Dropdown indicator
            ]),
        ]);

        // Choose border style based on state
        let border_style = if is_method_selected {
            self.theme.active_border_style()
        } else {
            self.theme.border_style()
        };

        // Add title indicator with debug info
        let title = if is_method_selected {
            "Method [SELECTED] - Press Enter to open dropdown"
        } else {
            "Method"
        };

        let method_block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .style(border_style);

        let method_paragraph = Paragraph::new(method_text).block(method_block);
        frame.render_widget(method_paragraph, area);
    }

    /// Render method dropdown (when dropdown is open)
    fn render_method_dropdown(&self, frame: &mut Frame, area: Rect) {
        let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];
        let selected_index = self.app.ui_state.method_dropdown_index;

        // Ensure selected_index is within bounds to prevent crashes
        // but use modulo to preserve circular behavior
        let safe_selected_index = selected_index % methods.len();

        // Show all methods since we now have dedicated vertical space
        let mut lines = Vec::new();
        
        // Add all methods
        for (i, method) in methods.iter().enumerate() {
            lines.push(Line::from(vec![
                if i == safe_selected_index {
                    Span::styled(format!("  ► {} ◄", method), self.theme.highlight_style())
                } else {
                    Span::styled(format!("    {}", method), self.theme.text_style())
                }
            ]));
        }

        let dropdown_text = Text::from(lines);

        let dropdown_block = Block::default()
            .title("Method [EDIT]")
            .borders(Borders::ALL)
            .style(self.theme.editing_border_style());

        let dropdown_paragraph = Paragraph::new(dropdown_text).block(dropdown_block);
        frame.render_widget(dropdown_paragraph, area);
    }
}