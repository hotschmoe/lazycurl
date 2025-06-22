use crate::app::{App, Tab, AppState, EditField, SelectedField, UrlField, BodyField};
use crate::models::command::{CurlCommand, HttpMethod};
use crate::ui::theme::Theme;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Paragraph, Tabs};
use ratatui::Frame;

/// URL container component that holds URL, tabs, and editor box
pub struct UrlContainer<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
}

impl<'a> UrlContainer<'a> {
    /// Create a new URL container component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        Self { app, theme }
    }

    /// Render the URL container
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        // Determine if the URL container is selected (but not when Method is selected)
        let is_container_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Url(UrlField::Url) |
            SelectedField::Url(UrlField::QueryParam(_)) |
            SelectedField::Headers(_) |
            SelectedField::Body(_) |
            SelectedField::Options(_)
        ) && self.app.ui_state.selected_template.is_none();

        // Choose border style based on selection state
        let border_style = if is_container_selected {
            self.theme.active_border_style()
        } else {
            self.theme.border_style()
        };

        // Add title indicator for selection
        let title = if is_container_selected {
            "URL Builder "
        } else {
            "URL Builder"
        };

        // Create main container block
        let container_block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .style(border_style);

        // Get inner area for content
        let inner_area = container_block.inner(area);

        // Render the container block
        frame.render_widget(container_block, area);

        // Create layout within the container
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),  // URL input
                Constraint::Length(3),  // Tabs
                Constraint::Min(0),     // Tab content
            ])
            .split(inner_area);

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

        // Determine if URL is selected (but not when templates are focused)
        let is_url_selected = matches!(
            self.app.ui_state.selected_field,
            SelectedField::Url(UrlField::Url)
        ) && self.app.ui_state.selected_template.is_none();

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
            let cursor = if self.app.ui_state.cursor_visible { "█" } else { " " };
            format!("{}{}", url_text, cursor) // Add blinking cursor indicator
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
            "URL "
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
        
        // Determine if any field in each tab is selected
        let url_selected = matches!(self.app.ui_state.selected_field, SelectedField::Url(_));
        let headers_selected = matches!(self.app.ui_state.selected_field, SelectedField::Headers(_));
        let body_selected = matches!(self.app.ui_state.selected_field, SelectedField::Body(_));
        let options_selected = matches!(self.app.ui_state.selected_field, SelectedField::Options(_));
        
        let titles = titles
            .iter()
            .enumerate()
            .map(|(i, t)| {
                let is_selected = match i {
                    0 => url_selected,
                    1 => headers_selected,
                    2 => body_selected,
                    3 => options_selected,
                    _ => false,
                };
                
                let style = if is_selected {
                    self.theme.selected_style()
                } else {
                    self.theme.text_style()
                };
                
                Line::from(Span::styled(*t, style))
            })
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
                    let cursor = if self.app.ui_state.cursor_visible { "█" } else { " " };
                    format!("{}{}", value_text, cursor) // Add blinking cursor indicator
                } else {
                    value_text.to_string()
                };

                // Add status indicator
                let status_indicator = if is_editing {
                    " [EDIT]"
                } else if is_selected {
                    " "
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
        // Determine if any header is selected
        let is_headers_selected = matches!(self.app.ui_state.selected_field, SelectedField::Headers(_));
        
        let border_style = if is_headers_selected {
            self.theme.active_border_style()
        } else {
            self.theme.border_style()
        };
        
        let title = if is_headers_selected {
            "Headers "
        } else {
            "Headers"
        };
        
        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .style(border_style);

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
                    let cursor = if self.app.ui_state.cursor_visible { "█" } else { " " };
                    format!("{}{}", value_text, cursor) // Add blinking cursor indicator
                } else {
                    value_text.to_string()
                };

                // Add status indicator
                let status_indicator = if is_editing {
                    " [EDIT]"
                } else if is_selected {
                    " "
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

        if is_editing_body {
            // Create a clone of the TextArea for rendering with proper styling
            let mut textarea = self.app.ui_state.body_textarea.clone();
            
            // Set the block style for editing mode
            textarea.set_block(
                Block::default()
                    .title("Request Body [EDIT] - Press F2 to save, Esc to cancel")
                    .borders(Borders::ALL)
                    .style(self.theme.editing_border_style())
            );
            
            // Set cursor style to make it more visible
            textarea.set_cursor_style(
                ratatui::style::Style::default()
                    .bg(ratatui::style::Color::Yellow)
                    .fg(ratatui::style::Color::Black)
            );
            
            // Render the TextArea directly - it should implement Widget
            // Render TextArea content with cursor indication
            let content = textarea.lines().join("\n");
            let (cursor_row, cursor_col) = textarea.cursor();
            
            let mut text_lines = Vec::new();
            for (row_idx, line) in content.lines().enumerate() {
                if row_idx == cursor_row {
                    // Add cursor indicator with yellow background
                    let mut line_spans = Vec::new();
                    
                    // Add text before cursor
                    if cursor_col > 0 {
                        let before_cursor = if cursor_col <= line.len() {
                            &line[..cursor_col]
                        } else {
                            line
                        };
                        line_spans.push(Span::styled(before_cursor, self.theme.editing_style()));
                    }
                    
                    // Add cursor with yellow background
                    let cursor_char = if cursor_col < line.len() {
                        line.chars().nth(cursor_col).unwrap_or(' ').to_string()
                    } else {
                        " ".to_string()
                    };
                    line_spans.push(Span::styled(
                        cursor_char,
                        ratatui::style::Style::default()
                            .bg(ratatui::style::Color::Yellow)
                            .fg(ratatui::style::Color::Black)
                    ));
                    
                    // Add text after cursor
                    if cursor_col < line.len() {
                        let after_cursor = &line[cursor_col + 1..];
                        if !after_cursor.is_empty() {
                            line_spans.push(Span::styled(after_cursor, self.theme.editing_style()));
                        }
                    }
                    
                    text_lines.push(Line::from(line_spans));
                } else {
                    text_lines.push(Line::from(Span::styled(line, self.theme.editing_style())));
                }
            }
            
            // If cursor is beyond all lines, add an empty line with cursor
            if cursor_row >= content.lines().count() {
                text_lines.push(Line::from(Span::styled(
                    " ",
                    ratatui::style::Style::default()
                        .bg(ratatui::style::Color::Yellow)
                        .fg(ratatui::style::Color::Black)
                )));
            }
            
            let text = Text::from(text_lines);
            let block = Block::default()
                .title("Request Body [EDIT] - Press F2 to save, Esc to cancel")
                .borders(Borders::ALL)
                .style(self.theme.editing_border_style());
            
            let paragraph = Paragraph::new(text).block(block);
            frame.render_widget(paragraph, area);
        } else {
            // Choose border style based on state
            let border_style = if is_content_selected {
                self.theme.active_border_style()
            } else {
                self.theme.border_style()
            };

            // Add title indicator
            let title = if is_content_selected {
                "Request Body "
            } else {
                "Request Body"
            };

            let block = Block::default()
                .title(title)
                .borders(Borders::ALL)
                .style(border_style);

            // Display current body content
            let text = match &self.app.current_command.body {
                Some(body) => match body {
                    crate::models::command::RequestBody::Raw(content) => {
                        let style = if is_content_selected {
                            self.theme.selected_style()
                        } else {
                            self.theme.text_style()
                        };
                        Text::from(content.lines().map(|line| Line::from(Span::styled(line, style))).collect::<Vec<_>>())
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
            };

            let paragraph = Paragraph::new(text).block(block);
            frame.render_widget(paragraph, area);
        }
    }

    /// Render options tab
    fn render_options_tab(&self, frame: &mut Frame, area: Rect) {
        // Determine if any option is selected
        let is_options_selected = matches!(self.app.ui_state.selected_field, SelectedField::Options(_));
        
        let border_style = if is_options_selected {
            self.theme.active_border_style()
        } else {
            self.theme.border_style()
        };
        
        let title = if is_options_selected {
            "Curl Options "
        } else {
            "Curl Options"
        };
        
        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .style(border_style);
            
        // Create a CurlOptions instance to get the available options
        let curl_options = crate::command::options::CurlOptions::new();
        
        // Get command line options
        let command_line_options = curl_options.get_options_by_category(
            &crate::command::options::OptionCategory::CommandLine
        );
        
        // Sort command line options by flag to ensure stable ordering
        let mut sorted_command_line_options = command_line_options.clone();
        sorted_command_line_options.sort_by(|a, b| a.flag.cmp(&b.flag));
        
        // Create a unified list of all options (both active and available)
        let mut lines = Vec::new();
        
        // Add header row for the grid
        lines.push(Line::from(vec![
            Span::styled("Status", self.theme.header_style()),
            Span::raw(" | "),
            Span::styled("Option", self.theme.header_style()),
            Span::raw(" | "),
            Span::styled("Value", self.theme.header_style()),
            Span::raw(" | "),
            Span::styled("Description", self.theme.header_style()),
        ]));
        
        // Add separator line
        lines.push(Line::from("─────────────────────────────────────────────────────────────"));
        
        // First, add all active options
        for (idx, option) in self.app.current_command.options.iter().enumerate() {
            // Determine if this option is selected
            let is_selected = matches!(
                self.app.ui_state.selected_field,
                SelectedField::Options(selected_idx) if selected_idx == idx
            );
            
            // Check if we're editing this option
            let is_editing = matches!(&self.app.state, AppState::Editing(EditField::OptionValue(edit_idx)) if *edit_idx == idx);
            
            // Status column (checkbox)
            let status = if option.enabled { "✓" } else { "✗" };
            
            // Option column (flag)
            let flag = &option.flag;
            
            // Value column
            let value_display_string = if is_editing {
                let cursor = if self.app.ui_state.cursor_visible { "█" } else { " " };
                format!("{}{}", self.app.ui_state.edit_buffer, cursor) // Add blinking cursor indicator
            } else {
                match &option.value {
                    Some(val) => val.clone(),
                    None => String::new(),
                }
            };
            
            // Style based on selection and editing state
            let style = if is_editing {
                self.theme.editing_style()
            } else if is_selected {
                self.theme.selected_style()
            } else {
                self.theme.text_style()
            };
            
            // Add status indicator
            let status_indicator = if is_editing {
                " [EDIT]"
            } else if is_selected {
                " "
            } else {
                ""
            };
            
            // Get the option description if available
            let description = match sorted_command_line_options.iter().find(|o| o.flag == option.flag) {
                Some(opt_def) => &opt_def.description,
                None => "",
            };
            
            lines.push(Line::from(vec![
                Span::styled(status, style),
                Span::raw(" | "),
                Span::styled(flag, style),
                Span::raw(" | "),
                Span::styled(value_display_string.clone(), style),
                Span::raw(" | "),
                Span::styled(description, style),
                Span::styled(status_indicator, if is_editing { self.theme.editing_style() } else { self.theme.selected_style() }),
            ]));
        }
        
        // Then, add all command line options that aren't already active
        for (cmd_idx, option) in sorted_command_line_options.iter().enumerate() {
            // Skip if this option is already in the active options
            let is_in_command = self.app.current_command.options.iter()
                .any(|o| o.flag == option.flag);
            
            if is_in_command {
                continue;
            }
            
            // Calculate the absolute index (active options + command line option index)
            let absolute_idx = self.app.current_command.options.len() + cmd_idx;
            
            // Check if this command line option is selected
            let is_selected = matches!(
                self.app.ui_state.selected_field,
                SelectedField::Options(selected_idx) if selected_idx == absolute_idx
            );
            
            // Status column (checkbox)
            let status = "☐";
            
            // Option column (flag)
            let flag = &option.flag;
            
            // Value column
            let value_text_string = if option.takes_value {
                "<value>".to_string()
            } else {
                "".to_string()
            };
            
            // Description column
            let description = &option.description;
            
            // Style based on selection state
            let style = if is_selected {
                self.theme.selected_style()
            } else {
                self.theme.text_style()
            };
            
            // Add status indicator for selection
            let status_indicator = if is_selected { " " } else { "" };
            
            lines.push(Line::from(vec![
                Span::styled(status, style),
                Span::raw(" | "),
                Span::styled(flag, if is_selected { style } else { Style::default().fg(self.theme.primary) }),
                Span::raw(" | "),
                Span::styled(value_text_string.clone(), if is_selected { style } else { Style::default().fg(self.theme.secondary) }),
                Span::raw(" | "),
                Span::styled(description, style),
                Span::styled(status_indicator, self.theme.selected_style()),
            ]));
        }
        
        let text = Text::from(lines);
        let paragraph = Paragraph::new(text).block(block);
        frame.render_widget(paragraph, area);
    }
}