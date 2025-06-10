use crate::models::command::CurlCommand;
use url::Url;

/// Validation result
pub enum ValidationResult {
    /// Command is valid
    Valid,
    /// Command has warnings
    Warning(Vec<String>),
    /// Command has errors
    Error(Vec<String>),
}

impl ValidationResult {
    /// Check if the validation result is valid
    pub fn is_valid(&self) -> bool {
        matches!(self, ValidationResult::Valid)
    }

    /// Check if the validation result has warnings
    pub fn has_warnings(&self) -> bool {
        matches!(self, ValidationResult::Warning(_))
    }

    /// Check if the validation result has errors
    pub fn has_errors(&self) -> bool {
        matches!(self, ValidationResult::Error(_))
    }

    /// Get warnings
    pub fn warnings(&self) -> Vec<String> {
        match self {
            ValidationResult::Warning(warnings) => warnings.clone(),
            _ => Vec::new(),
        }
    }

    /// Get errors
    pub fn errors(&self) -> Vec<String> {
        match self {
            ValidationResult::Error(errors) => errors.clone(),
            _ => Vec::new(),
        }
    }
}

/// Command validator
pub struct CommandValidator;

impl CommandValidator {
    /// Validate a curl command
    pub fn validate(command: &CurlCommand) -> ValidationResult {
        let mut errors = Vec::new();
        let mut warnings = Vec::new();

        // Validate URL
        if let Err(err) = Self::validate_url(&command.url) {
            errors.push(format!("Invalid URL: {}", err));
        }

        // Validate options
        Self::validate_options(command, &mut errors, &mut warnings);

        // Return validation result
        if !errors.is_empty() {
            ValidationResult::Error(errors)
        } else if !warnings.is_empty() {
            ValidationResult::Warning(warnings)
        } else {
            ValidationResult::Valid
        }
    }

    /// Validate URL
    fn validate_url(url: &str) -> Result<(), String> {
        // Check if URL is empty
        if url.trim().is_empty() {
            return Err("URL cannot be empty".to_string());
        }

        // Check if URL contains environment variables
        if url.contains("{{") && url.contains("}}") {
            // URL contains environment variables, so we can't fully validate it
            return Ok(());
        }

        // Parse URL
        match Url::parse(url) {
            Ok(_) => Ok(()),
            Err(err) => Err(err.to_string()),
        }
    }

    /// Validate options
    fn validate_options(command: &CurlCommand, errors: &mut Vec<String>, warnings: &mut Vec<String>) {
        // Check for conflicting options
        Self::check_conflicting_options(command, errors);

        // Check for missing required values
        Self::check_missing_values(command, errors);

        // Check for potentially problematic combinations
        Self::check_problematic_combinations(command, warnings);
    }

    /// Check for conflicting options
    fn check_conflicting_options(command: &CurlCommand, errors: &mut Vec<String>) {
        let enabled_options: Vec<&String> = command
            .options
            .iter()
            .filter(|opt| opt.enabled)
            .map(|opt| &opt.flag)
            .collect();

        // Check for -s (silent) and -v (verbose)
        if enabled_options.contains(&&"-s".to_string()) && enabled_options.contains(&&"-v".to_string()) {
            errors.push("Conflicting options: -s (silent) and -v (verbose) cannot be used together".to_string());
        }

        // Check for -I (head) and request body
        if enabled_options.contains(&&"-I".to_string()) && command.body.is_some() {
            errors.push("Conflicting options: -I (head) cannot be used with a request body".to_string());
        }
    }

    /// Check for missing required values
    fn check_missing_values(command: &CurlCommand, errors: &mut Vec<String>) {
        for option in &command.options {
            if !option.enabled {
                continue;
            }

            // Check if option requires a value
            let requires_value = match option.flag.as_str() {
                "-X" | "--request" | "-d" | "--data" | "--data-binary" | "--data-urlencode" |
                "-F" | "--form" | "-u" | "--user" | "--oauth2-bearer" | "--connect-timeout" |
                "--max-time" | "-H" | "--header" | "-A" | "--user-agent" | "-e" | "--referer" |
                "-b" | "--cookie" | "-c" | "--cookie-jar" | "--cacert" | "--cert" | "--key" |
                "--ciphers" | "--tls-max" | "-x" | "--proxy" | "--noproxy" | "-o" | "--output" |
                "-w" | "--write-out" => true,
                _ => false,
            };

            if requires_value && (option.value.is_none() || option.value.as_ref().unwrap().trim().is_empty()) {
                errors.push(format!("Option {} requires a value", option.flag));
            }
        }
    }

    /// Check for potentially problematic combinations
    fn check_problematic_combinations(command: &CurlCommand, warnings: &mut Vec<String>) {
        let enabled_options: Vec<&String> = command
            .options
            .iter()
            .filter(|opt| opt.enabled)
            .map(|opt| &opt.flag)
            .collect();

        // Check for -k (insecure) option
        if enabled_options.contains(&&"-k".to_string()) || enabled_options.contains(&&"--insecure".to_string()) {
            warnings.push("The -k/--insecure option disables SSL certificate verification, which may be insecure".to_string());
        }

        // Check for very long timeout
        for option in &command.options {
            if !option.enabled {
                continue;
            }

            if (option.flag == "--max-time" || option.flag == "-m") && option.value.is_some() {
                if let Ok(timeout) = option.value.as_ref().unwrap().parse::<u32>() {
                    if timeout > 300 {
                        warnings.push(format!("Long timeout value ({}s) may cause the command to hang", timeout));
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::command::{CurlOption, HttpMethod};

    #[test]
    fn test_validate_valid_command() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        
        let result = CommandValidator::validate(&command);
        assert!(matches!(result, ValidationResult::Valid));
    }

    #[test]
    fn test_validate_invalid_url() {
        let mut command = CurlCommand::default();
        command.url = "not a url".to_string();
        
        let result = CommandValidator::validate(&command);
        assert!(matches!(result, ValidationResult::Error(_)));
    }

    #[test]
    fn test_validate_conflicting_options() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.options.push(CurlOption {
            id: "1".to_string(),
            flag: "-s".to_string(),
            value: None,
            enabled: true,
        });
        command.options.push(CurlOption {
            id: "2".to_string(),
            flag: "-v".to_string(),
            value: None,
            enabled: true,
        });
        
        let result = CommandValidator::validate(&command);
        assert!(matches!(result, ValidationResult::Error(_)));
    }

    #[test]
    fn test_validate_missing_values() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.options.push(CurlOption {
            id: "1".to_string(),
            flag: "-H".to_string(),
            value: None, // Missing value for header
            enabled: true,
        });
        
        let result = CommandValidator::validate(&command);
        assert!(matches!(result, ValidationResult::Error(_)));
    }

    #[test]
    fn test_validate_insecure_warning() {
        let mut command = CurlCommand::default();
        command.url = "https://example.com".to_string();
        command.options.push(CurlOption {
            id: "1".to_string(),
            flag: "-k".to_string(),
            value: None,
            enabled: true,
        });
        
        let result = CommandValidator::validate(&command);
        assert!(matches!(result, ValidationResult::Warning(_)));
    }
}