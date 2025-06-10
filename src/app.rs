use crate::models::command::CurlCommand;
use crate::models::environment::Environment;
use crate::models::template::CommandTemplate;
use std::collections::HashMap;

/// Application state
pub struct App {
    /// Current state of the application
    pub state: AppState,
    /// Currently active command being built
    pub current_command: CurlCommand,
    /// Command templates
    pub templates: Vec<CommandTemplate>,
    /// Environments
    pub environments: HashMap<String, Environment>,
    /// Currently selected environment
    pub current_environment: String,
    /// Command execution output
    pub output: Option<String>,
    /// Command history
    pub history: Vec<CurlCommand>,
    /// UI state
    pub ui_state: UiState,
}

/// Application state enum
pub enum AppState {
    /// Normal mode - building and executing commands
    Normal,
    /// Editing a template name
    EditingTemplateName,
    /// Editing environment variables
    EditingEnvironment,
    /// Viewing help
    Help,
    /// Exiting the application
    Exiting,
}

/// UI state
pub struct UiState {
    /// Currently active tab
    pub active_tab: Tab,
    /// Currently selected template index
    pub selected_template: Option<usize>,
    /// Whether the templates panel is expanded
    pub templates_expanded: bool,
    /// Whether the environments panel is expanded
    pub environments_expanded: bool,
    /// Whether the history panel is expanded
    pub history_expanded: bool,
    /// Currently selected option category
    pub selected_option_category: OptionCategory,
}

/// UI tabs
pub enum Tab {
    /// URL and method tab
    Url,
    /// Headers tab
    Headers,
    /// Body tab
    Body,
    /// Curl options tab
    Options,
}

/// Curl option categories
pub enum OptionCategory {
    /// Basic options
    Basic,
    /// Request options
    Request,
    /// Authentication options
    Authentication,
    /// Connection options
    Connection,
    /// Header options
    Header,
    /// SSL/TLS options
    Ssl,
    /// Proxy options
    Proxy,
    /// Output options
    Output,
}

impl Default for App {
    fn default() -> Self {
        Self {
            state: AppState::Normal,
            current_command: CurlCommand::default(),
            templates: Vec::new(),
            environments: HashMap::new(),
            current_environment: "default".to_string(),
            output: None,
            history: Vec::new(),
            ui_state: UiState {
                active_tab: Tab::Url,
                selected_template: None,
                templates_expanded: true,
                environments_expanded: true,
                history_expanded: false,
                selected_option_category: OptionCategory::Basic,
            },
        }
    }
}

impl App {
    /// Create a new application instance
    pub fn new() -> Self {
        // Create default environment
        let mut environments = HashMap::new();
        environments.insert(
            "default".to_string(),
            Environment {
                id: "env_default".to_string(),
                name: "Default".to_string(),
                variables: Vec::new(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            },
        );

        Self {
            environments,
            ..Self::default()
        }
    }

    /// Handle application events
    pub fn handle_event(&mut self, event: &crossterm::event::Event) -> bool {
        match event {
            crossterm::event::Event::Key(key_event) => self.handle_key_event(key_event),
            _ => false,
        }
    }

    /// Handle key events
    fn handle_key_event(&mut self, key_event: &crossterm::event::KeyEvent) -> bool {
        match self.state {
            AppState::Normal => self.handle_normal_mode_key(key_event),
            AppState::EditingTemplateName => self.handle_editing_template_name_key(key_event),
            AppState::EditingEnvironment => self.handle_editing_environment_key(key_event),
            AppState::Help => self.handle_help_key(key_event),
            AppState::Exiting => true,
        }
    }

    /// Handle key events in normal mode
    fn handle_normal_mode_key(&mut self, key_event: &crossterm::event::KeyEvent) -> bool {
        use crossterm::event::{KeyCode, KeyModifiers};

        match (key_event.code, key_event.modifiers) {
            // Quit application
            (KeyCode::Char('q'), KeyModifiers::CONTROL) => {
                self.state = AppState::Exiting;
                true
            }
            // Switch tabs with Tab or Right arrow
            (KeyCode::Tab, KeyModifiers::NONE) | (KeyCode::Right, KeyModifiers::NONE) => {
                self.ui_state.active_tab = match self.ui_state.active_tab {
                    Tab::Url => Tab::Headers,
                    Tab::Headers => Tab::Body,
                    Tab::Body => Tab::Options,
                    Tab::Options => Tab::Url,
                };
                false
            }
            // Switch tabs with Shift+Tab or Left arrow
            (KeyCode::BackTab, _) | (KeyCode::Left, KeyModifiers::NONE) => {
                self.ui_state.active_tab = match self.ui_state.active_tab {
                    Tab::Url => Tab::Options,
                    Tab::Headers => Tab::Url,
                    Tab::Body => Tab::Headers,
                    Tab::Options => Tab::Body,
                };
                false
            }
            // Navigate templates with Up arrow
            (KeyCode::Up, KeyModifiers::NONE) => {
                if let Some(selected) = self.ui_state.selected_template {
                    if selected > 0 {
                        self.ui_state.selected_template = Some(selected - 1);
                    }
                } else if !self.templates.is_empty() {
                    self.ui_state.selected_template = Some(0);
                }
                false
            }
            // Navigate templates with Down arrow
            (KeyCode::Down, KeyModifiers::NONE) => {
                if let Some(selected) = self.ui_state.selected_template {
                    if selected < self.templates.len().saturating_sub(1) {
                        self.ui_state.selected_template = Some(selected + 1);
                    }
                } else if !self.templates.is_empty() {
                    self.ui_state.selected_template = Some(0);
                }
                false
            }
            // Toggle panels
            (KeyCode::Char('t'), KeyModifiers::CONTROL) => {
                self.ui_state.templates_expanded = !self.ui_state.templates_expanded;
                false
            }
            (KeyCode::Char('e'), KeyModifiers::CONTROL) => {
                self.ui_state.environments_expanded = !self.ui_state.environments_expanded;
                false
            }
            (KeyCode::Char('h'), KeyModifiers::CONTROL) => {
                self.ui_state.history_expanded = !self.ui_state.history_expanded;
                false
            }
            // Show help
            (KeyCode::F(1), KeyModifiers::NONE) => {
                self.state = AppState::Help;
                false
            }
            // Default - event not handled
            _ => false,
        }
    }

    /// Handle key events in editing template name mode
    fn handle_editing_template_name_key(&mut self, key_event: &crossterm::event::KeyEvent) -> bool {
        use crossterm::event::KeyCode;

        match key_event.code {
            KeyCode::Esc => {
                self.state = AppState::Normal;
                false
            }
            _ => false,
        }
    }

    /// Handle key events in editing environment mode
    fn handle_editing_environment_key(&mut self, key_event: &crossterm::event::KeyEvent) -> bool {
        use crossterm::event::KeyCode;

        match key_event.code {
            KeyCode::Esc => {
                self.state = AppState::Normal;
                false
            }
            _ => false,
        }
    }

    /// Handle key events in help mode
    fn handle_help_key(&mut self, key_event: &crossterm::event::KeyEvent) -> bool {
        use crossterm::event::KeyCode;

        match key_event.code {
            KeyCode::Esc | KeyCode::F(1) => {
                self.state = AppState::Normal;
                false
            }
            _ => false,
        }
    }

    /// Update the current command based on user input
    pub fn update_command(&mut self) {
        // This will be implemented to update the command based on UI state
    }

    /// Execute the current command
    pub fn execute_command(&mut self) {
        // This will be implemented to execute the command and capture output
    }

    /// Save the current command as a template
    pub fn save_template(&mut self, name: String) {
        let template = CommandTemplate {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            description: None,
            command: self.current_command.clone(),
            category: None,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };

        self.templates.push(template);
    }

    /// Load a template
    pub fn load_template(&mut self, index: usize) {
        if let Some(template) = self.templates.get(index) {
            self.current_command = template.command.clone();
        }
    }
}