use crate::models::command::CurlCommand;
use crate::models::environment::Environment;
use crate::models::template::CommandTemplate;
use crate::execution::executor::{CommandExecutor, ExecutionResult};
use crate::command::builder::CommandBuilder;
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
#[derive(Clone)]
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
}

/// Selected field in each tab
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
pub enum UrlField {
    /// URL input
    Url,
    /// Method selection
    Method,
    /// Query parameters
    QueryParam(usize),
}

/// Body tab fields
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
            execution_result: None,
            history: Vec::new(),
            ui_state: UiState {
                active_tab: Tab::Url,
                selected_field: SelectedField::Url(UrlField::Url),
                selected_template: None,
                templates_expanded: true,
                environments_expanded: true,
                history_expanded: false,
                selected_option_category: OptionCategory::Basic,
                edit_buffer: String::new(),
                method_dropdown_index: 0,
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

        Self {
            environments,
            executor,
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
                self.navigate_field_up();
                false
            }
            (KeyCode::Down, KeyModifiers::NONE) => {
                self.navigate_field_down();
                false
            }
            // Navigate fields with Left/Right arrows
            (KeyCode::Left, KeyModifiers::NONE) => {
                self.navigate_field_left();
                false
            }
            (KeyCode::Right, KeyModifiers::NONE) => {
                self.navigate_field_right();
                false
            }
            // Edit current field
            (KeyCode::Enter, KeyModifiers::NONE) => {
                self.start_editing_field();
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
            // Execute command
            (KeyCode::F(5), KeyModifiers::NONE) | (KeyCode::Char('r'), KeyModifiers::CONTROL) => {
                self.execute_command();
                false
            }
            // Default - event not handled
            _ => false,
        }
    }

    /// Navigate to the field above the current one
    fn navigate_field_up(&mut self) {
        match &self.ui_state.selected_field {
            SelectedField::Url(field) => {
                match field {
                    UrlField::Url => {
                        // Already at the top, do nothing
                    }
                    UrlField::Method => {
                        self.ui_state.selected_field = SelectedField::Url(UrlField::Url);
                    }
                    UrlField::QueryParam(idx) => {
                        if *idx > 0 {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::QueryParam(idx - 1));
                        } else {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::Method);
                        }
                    }
                }
            }
            SelectedField::Headers(idx) => {
                if *idx > 0 {
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
                if *idx > 0 {
                    self.ui_state.selected_field = SelectedField::Options(idx - 1);
                }
            }
        }
    }

    /// Navigate to the field below the current one
    fn navigate_field_down(&mut self) {
        match &self.ui_state.selected_field {
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
                        if *idx < self.current_command.query_params.len() - 1 {
                            self.ui_state.selected_field = SelectedField::Url(UrlField::QueryParam(idx + 1));
                        }
                    }
                }
            }
            SelectedField::Headers(idx) => {
                if *idx < self.current_command.headers.len() - 1 {
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
                if *idx < self.current_command.options.len() - 1 {
                    self.ui_state.selected_field = SelectedField::Options(idx + 1);
                }
            }
        }
    }

    /// Navigate to the field to the left of the current one
    fn navigate_field_left(&mut self) {
        // This is used for navigating between key-value pairs
        match &self.ui_state.selected_field {
            SelectedField::Headers(idx) => {
                // Toggle between key and value
                if let Some(_header) = self.current_command.headers.get(*idx) {
                    // Toggle header enabled state
                    if let Some(header) = self.current_command.headers.get_mut(*idx) {
                        header.enabled = !header.enabled;
                    }
                }
            }
            SelectedField::Url(UrlField::QueryParam(idx)) => {
                // Toggle query param enabled state
                if let Some(param) = self.current_command.query_params.get_mut(*idx) {
                    param.enabled = !param.enabled;
                }
            }
            SelectedField::Options(idx) => {
                // Toggle option enabled state
                if let Some(option) = self.current_command.options.get_mut(*idx) {
                    option.enabled = !option.enabled;
                }
            }
            _ => {}
        }
    }

    /// Navigate to the field to the right of the current one
    fn navigate_field_right(&mut self) {
        // This is used for navigating between key-value pairs
        // For now, we'll just use it as an alias for Enter to edit the field
        self.start_editing_field();
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
                        if let Some(body) = &self.current_command.body {
                            match body {
                                crate::models::command::RequestBody::Raw(content) => {
                                    self.ui_state.edit_buffer = content.clone();
                                }
                                _ => {
                                    self.ui_state.edit_buffer = String::new();
                                }
                            }
                        } else {
                            self.ui_state.edit_buffer = String::new();
                        }
                        EditField::Body
                    }
                }
            }
            SelectedField::Options(idx) => {
                if let Some(option) = self.current_command.options.get(*idx) {
                    if let Some(value) = &option.value {
                        self.ui_state.edit_buffer = value.clone();
                        EditField::OptionValue(*idx)
                    } else {
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
                        // Set body content
                        let content = self.ui_state.edit_buffer.clone();
                        self.current_command.body = Some(crate::models::command::RequestBody::Raw(content));
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
        
        // Split command into arguments
        let args: Vec<&str> = command.split_whitespace().collect();
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
                display_output.push_str(&format!("Exit Code: {:?}\n", output.status.code()));
                display_output.push_str(&format!("Execution Time: {:?}\n\n", execution_time));
                
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
}