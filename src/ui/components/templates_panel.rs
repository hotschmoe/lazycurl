use crate::app::App;
use crate::ui::theme::Theme;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState};
use ratatui::Frame;

/// Templates panel component
pub struct TemplatesPanel<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
    /// List state
    state: ListState,
}

impl<'a> TemplatesPanel<'a> {
    /// Create a new templates panel component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        let mut state = ListState::default();
        state.select(app.ui_state.selected_template);
        
        Self { app, theme, state }
    }

    /// Render the templates panel
    pub fn render(&mut self, frame: &mut Frame, area: Rect) {
        // Create block
        let block = Block::default()
            .title("Templates")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        // Create items
        let items: Vec<ListItem> = if self.app.templates.is_empty() {
            vec![ListItem::new("No templates")]
        } else {
            self.app.templates
                .iter()
                .map(|template| {
                    let line = Line::from(vec![
                        Span::styled(&template.name, self.theme.text_style()),
                    ]);
                    ListItem::new(line)
                })
                .collect()
        };

        // Create list
        let list = List::new(items)
            .block(block)
            .highlight_style(self.theme.highlight_style());

        // Render list
        frame.render_stateful_widget(list, area, &mut self.state);
    }
}

/// Templates tree component
pub struct TemplatesTree<'a> {
    /// Application state
    app: &'a App,
    /// UI theme
    theme: &'a Theme,
}

impl<'a> TemplatesTree<'a> {
    /// Create a new templates tree component
    pub fn new(app: &'a App, theme: &'a Theme) -> Self {
        Self { app, theme }
    }

    /// Render the templates tree
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        // Create block
        let block = Block::default()
            .title("Templates")
            .borders(Borders::ALL)
            .style(self.theme.border_style());

        // Create text
        // Create text
        let text = if self.app.templates.is_empty() {
            Text::from("No templates")
        } else {
            // Create lines for templates grouped by category
            let mut lines = Vec::new();
            
            // Group templates by category
            let mut category_map = std::collections::HashMap::new();
            for template in &self.app.templates {
                let category = template.category.clone().unwrap_or_else(|| "Uncategorized".to_string());
                category_map.entry(category).or_insert_with(Vec::new).push(template);
            }
            
            // Convert the HashMap into a Vec for stable iteration
            let mut categories: Vec<(String, Vec<&crate::models::template::CommandTemplate>)> =
                category_map.into_iter().collect();
            
            // Sort categories by name for consistent display
            categories.sort_by(|a, b| a.0.cmp(&b.0));
            
            // Add each category and its templates
            for (category, templates) in categories {
                // Add category
                let expanded = true; // TODO: Track expanded state
                let symbol = if expanded { "▼" } else { "▶" };
                lines.push(Line::from(vec![
                    Span::styled(symbol, self.theme.text_style()),
                    Span::raw(" "),
                    Span::styled(category.clone(), self.theme.header_style()),
                ]));

                // Add templates
                if expanded {
                    for template in templates {
                        let selected = self.app.ui_state.selected_template
                            .map(|idx| &self.app.templates[idx].id == &template.id)
                            .unwrap_or(false);
                        
                        let style = if selected {
                            self.theme.selected_style()
                        } else {
                            self.theme.text_style()
                        };
                        
                        lines.push(Line::from(vec![
                            Span::raw("  ▶ "),
                            Span::styled(&template.name, style),
                        ]));
                    }
                }
            }

            Text::from(lines)
        };

        // Create paragraph
        let paragraph = ratatui::widgets::Paragraph::new(text).block(block);

        // Render paragraph
        frame.render_widget(paragraph, area);
    }
}