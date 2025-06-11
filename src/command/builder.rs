use crate::models::command::{CurlCommand, RequestBody};
use crate::models::environment::Environment;
use regex::Regex;

/// Command builder for generating curl commands
pub struct CommandBuilder;

impl CommandBuilder {
    /// Build a curl command string from a CurlCommand and Environment
    pub fn build(command: &CurlCommand, environment: &Environment) -> String {
        let mut args = vec!["curl".to_string()];
        
        // Add enabled options
        for option in &command.options {
            if option.enabled {
                args.push(option.flag.clone());
                if let Some(value) = &option.value {
                    let value_with_env = Self::substitute_env_vars(value, environment);
                    args.push(value_with_env);
                }
            }
        }
        
        // Add method if specified and not GET
        if let Some(method) = &command.method {
            if method.to_string() != "GET" {
                args.push("-X".to_string());
                args.push(method.to_string());
            }
        }
        
        // Add headers
        for header in &command.headers {
            if header.enabled {
                let header_value = Self::substitute_env_vars(&header.value, environment);
                args.push("-H".to_string());
                args.push(format!("{}: {}", header.key, header_value));
            }
        }
        
        // Add request body if applicable
        if let Some(body) = &command.body {
            match body {
                RequestBody::Raw(content) => {
                    // Only add -d flag if content is not empty
                    if !content.trim().is_empty() {
                        let content_with_env = Self::substitute_env_vars(content, environment);
                        args.push("-d".to_string());
                        args.push(content_with_env);
                    }
                },
                RequestBody::FormData(items) => {
                    for item in items {
                        if item.enabled {
                            args.push("-F".to_string());
                            let value = Self::substitute_env_vars(&item.value, environment);
                            args.push(format!("{}={}", item.key, value));
                        }
                    }
                },
                RequestBody::Binary(path) => {
                    args.push("--data-binary".to_string());
                    args.push(format!("@{}", path.display()));
                },
                RequestBody::None => {}
            }
        }
        
        // Add URL with environment variable substitution
        let url_with_query = Self::build_url_with_query(command, environment);
        args.push(url_with_query);
        
        // Format the command for display
        Self::format_curl_command(&args)
    }

    /// Build URL with query parameters
    fn build_url_with_query(command: &CurlCommand, environment: &Environment) -> String {
        let base_url = Self::substitute_env_vars(&command.url, environment);
        
        // If no query params or none enabled, return the base URL
        if command.query_params.is_empty() || !command.query_params.iter().any(|p| p.enabled) {
            return base_url;
        }
        
        // Build query string
        let query_string: String = command.query_params
            .iter()
            .filter(|p| p.enabled)
            .map(|p| {
                let value = Self::substitute_env_vars(&p.value, environment);
                format!("{}={}", p.key, urlencoding::encode(&value))
            })
            .collect::<Vec<String>>()
            .join("&");
        
        // Append query string to URL
        if base_url.contains('?') {
            format!("{}&{}", base_url, query_string)
        } else {
            format!("{}?{}", base_url, query_string)
        }
    }

    /// Substitute environment variables in a string
    pub fn substitute_env_vars(input: &str, environment: &Environment) -> String {
        let mut result = input.to_string();
        
        // Regular expression to match {{variable}} patterns
        let re = Regex::new(r"\{\{([^:}]+)(?::([^}]+))?\}\}").unwrap();
        
        while let Some(captures) = re.captures(&result) {
            let full_match = captures.get(0).unwrap().as_str();
            let var_name = captures.get(1).unwrap().as_str();
            let default_value = captures.get(2).map(|m| m.as_str());
            
            // Look up variable in environment
            let replacement = environment.variables
                .iter()
                .find(|v| v.key == var_name)
                .map(|v| v.value.clone())
                .or_else(|| default_value.map(|s| s.to_string()))
                .unwrap_or_else(|| full_match.to_string());
            
            result = result.replacen(full_match, &replacement, 1);
        }
        
        result
    }

    /// Format a curl command for display
    fn format_curl_command(args: &[String]) -> String {
        // Format the command for better readability
        // This could include line breaks for long commands
        let mut formatted = String::new();
        let mut current_line_length = 0;
        let max_line_length = 80;
        
        for (i, arg) in args.iter().enumerate() {
            if i > 0 && current_line_length + arg.len() > max_line_length {
                formatted.push_str(" \\\n      ");
                current_line_length = 6;
            }
            
            if i > 0 {
                formatted.push(' ');
                current_line_length += 1;
            }
            
            // Handle arguments that need quoting
            if arg.contains(' ') && !arg.starts_with('"') && !arg.starts_with('\'') {
                formatted.push('"');
                formatted.push_str(arg);
                formatted.push('"');
                current_line_length += arg.len() + 2;
            } else {
                formatted.push_str(arg);
                current_line_length += arg.len();
            }
        }
        
        formatted
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::command::{CurlOption, Header, HttpMethod, QueryParam};

    #[test]
    fn test_build_simple_command() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        
        let environment = Environment::new("test".to_string());
        
        let result = CommandBuilder::build(&command, &environment);
        assert_eq!(result, "curl https://example.com");
    }

    #[test]
    fn test_build_command_with_options() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.options.push(CurlOption {
            id: "1".to_string(),
            flag: "-v".to_string(),
            value: None,
            enabled: true,
        });
        
        let environment = Environment::new("test".to_string());
        
        let result = CommandBuilder::build(&command, &environment);
        assert_eq!(result, "curl -v https://example.com");
    }

    #[test]
    fn test_build_command_with_headers() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.headers.push(Header {
            id: "1".to_string(),
            key: "Content-Type".to_string(),
            value: "application/json".to_string(),
            enabled: true,
        });
        
        let environment = Environment::new("test".to_string());
        
        let result = CommandBuilder::build(&command, &environment);
        assert_eq!(result, "curl -H \"Content-Type: application/json\" https://example.com");
    }

    #[test]
    fn test_build_command_with_method() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.method = Some(HttpMethod::POST);
        
        let environment = Environment::new("test".to_string());
        
        let result = CommandBuilder::build(&command, &environment);
        assert_eq!(result, "curl -X POST https://example.com");
    }

    #[test]
    fn test_build_command_with_query_params() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.query_params.push(QueryParam {
            id: "1".to_string(),
            key: "q".to_string(),
            value: "test query".to_string(),
            enabled: true,
        });
        
        let environment = Environment::new("test".to_string());
        
        let result = CommandBuilder::build(&command, &environment);
        assert_eq!(result, "curl https://example.com?q=test%20query");
    }

    #[test]
    fn test_substitute_env_vars() {
        let mut environment = Environment::new("test".to_string());
        environment.add_variable("api_url".to_string(), "https://api.example.com".to_string(), false);
        environment.add_variable("api_key".to_string(), "secret-key".to_string(), true);
        
        let input = "{{api_url}}/users?key={{api_key}}";
        let result = CommandBuilder::substitute_env_vars(input, &environment);
        
        assert_eq!(result, "https://api.example.com/users?key=secret-key");
    }

    #[test]
    fn test_substitute_env_vars_with_default() {
        let environment = Environment::new("test".to_string());
        
        let input = "{{api_url:https://default.example.com}}/users";
        let result = CommandBuilder::substitute_env_vars(input, &environment);
        
        assert_eq!(result, "https://default.example.com/users");
    }
}