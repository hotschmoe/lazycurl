use crate::models::command::CurlCommand;
use crate::models::environment::Environment;
use crate::models::template::CommandTemplate;
use crate::execution::executor::{CommandExecutor, ExecutionResult};
use crate::command::builder::CommandBuilder;
use std::collections::HashMap;
use tui_textarea::{TextArea, Input};

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
    /// Command execution result
    pub execution_result: Option<ExecutionResult>,
    /// Command history
    pub history: Vec<CurlCommand>,
    /// UI state
    pub ui_state: UiState,
    /// Command executor
    pub executor: Option<CommandExecutor>,
}

/// Application state enum
pub enum AppState {
    /// Normal mode - building and executing commands
    Normal,
    /// Editing a field
    Editing(EditField),
    /// Method dropdown is open
    MethodDropdown,
    /// Editing a template name
    EditingTemplateName,
    /// Editing environment variables
    EditingEnvironment,
    /// Viewing help
    Help,
    /// Exiting the application
    Exiting,
}

/// Editable fields
#[derive(Clone, Debug)]
pub enum EditField {
    /// URL field
    Url,
    /// Method field
    Method,
    /// Header key
    HeaderKey(usize),
    /// Header value
    HeaderValue(usize),
    /// Query parameter key
    QueryParamKey(usize),
    /// Query parameter value
    QueryParamValue(usize),
    /// Body content
    Body,
    /// Option value
    OptionValue(usize),
}

/// UI state
pub struct UiState {
    /// Currently active tab
    pub active_tab: Tab,
    /// Currently selected field in the active tab
    pub selected_field: SelectedField,
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
    /// Current edit buffer for editing fields
    pub edit_buffer: String,
    /// Selected method index in dropdown (when dropdown is open)
    pub method_dropdown_index: usize,
    /// Cursor visibility for blinking effect
    pub cursor_visible: bool,
    /// Cursor blink counter for slower blinking
    pub cursor_blink_counter: u8,
    /// Text area for body editing
    pub body_textarea: TextArea<'static>,
    /// Scroll offset for options tab
    pub options_scroll_offset: usize,
}

/// Selected field in each tab
#[derive(Clone)]
pub enum SelectedField {
    /// URL tab fields
    Url(UrlField),
    /// Headers tab fields
    Headers(usize),
    /// Body tab fields
    Body(BodyField),
    /// Options tab fields
    Options(usize),
}

/// URL tab fields
#[derive(Clone)]
pub enum UrlField {
    /// URL input
    Url,
    /// Method selection
    Method,
    /// Query parameters
    QueryParam(usize),
}

/// Body tab fields
#[derive(Clone)]
pub enum BodyField {
    /// Body type selection
    Type,
    /// Body content
    Content,
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
    /// Command Line options
    CommandLine,
}

impl Default for App {
    fn default() -> Self {
        // Create default command with -i option enabled
        let mut default_command = CurlCommand::default();
        default_command.add_option("-i".to_string(), None);
        
        Self {
            state: AppState::Normal,
            current_command: default_command,
            templates: Vec::new(),
            environments: HashMap::new(),
            current_environment: "default".to_string(),
            output: None,
            execution_result: None,
            history: Vec::new(),
            ui_state: UiState {
                active_tab: Tab::Url,
                selected_field: SelectedField::Url(UrlField::Url),
                selected_template: None,
                templates_expanded: true,
                environments_expanded: true,
                history_expanded: false,
                selected_option_category: OptionCategory::CommandLine,
                edit_buffer: String::new(),
                method_dropdown_index: 0,
                cursor_visible: true,
                cursor_blink_counter: 0,
                body_textarea: TextArea::default(),
                options_scroll_offset: 0,
            },
            executor: None,
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

        // Try to create command executor
        let executor = CommandExecutor::new().ok();

        // Create some sample templates for testing
        let mut templates = Vec::new();
        
        let mut get_command = CurlCommand::default();
        get_command.name = "GET Example".to_string();
        get_command.url = "https://httpbin.org/get".to_string();
        get_command.method = Some(crate::models::command::HttpMethod::GET);
        get_command.add_option("-i".to_string(), None); // Add -i option by default
        
        templates.push(CommandTemplate {
            id: "template_1".to_string(),
            name: "GET Example".to_string(),
            description: Some("Simple GET request".to_string()),
            command: get_command,
            category: Some("Examples".to_string()),
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        });
        
        let mut post_command = CurlCommand::default();
        post_command.name = "POST JSON".to_string();
        post_command.url = "https://httpbin.org/post".to_string();
        post_command.method = Some(crate::models::command::HttpMethod::POST);
        post_command.add_header("Content-Type".to_string(), "application/json".to_string());
        post_command.body = Some(crate::models::command::RequestBody::Raw(r#"{"key": "value"}"#.to_string()));
        post_command.add_option("-i".to_string(), None); // Add -i option by default
        
        templates.push(CommandTemplate {
            id: "template_2".to_string(),
            name: "POST JSON".to_string(),
            description: Some("POST with JSON body".to_string()),
            command: post_command,
            category: Some("Examples".to_string()),
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        });

        Self {
            environments,
            executor,
            templates,
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
            AppState::Editing(ref field) => {
                let field_clone = field.clone();
                self.handle_editing_field_key(key_event, &field_clone)
            },
            AppState::MethodDropdown => self.handle_method_dropdown_key(key_event),
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
            (KeyCode::Tab, KeyModifiers::NONE) | (KeyCode::Right, KeyModifiers::CONTROL) => {
                self.ui_state.active_tab = match self.ui_state.active_tab {
                    Tab::Url => Tab::Headers,
                    Tab::Headers => Tab::Body,
                    Tab::Body => Tab::Options,
                    Tab::Options => Tab::Url,
                };
                // Reset selected field for the new tab
                self.ui_state.selected_field = match self.ui_state.active_tab {
                    Tab::Url => SelectedField::Url(UrlField::Url),
                    Tab::Headers => SelectedField::Headers(0),
                    Tab::Body => SelectedField::Body(BodyField::Content),
                    Tab::Options => SelectedField::Options(0),
                };
                false
            }
            // Switch tabs with Shift+Tab or Left arrow
            (KeyCode::BackTab, _) | (KeyCode::Left, KeyModifiers::CONTROL) => {
                self.ui_state.active_tab = match self.ui_state.active_tab {
                    Tab::Url => Tab::Options,
                    Tab::Headers => Tab::Url,
                    Tab::Body => Tab::Headers,
                    Tab::Options => Tab::Body,
                };
                // Reset selected field for the new tab
                self.ui_state.selected_field = match self.ui_state.active_tab {
                    Tab::Url => SelectedField::Url(UrlField::Url),
                    Tab::Headers => SelectedField::Headers(0),
                    Tab::Body => SelectedField::Body(BodyField::Content),
                    Tab::Options => SelectedField::Options(0),
                };
                false
            }
            // Navigate fields with Up/Down arrows
            (KeyCode::Up, KeyModifiers::NONE) => {
                if self.ui_state.selected_template.is_some() {
                    // Navigate templates
                    self.navigate_template_up();
                } else {
                    self.navigate_field_up();
                }
                false
            }
            (KeyCode::Down, KeyModifiers::NONE) => {
                if self.ui_state.selected_template.is_some() {
                    // Navigate templates
                    self.navigate_template_down();
                } else {
                    self.navigate_field_down();
                }
                false
            }
            // Navigate fields with Left/Right arrows
            (KeyCode::Left, KeyModifiers::NONE) => {
                self.navigate_field_left();
                false
            }
            (KeyCode::Right, KeyModifiers::NONE) => {
                if self.ui_state.selected_template.is_some() {
                    // From templates, go to Method field
                    self.ui_state.selected_template = None;
                    self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
                } else {
                    self.navigate_field_right();
                }
                false
            }
            // Execute command with F5 or Ctrl+R (reliable options)
            (KeyCode::F(5), KeyModifiers::NONE) | (KeyCode::Char('r'), KeyModifiers::CONTROL) => {
                self.execute_command();
                false
            }
            // Add command line option with Enter
            (KeyCode::Enter, KeyModifiers::NONE) => {
                if let SelectedField::Options(idx) = self.ui_state.selected_field {
                    // Check if we're selecting a command line option
                    if self.is_command_line_option_selected(idx) {
                        self.add_selected_command_line_option(idx);
                        return false;
                    }
                }
                
                if let Some(template_idx) = self.ui_state.selected_template {
                    // Load the selected template
                    self.load_template(template_idx);
                    // Clear template selection and go to URL field
                    self.ui_state.selected_template = None;
                    self.ui_state.selected_field = SelectedField::Url(UrlField::Url);
                } else {
                    self.start_editing_field();
                }
                false
            }
            // Remove option with Delete or Backspace
            (KeyCode::Delete, KeyModifiers::NONE) | (KeyCode::Backspace, KeyModifiers::NONE) => {
                if let SelectedField::Options(idx) = self.ui_state.selected_field {
                    // Only remove if it's an active option (not a command line option)
                    if !self.is_command_line_option_selected(idx) {
                        self.remove_option(idx);
                    }
                }
                false
            }
            // Toggle option enabled/disabled with Space
            (KeyCode::Char(' '), KeyModifiers::NONE) => {
                if let SelectedField::Options(idx) = self.ui_state.selected_field {
                    // Only toggle if it's an active option (not a command line option)
                    if !self.is_command_line_option_selected(idx) {
                        if let Some(option) = self.current_command.options.get_mut(idx) {
                            option.enabled = !option.enabled;
                        }
                    }
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

    /// Navigate to the field above the current one
    fn navigate_field_up(&mut self) {
        // Extract the current field without borrowing
        let current_field = self.ui_state.selected_field.clone();
        
        match current_field {
            SelectedField::Url(field) => {
                match field {
                    UrlField::Url => {
                        // Already at the top, do nothing
                    }
                    UrlField::Method => {
                        self.ui_state.selected_field = SelectedField::Url(UrlField::Url);
                    }
                    UrlField::QueryParam(idx) => {
                        if idx > 0 {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::QueryParam(idx - 1));
                        } else {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
                        }
                    }
                }
            }
            SelectedField::Headers(idx) => {
                if idx > 0 {
                    self.ui_state.selected_field = SelectedField::Headers(idx - 1);
                }
            }
            SelectedField::Body(field) => {
                match field {
                    BodyField::Type => {
                        // Already at the top, do nothing
                    }
                    BodyField::Content => {
                        self.ui_state.selected_field = SelectedField::Body(BodyField::Type);
                    }
                }
            }
            SelectedField::Options(idx) => {
                if idx > 0 {
                    // Update the selected field
                    self.ui_state.selected_field = SelectedField::Options(idx - 1);
                    
                    // Adjust scroll offset if needed
                    if idx <= self.ui_state.options_scroll_offset {
                        self.ui_state.options_scroll_offset = self.ui_state.options_scroll_offset.saturating_sub(1);
                    }
                }
            }
        }
    }

    /// Navigate to the field below the current one
    fn navigate_field_down(&mut self) {
        // Extract the current field without borrowing
        let current_field = self.ui_state.selected_field.clone();
        
        match current_field {
            SelectedField::Url(field) => {
                match field {
                    UrlField::Url => {
                        self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
                    }
                    UrlField::Method => {
                        if !self.current_command.query_params.is_empty() {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::QueryParam(0));
                        }
                    }
                    UrlField::QueryParam(idx) => {
                        if !self.current_command.query_params.is_empty() && idx < self.current_command.query_params.len() - 1 {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::QueryParam(idx + 1));
                        }
                    }
                }
            }
            SelectedField::Headers(idx) => {
                if !self.current_command.headers.is_empty() && idx < self.current_command.headers.len() - 1 {
                    self.ui_state.selected_field = SelectedField::Headers(idx + 1);
                }
            }
            SelectedField::Body(field) => {
                match field {
                    BodyField::Type => {
                        self.ui_state.selected_field = SelectedField::Body(BodyField::Content);
                    }
                    BodyField::Content => {
                        // Already at the bottom, do nothing
                    }
                }
            }
            SelectedField::Options(idx) => {
                // Get the total number of options (active + command line options)
                let curl_options = crate::command::options::CurlOptions::new();
                let command_line_options = curl_options.get_options_by_category(
                    &crate::command::options::OptionCategory::CommandLine
                );
                
                // Sort command line options by flag to ensure stable ordering
                let mut sorted_command_line_options = command_line_options.clone();
                sorted_command_line_options.sort_by(|a, b| a.flag.cmp(&b.flag));
                
                let total_options = self.current_command.options.len() + sorted_command_line_options.len();
                
                if idx < total_options - 1 {
                    // Update the selected field
                    self.ui_state.selected_field = SelectedField::Options(idx + 1);
                    
                    // Calculate visible rows (approximate)
                    // This is a rough estimate - we'll refine this in the render method
                    let visible_rows = 10; // Approximate number of visible rows
                    
                    // Adjust scroll offset if needed
                    if idx >= self.ui_state.options_scroll_offset + visible_rows - 2 {
                        self.ui_state.options_scroll_offset += 1;
                    }
                }
            }
        }
    }

    /// Navigate to the field to the left of the current one
    fn navigate_field_left(&mut self) {
        // Navigate left through different UI sections: Templates ← Method ← URL Container
        match &self.ui_state.selected_field {
            SelectedField::Url(UrlField::Url) => {
                // From URL field, go to Method
                self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
            }
            SelectedField::Url(UrlField::Method) => {
                // From Method, go to Templates (always select templates, even if empty)
                self.ui_state.selected_template = Some(0);
                // Don't set a selected field when templates are focused - templates take precedence
            }
            // From any field in the URL container (except URL and Method), go back to Method
            SelectedField::Headers(_) | SelectedField::Body(_) | SelectedField::Options(_) => {
                self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
            }
            SelectedField::Url(UrlField::QueryParam(_)) => {
                // From query params, also go back to Method to maintain navigation consistency
                self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
            }
        }
    }

    /// Navigate to the field to the right of the current one
    fn navigate_field_right(&mut self) {
        // Navigate right through different UI sections: Templates → Method → URL Container
        match &self.ui_state.selected_field {
            SelectedField::Url(UrlField::Method) => {
                // From Method, go to the appropriate field based on active tab
                match self.ui_state.active_tab {
                    Tab::Url => {
                        self.ui_state.selected_field = SelectedField::Url(UrlField::Url);
                    }
                    Tab::Headers => {
                        self.ui_state.selected_field = SelectedField::Headers(0);
                    }
                    Tab::Body => {
                        self.ui_state.selected_field = SelectedField::Body(BodyField::Content);
                    }
                    Tab::Options => {
                        self.ui_state.selected_field = SelectedField::Options(0);
                    }
                }
            }
            SelectedField::Url(UrlField::Url) => {
                // From URL, stay in URL (no further right navigation)
            }
            _ => {
                // For other fields, keep existing toggle behavior
                match &self.ui_state.selected_field {
                    SelectedField::Headers(idx) => {
                        // Toggle header enabled state
                        if let Some(header) = self.current_command.headers.get_mut(*idx) {
                            header.enabled = !header.enabled;
                        }
                    }
                    SelectedField::Url(UrlField::QueryParam(idx)) => {
                        // Toggle query param enabled state
                        if let Some(param) = self.current_command.query_params.get_mut(*idx) {
                            param.enabled = !param.enabled;
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    /// Start editing the current field
    fn start_editing_field(&mut self) -> bool {
        let edit_field = match &self.ui_state.selected_field {
            SelectedField::Url(field) => {
                match field {
                    UrlField::Url => {
                        self.ui_state.edit_buffer = self.current_command.url.clone();
                        EditField::Url
                    }
                    UrlField::Method => {
                        // Open method dropdown instead of editing
                        self.open_method_dropdown();
                        return false;
                    }
                    UrlField::QueryParam(idx) => {
                        if let Some(param) = self.current_command.query_params.get(*idx) {
                            self.ui_state.edit_buffer = param.value.clone();
                            EditField::QueryParamValue(*idx)
                        } else {
                            return false;
                        }
                    }
                }
            }
            SelectedField::Headers(idx) => {
                if let Some(header) = self.current_command.headers.get(*idx) {
                    self.ui_state.edit_buffer = header.value.clone();
                    EditField::HeaderValue(*idx)
                } else {
                    return false;
                }
            }
            SelectedField::Body(field) => {
                match field {
                    BodyField::Type => {
                        // Not editable directly
                        return false;
                    }
                    BodyField::Content => {
                        // Initialize the TextArea with current body content
                        let content = if let Some(body) = &self.current_command.body {
                            match body {
                                crate::models::command::RequestBody::Raw(content) => content.clone(),
                                _ => String::new(),
                            }
                        } else {
                            String::new()
                        };
                        
                        // Create a new TextArea with the content
                        self.ui_state.body_textarea = TextArea::from(content.lines().map(|s| s.to_string()).collect::<Vec<_>>());
                        
                        // Set cursor style to make it more visible
                        self.ui_state.body_textarea.set_cursor_style(ratatui::style::Style::default().bg(ratatui::style::Color::White).fg(ratatui::style::Color::Black));
                        
                        EditField::Body
                    }
                }
            }
            SelectedField::Options(idx) => {
                if let Some(option) = self.current_command.options.get(*idx) {
                    // Check if this option takes a value
                    let curl_options = crate::command::options::CurlOptions::new();
                    if let Some(option_def) = curl_options.get_option(&option.flag) {
                        // Only allow editing if the option takes a value
                        if option_def.takes_value {
                            if let Some(value) = &option.value {
                                self.ui_state.edit_buffer = value.clone();
                                EditField::OptionValue(*idx)
                            } else {
                                return false;
                            }
                        } else {
                            // Option doesn't take a value, don't allow editing
                            return false;
                        }
                    } else {
                        // Unknown option, don't allow editing
                        return false;
                    }
                } else {
                    return false;
                }
            }
        };

        self.state = AppState::Editing(edit_field);
        false
    }

    /// Handle key events in editing field mode
    fn handle_editing_field_key(&mut self, key_event: &crossterm::event::KeyEvent, field: &EditField) -> bool {
        use crossterm::event::KeyCode;

        // Handle body editing with TextArea
        if matches!(field, EditField::Body) {
            match key_event.code {
                KeyCode::Esc => {
                    // Cancel editing
                    self.state = AppState::Normal;
                    false
                }
                KeyCode::F(2) => {
                    // Save body content (F2 to save, since Enter is used for new lines)
                    let content = self.ui_state.body_textarea.lines().join("\n");
                    self.current_command.body = Some(crate::models::command::RequestBody::Raw(content));
                    self.state = AppState::Normal;
                    false
                }
                _ => {
                    // Pass all other key events to the TextArea
                    self.ui_state.body_textarea.input(Input::from(key_event.clone()));
                    false
                }
            }
        } else {
            // Handle other fields with simple edit buffer
            match key_event.code {
                KeyCode::Enter => {
                    // Save the edited value
                    match field {
                        EditField::Url => {
                            self.current_command.url = self.ui_state.edit_buffer.clone();
                        }
                        EditField::Method => {
                            // Parse method from string
                            let method_str = self.ui_state.edit_buffer.to_uppercase();
                            let method = match method_str.as_str() {
                                "GET" => crate::models::command::HttpMethod::GET,
                                "POST" => crate::models::command::HttpMethod::POST,
                                "PUT" => crate::models::command::HttpMethod::PUT,
                                "DELETE" => crate::models::command::HttpMethod::DELETE,
                                "PATCH" => crate::models::command::HttpMethod::PATCH,
                                "HEAD" => crate::models::command::HttpMethod::HEAD,
                                "OPTIONS" => crate::models::command::HttpMethod::OPTIONS,
                                _ => crate::models::command::HttpMethod::GET,
                            };
                            self.current_command.method = Some(method);
                        }
                        EditField::HeaderKey(idx) => {
                            if let Some(header) = self.current_command.headers.get_mut(*idx) {
                                header.key = self.ui_state.edit_buffer.clone();
                            }
                        }
                        EditField::HeaderValue(idx) => {
                            if let Some(header) = self.current_command.headers.get_mut(*idx) {
                                header.value = self.ui_state.edit_buffer.clone();
                            }
                        }
                        EditField::QueryParamKey(idx) => {
                            if let Some(param) = self.current_command.query_params.get_mut(*idx) {
                                param.key = self.ui_state.edit_buffer.clone();
                            }
                        }
                        EditField::QueryParamValue(idx) => {
                            if let Some(param) = self.current_command.query_params.get_mut(*idx) {
                                param.value = self.ui_state.edit_buffer.clone();
                            }
                        }
                        EditField::Body => {
                            // This case is handled above
                        }
                        EditField::OptionValue(idx) => {
                            if let Some(option) = self.current_command.options.get_mut(*idx) {
                                option.value = Some(self.ui_state.edit_buffer.clone());
                            }
                        }
                    }
                    self.state = AppState::Normal;
                    false
                }
                KeyCode::Esc => {
                    // Cancel editing
                    self.state = AppState::Normal;
                    false
                }
                KeyCode::Char(c) => {
                    // Add character to edit buffer
                    self.ui_state.edit_buffer.push(c);
                    false
                }
                KeyCode::Backspace => {
                    // Remove last character from edit buffer
                    self.ui_state.edit_buffer.pop();
                    false
                }
                _ => false,
            }
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

    /// Toggle cursor visibility for blinking effect (slower)
    pub fn toggle_cursor(&mut self) {
        self.ui_state.cursor_blink_counter = (self.ui_state.cursor_blink_counter + 1) % 6; // Blink every 6 ticks (slower)
        if self.ui_state.cursor_blink_counter == 0 {
            self.ui_state.cursor_visible = !self.ui_state.cursor_visible;
        }
    }

    /// Execute the current command
    pub fn execute_command(&mut self) {
        // Check if executor is available
        if self.executor.is_none() {
            self.output = Some("Error: curl executable not found in PATH".to_string());
            self.execution_result = None;
            return;
        }

        // Get current environment
        let environment = self.environments.get(&self.current_environment)
            .cloned()
            .unwrap_or_else(|| Environment {
                id: "default".to_string(),
                name: "Default".to_string(),
                variables: Vec::new(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            });

        // Build the curl command string
        let command_string = CommandBuilder::build(&self.current_command, &environment);
        
        // Set output to indicate execution is starting
        self.output = Some("Executing command...".to_string());
        self.execution_result = None;

        // Store the command string for async execution
        // We'll need to handle this differently since we can't do async in this sync context
        // For now, we'll create a simple synchronous version
        self.execute_command_sync(&command_string);
    }

    /// Execute command synchronously (blocking)
    fn execute_command_sync(&mut self, command: &str) {
        use std::process::Command;
        use std::time::Instant;

        let start_time = Instant::now();
        
        // Parse command properly respecting quotes
        let args = App::parse_command_args(command);
        if args.is_empty() || args[0] != "curl" {
            self.output = Some("Error: Invalid curl command".to_string());
            return;
        }

        // Execute the command
        match Command::new("curl").args(&args[1..]).output() {
            Ok(output) => {
                let execution_time = start_time.elapsed();
                let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                
                // Create execution result
                let result = ExecutionResult {
                    command: command.to_string(),
                    exit_code: output.status.code(),
                    stdout: stdout.clone(),
                    stderr: stderr.clone(),
                    execution_time,
                    error: None,
                };

                // Format output for display
                let mut display_output = String::new();
                display_output.push_str(&format!("Command: {}\n", command));
                
                // Format exit code with meaningful message
                match output.status.code() {
                    Some(0) => display_output.push_str("Status: Success (0)\n"),
                    Some(code) => {
                        let error_msg = App::get_curl_error_message(code);
                        display_output.push_str(&format!("Status: Error ({}) - {}\n", code, error_msg));
                    }
                    None => display_output.push_str("Status: Process terminated by signal\n"),
                }
                
                display_output.push_str(&format!("Execution Time: {:.2}ms\n\n", execution_time.as_millis()));
                
                if !stdout.is_empty() {
                    display_output.push_str("STDOUT:\n");
                    display_output.push_str(&stdout);
                    display_output.push_str("\n\n");
                }
                
                if !stderr.is_empty() {
                    display_output.push_str("STDERR:\n");
                    display_output.push_str(&stderr);
                }

                self.output = Some(display_output);
                self.execution_result = Some(result);

                // Add to history if successful
                if output.status.success() {
                    self.history.push(self.current_command.clone());
                }
            }
            Err(err) => {
                let execution_time = start_time.elapsed();
                let error_msg = format!("Failed to execute command: {}", err);
                
                let result = ExecutionResult {
                    command: command.to_string(),
                    exit_code: None,
                    stdout: String::new(),
                    stderr: String::new(),
                    execution_time,
                    error: Some(error_msg.clone()),
                };

                self.output = Some(format!("Error: {}", error_msg));
                self.execution_result = Some(result);
            }
        }
    }

    /// Get a human-readable error message for curl exit codes
    fn get_curl_error_message(exit_code: i32) -> &'static str {
        match exit_code {
            1 => "Unsupported protocol",
            2 => "Failed to initialize",
            3 => "URL malformed",
            4 => "A feature or option that was needed to perform the desired request was not enabled",
            5 => "Couldn't resolve proxy",
            6 => "Couldn't resolve host",
            7 => "Failed to connect to host",
            8 => "FTP weird server reply",
            9 => "FTP access denied",
            10 => "FTP accept failed",
            11 => "FTP weird PASS reply",
            12 => "FTP accept timeout",
            13 => "FTP weird PASV reply",
            14 => "FTP weird 227 format",
            15 => "FTP can't get host",
            16 => "HTTP/2 framing layer error",
            17 => "FTP couldn't set binary",
            18 => "Partial file transfer",
            19 => "FTP couldn't download/access the given file",
            20 => "FTP write error",
            21 => "FTP quote error",
            22 => "HTTP page not retrieved",
            23 => "Write error",
            24 => "Upload failed",
            25 => "Failed to open/read local data",
            26 => "Read error",
            27 => "Out of memory",
            28 => "Operation timeout",
            29 => "FTP PORT failed",
            30 => "FTP couldn't use REST",
            31 => "HTTP range error",
            32 => "HTTP post error",
            33 => "SSL connect error",
            34 => "FTP bad download resume",
            35 => "FILE couldn't read file",
            36 => "LDAP cannot bind",
            37 => "LDAP search failed",
            38 => "Function not found",
            39 => "Aborted by callback",
            40 => "Bad function argument",
            41 => "Bad calling order",
            42 => "HTTP Interface operation failed",
            43 => "Bad password entered",
            44 => "Too many redirects",
            45 => "Unknown option specified",
            46 => "Malformed telnet option",
            47 => "The peer certificate cannot be authenticated",
            48 => "Unknown TELNET option specified",
            49 => "Malformed telnet option",
            51 => "The peer's SSL certificate or SSH MD5 fingerprint was not OK",
            52 => "The server didn't reply anything",
            53 => "SSL crypto engine not found",
            54 => "Cannot set SSL crypto engine as default",
            55 => "Failed sending network data",
            56 => "Failure in receiving network data",
            58 => "Problem with the local certificate",
            59 => "Couldn't use specified cipher",
            60 => "Peer certificate cannot be authenticated with known CA certificates",
            61 => "Unrecognized transfer encoding",
            62 => "Invalid LDAP URL",
            63 => "Maximum file size exceeded",
            64 => "Requested FTP SSL level failed",
            65 => "Sending the data requires a rewind that failed",
            66 => "Failed to initialise SSL Engine",
            67 => "The user name, password, or similar was not accepted and curl failed to log in",
            68 => "File not found on TFTP server",
            69 => "Permission problem on TFTP server",
            70 => "Out of disk space on TFTP server",
            71 => "Illegal TFTP operation",
            72 => "Unknown transfer ID",
            73 => "File already exists",
            74 => "No such user",
            75 => "Character conversion failed",
            76 => "Character conversion functions required",
            77 => "Problem with reading the SSL CA cert",
            78 => "The resource referenced in the URL does not exist",
            79 => "An unspecified error occurred during the SSH session",
            80 => "Failed to shut down the SSL connection",
            82 => "Could not load CRL file",
            83 => "Issuer check failed",
            84 => "The FTP PRET command failed",
            85 => "RTSP: mismatch of CSeq numbers",
            86 => "RTSP: mismatch of Session Identifiers",
            87 => "Unable to parse FTP file list",
            88 => "FTP chunk callback reported error",
            89 => "No connection available, the session will be queued",
            90 => "SSL public key does not matched pinned public key",
            91 => "Invalid SSL certificate status",
            92 => "Stream error in HTTP/2 framing layer",
            93 => "An API function was called from inside a callback",
            94 => "An authentication function returned an error",
            95 => "A problem was detected in the HTTP/3 layer",
            96 => "QUIC connection error",
            _ => "Unknown error",
        }
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

    /// Navigate to the template above the current one
    fn navigate_template_up(&mut self) {
        if let Some(current_idx) = self.ui_state.selected_template {
            if current_idx > 0 {
                self.ui_state.selected_template = Some(current_idx - 1);
            }
        }
    }

    /// Navigate to the template below the current one
    fn navigate_template_down(&mut self) {
        if let Some(current_idx) = self.ui_state.selected_template {
            if current_idx < self.templates.len().saturating_sub(1) {
                self.ui_state.selected_template = Some(current_idx + 1);
            }
        }
    }

    /// Open the method dropdown
    fn open_method_dropdown(&mut self) {
        // Set the current method index in the dropdown
        let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];
        let current_method = self.current_command.method.as_ref().unwrap_or(&crate::models::command::HttpMethod::GET);
        let current_method_str = current_method.to_string();
        
        self.ui_state.method_dropdown_index = methods
            .iter()
            .position(|&m| m == current_method_str)
            .unwrap_or(0);
        
        self.state = AppState::MethodDropdown;
    }

    /// Handle key events in method dropdown mode
    fn handle_method_dropdown_key(&mut self, key_event: &crossterm::event::KeyEvent) -> bool {
        use crossterm::event::KeyCode;

        let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];

        match key_event.code {
            KeyCode::Up => {
                // Circular navigation: wrap to bottom when at top
                if self.ui_state.method_dropdown_index > 0 {
                    self.ui_state.method_dropdown_index -= 1;
                } else {
                    self.ui_state.method_dropdown_index = methods.len() - 1;
                }
                false
            }
            KeyCode::Down => {
                // Circular navigation: wrap to top when at bottom
                if self.ui_state.method_dropdown_index < methods.len() - 1 {
                    self.ui_state.method_dropdown_index += 1;
                } else {
                    self.ui_state.method_dropdown_index = 0;
                }
                false
            }
            KeyCode::Enter => {
                // Select the current method
                let selected_method = methods[self.ui_state.method_dropdown_index];
                let method = match selected_method {
                    "GET" => crate::models::command::HttpMethod::GET,
                    "POST" => crate::models::command::HttpMethod::POST,
                    "PUT" => crate::models::command::HttpMethod::PUT,
                    "DELETE" => crate::models::command::HttpMethod::DELETE,
                    "PATCH" => crate::models::command::HttpMethod::PATCH,
                    "HEAD" => crate::models::command::HttpMethod::HEAD,
                    "OPTIONS" => crate::models::command::HttpMethod::OPTIONS,
                    _ => crate::models::command::HttpMethod::GET,
                };
                self.current_command.method = Some(method);
                self.state = AppState::Normal;
                false
            }
            KeyCode::Esc => {
                // Cancel dropdown
                self.state = AppState::Normal;
                false
            }
            _ => false,
        }
    }

    /// Parse command arguments properly respecting quotes
    fn parse_command_args(command: &str) -> Vec<String> {
        let mut args = Vec::new();
        let mut current_arg = String::new();
        let mut in_single_quote = false;
        let mut in_double_quote = false;
        let mut chars = command.chars().peekable();

        while let Some(ch) = chars.next() {
            match ch {
                '\'' if !in_double_quote => {
                    if in_single_quote {
                        // End of single-quoted string
                        in_single_quote = false;
                    } else {
                        // Start of single-quoted string
                        in_single_quote = true;
                    }
                }
                '"' if !in_single_quote => {
                    if in_double_quote {
                        // End of double-quoted string
                        in_double_quote = false;
                    } else {
                        // Start of double-quoted string
                        in_double_quote = true;
                    }
                }
                ' ' | '\t' if !in_single_quote && !in_double_quote => {
                    // Whitespace outside quotes - end current argument
                    if !current_arg.is_empty() {
                        args.push(current_arg.clone());
                        current_arg.clear();
                    }
                    // Skip additional whitespace
                    while let Some(&next_ch) = chars.peek() {
                        if next_ch == ' ' || next_ch == '\t' {
                            chars.next();
                        } else {
                            break;
                        }
                    }
                }
                '\\' if in_single_quote => {
                    // Handle escaped characters in single quotes (limited escaping)
                    if let Some(&next_ch) = chars.peek() {
                        if next_ch == '\'' {
                            chars.next(); // consume the escaped quote
                            current_arg.push('\'');
                        } else {
                            current_arg.push(ch);
                        }
                    } else {
                        current_arg.push(ch);
                    }
                }
                '\\' if in_double_quote => {
                    // Handle escaped characters in double quotes
                    if let Some(&next_ch) = chars.peek() {
                        match next_ch {
                            '"' | '\\' | '$' | '`' | '\n' => {
                                chars.next(); // consume the escaped character
                                current_arg.push(next_ch);
                            }
                            _ => {
                                current_arg.push(ch);
                            }
                        }
                    } else {
                        current_arg.push(ch);
                    }
                }
                _ => {
                    current_arg.push(ch);
                }
            }
        }

        // Add the last argument if there is one
        if !current_arg.is_empty() {
            args.push(current_arg);
        }

        args
    }

    /// Check if the selected option is a command line option
    fn is_command_line_option_selected(&self, idx: usize) -> bool {
        // If the index is within the range of current options, it's not a command line option
        if idx < self.current_command.options.len() {
            return false;
        }
        
        // Otherwise, it's a command line option
        true
    }
    
    /// Add the selected command line option to the current command
    fn add_selected_command_line_option(&mut self, idx: usize) {
        // Get the command line options
        let curl_options = crate::command::options::CurlOptions::new();
        let command_line_options = curl_options.get_options_by_category(
            &crate::command::options::OptionCategory::CommandLine
        );
        
        // Sort command line options by flag to ensure stable ordering (same as in rendering)
        let mut sorted_command_line_options = command_line_options.clone();
        sorted_command_line_options.sort_by(|a, b| a.flag.cmp(&b.flag));
        
        // Calculate the index in the command line options list
        let cmd_option_idx = idx - self.current_command.options.len();
        
        // Check if the index is valid
        if cmd_option_idx < sorted_command_line_options.len() {
            // Get the option definition
            let option_def = &sorted_command_line_options[cmd_option_idx];
            
            // Check if this option is already in the current command
            let already_exists = self.current_command.options.iter()
                .any(|o| o.flag == option_def.flag);
            
            // If not already added, add it to the current command
            if !already_exists {
                self.current_command.add_option(
                    option_def.flag.clone(),
                    if option_def.takes_value { Some(String::new()) } else { None }
                );
                
                // Update the selected field to point to the newly added option
                self.ui_state.selected_field = SelectedField::Options(self.current_command.options.len() - 1);
            }
        }
    }
    
    /// Remove an option from the current command
    fn remove_option(&mut self, idx: usize) {
        // Check if the index is valid
        if idx < self.current_command.options.len() {
            // Remove the option
            self.current_command.options.remove(idx);
            
            // Update the selected field if needed
            if !self.current_command.options.is_empty() {
                // If there are still options, select the previous one or the last one
                let new_idx = if idx > 0 {
                    idx - 1
                } else {
                    0
                };
                self.ui_state.selected_field = SelectedField::Options(new_idx);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_command_args() {
        // Test simple command
        let args = App::parse_command_args("curl https://example.com");
        assert_eq!(args, vec!["curl", "https://example.com"]);

        // Test command with single-quoted JSON
        let args = App::parse_command_args("curl -X POST -H 'Content-Type: application/json' -d '{\"key\": \"value\"}' https://httpbin.org/post");
        assert_eq!(args, vec![
            "curl",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            "{\"key\": \"value\"}",
            "https://httpbin.org/post"
        ]);

        // Test command with double-quoted arguments
        let args = App::parse_command_args("curl -H \"Authorization: Bearer token123\" https://api.example.com");
        assert_eq!(args, vec![
            "curl",
            "-H",
            "Authorization: Bearer token123",
            "https://api.example.com"
        ]);

        // Test command with mixed quotes
        let args = App::parse_command_args("curl -d '{\"name\": \"John\"}' -H \"Content-Type: application/json\"");
        assert_eq!(args, vec![
            "curl",
            "-d",
            "{\"name\": \"John\"}",
            "-H",
            "Content-Type: application/json"
        ]);
    }
}