use crate::app::{App, OptionCategory};
use crate::command::options::{CurlOptions, OptionTier};
use crate::ui::theme::Theme;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph};
use ratatui::Frame;

/// Options panel component
pub struct OptionsPanel<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
    /// Curl options
    options: CurlOptions,
    /// Category list state
    category_state: ListState,
}

impl<'a> OptionsPanel<'a> {
    /// Create a new options panel component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        let mut category_state = ListState::default();
        category_state.select(Some(match app.ui_state.selected_option_category {
            OptionCategory::Basic => 0,
            OptionCategory::Request => 1,
            OptionCategory::Authentication => 2,
            OptionCategory::Connection => 3,
            OptionCategory::Header => 4,
            OptionCategory::Ssl => 5,
            OptionCategory::Proxy => 6,
            OptionCategory::Output => 7,
        }));
        
        Self {
            app,
            theme,
            options: CurlOptions::new(),
            category_state,
        }
    }

    /// Render the options panel
    pub fn render(&mut self, frame: &mut Frame, area: Rect) {
        // Create layout
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Percentage(70),
            ])
            .split(area);

        // Render categories
        self.render_categories(frame, chunks[0]);

        // Render options
        self.render_options(frame, chunks[1]);
    }

    /// Render option categories
    fn render_categories(&mut self, frame: &mut Frame, area: Rect) {
        // Create block
        let block = Block::default()
            .title("Categories")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        // Create items
        let items = vec![
            ListItem::new("Basic Options"),
            ListItem::new("Request Options"),
            ListItem::new("Authentication Options"),
            ListItem::new("Connection Options"),
            ListItem::new("Header Options"),
            ListItem::new("SSL/TLS Options"),
            ListItem::new("Proxy Options"),
            ListItem::new("Output Options"),
        ];

        // Create list
        let list = List::new(items)
            .block(block)
            .highlight_style(self.theme.highlight_style());

        // Render list
        frame.render_stateful_widget(list, area, &mut self.category_state);
    }

    /// Render options for the selected category
    fn render_options(&self, frame: &mut Frame, area: Rect) {
        // Get selected category
        let selected_category = match self.category_state.selected() {
            Some(0) => crate::command::options::OptionCategory::Basic,
            Some(1) => crate::command::options::OptionCategory::Request,
            Some(2) => crate::command::options::OptionCategory::Authentication,
            Some(3) => crate::command::options::OptionCategory::Connection,
            Some(4) => crate::command::options::OptionCategory::Header,
            Some(5) => crate::command::options::OptionCategory::Ssl,
            Some(6) => crate::command::options::OptionCategory::Proxy,
            Some(7) => crate::command::options::OptionCategory::Output,
            _ => crate::command::options::OptionCategory::Basic,
        };

        // Get options for the selected category
        let basic_options = self.options.get_options_by_category_and_tier(
            &selected_category,
            &OptionTier::Basic,
        );
        let advanced_options = self.options.get_options_by_category_and_tier(
            &selected_category,
            &OptionTier::Advanced,
        );

        // Create block
        let block = Block::default()
            .title(format!("{}", selected_category))
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        // Create text
        let mut lines = Vec::new();

        // Add basic options
        lines.push(Line::from(vec![
            Span::styled("Basic Options", self.theme.header_style()),
        ]));
        lines.push(Line::from(""));

        for option in &basic_options {
            // Check if option is enabled in the current command
            let enabled = self.app.current_command.options.iter()
                .any(|o| o.flag == option.flag && o.enabled);
            
            let checkbox = if enabled { "✓" } else { "☐" };
            let value_text = if option.takes_value {
                " <value>"
            } else {
                ""
            };
            
            lines.push(Line::from(vec![
                Span::styled(checkbox, self.theme.text_style()),
                Span::raw(" "),
                Span::styled(&option.flag, Style::default().fg(self.theme.primary)),
                Span::styled(value_text, Style::default().fg(self.theme.secondary)),
                Span::raw(" - "),
                Span::styled(&option.description, self.theme.text_style()),
            ]));
        }

        // Add advanced options
        if !advanced_options.is_empty() {
            lines.push(Line::from(""));
            lines.push(Line::from(vec![
                Span::styled("Advanced Options", self.theme.header_style()),
            ]));
            lines.push(Line::from(""));

            for option in &advanced_options {
                // Check if option is enabled in the current command
                let enabled = self.app.current_command.options.iter()
                    .any(|o| o.flag == option.flag && o.enabled);
                
                let checkbox = if enabled { "✓" } else { "☐" };
                let value_text = if option.takes_value {
                    " <value>"
                } else {
                    ""
                };
                
                lines.push(Line::from(vec![
                    Span::styled(checkbox, self.theme.text_style()),
                    Span::raw(" "),
                    Span::styled(&option.flag, Style::default().fg(self.theme.primary)),
                    Span::styled(value_text, Style::default().fg(self.theme.secondary)),
                    Span::raw(" - "),
                    Span::styled(&option.description, self.theme.text_style()),
                ]));
            }
        }

        // Create paragraph
        let paragraph = Paragraph::new(Text::from(lines)).block(block);

        // Render paragraph
        frame.render_widget(paragraph, area);
    }
}