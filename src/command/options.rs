use crate::models::command::CurlOption;
use std::collections::HashMap;

/// Curl option category
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
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

impl std::fmt::Display for OptionCategory {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OptionCategory::Basic => write!(f, "Basic Options"),
            OptionCategory::Request => write!(f, "Request Options"),
            OptionCategory::Authentication => write!(f, "Authentication Options"),
            OptionCategory::Connection => write!(f, "Connection Options"),
            OptionCategory::Header => write!(f, "Header Options"),
            OptionCategory::Ssl => write!(f, "SSL/TLS Options"),
            OptionCategory::Proxy => write!(f, "Proxy Options"),
            OptionCategory::Output => write!(f, "Output Options"),
            OptionCategory::CommandLine => write!(f, "Command Line Options"),
        }
    }
}

/// Curl option complexity tier
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OptionTier {
    /// Basic tier - most common options
    Basic,
    /// Advanced tier - more specialized options
    Advanced,
    /// Expert tier - rarely used or complex options
    Expert,
}

/// Curl option definition
#[derive(Debug, Clone)]
pub struct OptionDefinition {
    /// Option flag (e.g., "-v", "--location")
    pub flag: String,
    /// Long form flag (e.g., "--verbose")
    pub long_flag: Option<String>,
    /// Option description
    pub description: String,
    /// Whether the option takes a value
    pub takes_value: bool,
    /// Option category
    pub category: OptionCategory,
    /// Option complexity tier
    pub tier: OptionTier,
}

/// Curl options manager
pub struct CurlOptions {
    /// Option definitions by flag
    options: HashMap<String, OptionDefinition>,
}

impl CurlOptions {
    /// Create a new curl options manager with all predefined options
    pub fn new() -> Self {
        let mut options = HashMap::new();
        
        // Add all predefined options
        for option in Self::predefined_options() {
            options.insert(option.flag.clone(), option);
        }
        
        Self { options }
    }
    
    /// Get an option definition by flag
    pub fn get_option(&self, flag: &str) -> Option<&OptionDefinition> {
        self.options.get(flag)
    }
    
    /// Get all options in a category
    pub fn get_options_by_category(&self, category: &OptionCategory) -> Vec<&OptionDefinition> {
        self.options
            .values()
            .filter(|opt| opt.category == *category)
            .collect()
    }
    
    /// Get all options in a tier
    pub fn get_options_by_tier(&self, tier: &OptionTier) -> Vec<&OptionDefinition> {
        self.options
            .values()
            .filter(|opt| opt.tier == *tier)
            .collect()
    }
    
    /// Get all options in a category and tier
    pub fn get_options_by_category_and_tier(
        &self,
        category: &OptionCategory,
        tier: &OptionTier,
    ) -> Vec<&OptionDefinition> {
        self.options
            .values()
            .filter(|opt| opt.category == *category && opt.tier == *tier)
            .collect()
    }
    
    /// Create a curl option from a definition
    pub fn create_option(&self, flag: &str) -> Option<CurlOption> {
        self.get_option(flag).map(|def| CurlOption {
            id: uuid::Uuid::new_v4().to_string(),
            flag: def.flag.clone(),
            value: if def.takes_value { Some(String::new()) } else { None },
            enabled: true,
        })
    }
    
    /// Predefined curl options
    fn predefined_options() -> Vec<OptionDefinition> {
        vec![
            // Basic Options
            OptionDefinition {
                flag: "-#".to_string(),
                long_flag: Some("--progress-bar".to_string()),
                description: "Display transfer progress as a bar".to_string(),
                takes_value: false,
                category: OptionCategory::Basic,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-L".to_string(),
                long_flag: Some("--location".to_string()),
                description: "Follow redirects".to_string(),
                takes_value: false,
                category: OptionCategory::Basic,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-f".to_string(),
                long_flag: Some("--fail".to_string()),
                description: "Fail silently on server errors".to_string(),
                takes_value: false,
                category: OptionCategory::Basic,
                tier: OptionTier::Basic,
            },
            
            // Request Options
            OptionDefinition {
                flag: "-X".to_string(),
                long_flag: Some("--request".to_string()),
                description: "HTTP method to use".to_string(),
                takes_value: true,
                category: OptionCategory::Request,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-d".to_string(),
                long_flag: Some("--data".to_string()),
                description: "HTTP POST data".to_string(),
                takes_value: true,
                category: OptionCategory::Request,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--data-binary".to_string(),
                long_flag: None,
                description: "HTTP POST binary data".to_string(),
                takes_value: true,
                category: OptionCategory::Request,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--data-urlencode".to_string(),
                long_flag: None,
                description: "HTTP POST data url encoded".to_string(),
                takes_value: true,
                category: OptionCategory::Request,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "-F".to_string(),
                long_flag: Some("--form".to_string()),
                description: "Specify multipart MIME data".to_string(),
                takes_value: true,
                category: OptionCategory::Request,
                tier: OptionTier::Advanced,
            },
            
            // Authentication Options
            OptionDefinition {
                flag: "-u".to_string(),
                long_flag: Some("--user".to_string()),
                description: "Server user and password".to_string(),
                takes_value: true,
                category: OptionCategory::Authentication,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--basic".to_string(),
                long_flag: None,
                description: "Use HTTP Basic Authentication".to_string(),
                takes_value: false,
                category: OptionCategory::Authentication,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--digest".to_string(),
                long_flag: None,
                description: "Use HTTP Digest Authentication".to_string(),
                takes_value: false,
                category: OptionCategory::Authentication,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--ntlm".to_string(),
                long_flag: None,
                description: "Use HTTP NTLM authentication".to_string(),
                takes_value: false,
                category: OptionCategory::Authentication,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--oauth2-bearer".to_string(),
                long_flag: None,
                description: "OAuth 2 Bearer Token".to_string(),
                takes_value: true,
                category: OptionCategory::Authentication,
                tier: OptionTier::Basic,
            },
            
            // Connection Options
            OptionDefinition {
                flag: "-k".to_string(),
                long_flag: Some("--insecure".to_string()),
                description: "Allow insecure server connections".to_string(),
                takes_value: false,
                category: OptionCategory::Connection,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--connect-timeout".to_string(),
                long_flag: None,
                description: "Maximum time allowed for connection".to_string(),
                takes_value: true,
                category: OptionCategory::Connection,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--max-time".to_string(),
                long_flag: Some("-m".to_string()),
                description: "Maximum time allowed for the transfer".to_string(),
                takes_value: true,
                category: OptionCategory::Connection,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-4".to_string(),
                long_flag: Some("--ipv4".to_string()),
                description: "Resolve names to IPv4 addresses".to_string(),
                takes_value: false,
                category: OptionCategory::Connection,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "-6".to_string(),
                long_flag: Some("--ipv6".to_string()),
                description: "Resolve names to IPv6 addresses".to_string(),
                takes_value: false,
                category: OptionCategory::Connection,
                tier: OptionTier::Advanced,
            },
            
            // Header Options
            OptionDefinition {
                flag: "-H".to_string(),
                long_flag: Some("--header".to_string()),
                description: "Pass custom header(s) to server".to_string(),
                takes_value: true,
                category: OptionCategory::Header,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-A".to_string(),
                long_flag: Some("--user-agent".to_string()),
                description: "Send User-Agent to server".to_string(),
                takes_value: true,
                category: OptionCategory::Header,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-e".to_string(),
                long_flag: Some("--referer".to_string()),
                description: "Referer URL".to_string(),
                takes_value: true,
                category: OptionCategory::Header,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-b".to_string(),
                long_flag: Some("--cookie".to_string()),
                description: "Send cookies from string/file".to_string(),
                takes_value: true,
                category: OptionCategory::Header,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-c".to_string(),
                long_flag: Some("--cookie-jar".to_string()),
                description: "Write cookies to file after operation".to_string(),
                takes_value: true,
                category: OptionCategory::Header,
                tier: OptionTier::Advanced,
            },
            
            // SSL/TLS Options
            OptionDefinition {
                flag: "--cacert".to_string(),
                long_flag: None,
                description: "CA certificate to verify peer against".to_string(),
                takes_value: true,
                category: OptionCategory::Ssl,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--cert".to_string(),
                long_flag: None,
                description: "Client certificate file".to_string(),
                takes_value: true,
                category: OptionCategory::Ssl,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--key".to_string(),
                long_flag: None,
                description: "Private key file name".to_string(),
                takes_value: true,
                category: OptionCategory::Ssl,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--ciphers".to_string(),
                long_flag: None,
                description: "SSL ciphers to use".to_string(),
                takes_value: true,
                category: OptionCategory::Ssl,
                tier: OptionTier::Expert,
            },
            OptionDefinition {
                flag: "--tls-max".to_string(),
                long_flag: None,
                description: "Set maximum allowed TLS version".to_string(),
                takes_value: true,
                category: OptionCategory::Ssl,
                tier: OptionTier::Expert,
            },
            
            // Proxy Options
            OptionDefinition {
                flag: "-x".to_string(),
                long_flag: Some("--proxy".to_string()),
                description: "Use proxy".to_string(),
                takes_value: true,
                category: OptionCategory::Proxy,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--proxy-basic".to_string(),
                long_flag: None,
                description: "Use Basic authentication on the proxy".to_string(),
                takes_value: false,
                category: OptionCategory::Proxy,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--proxy-digest".to_string(),
                long_flag: None,
                description: "Use Digest authentication on the proxy".to_string(),
                takes_value: false,
                category: OptionCategory::Proxy,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--noproxy".to_string(),
                long_flag: None,
                description: "List of hosts which do not use proxy".to_string(),
                takes_value: true,
                category: OptionCategory::Proxy,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "-p".to_string(),
                long_flag: Some("--proxytunnel".to_string()),
                description: "Operate through an HTTP proxy tunnel (using CONNECT)".to_string(),
                takes_value: false,
                category: OptionCategory::Proxy,
                tier: OptionTier::Advanced,
            },
            
            // Output Options
            OptionDefinition {
                flag: "-o".to_string(),
                long_flag: Some("--output".to_string()),
                description: "Write to file instead of stdout".to_string(),
                takes_value: true,
                category: OptionCategory::Output,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-O".to_string(),
                long_flag: Some("--remote-name".to_string()),
                description: "Write output to a file named as the remote file".to_string(),
                takes_value: false,
                category: OptionCategory::Output,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-J".to_string(),
                long_flag: Some("--remote-header-name".to_string()),
                description: "Use the header-provided filename".to_string(),
                takes_value: false,
                category: OptionCategory::Output,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "--create-dirs".to_string(),
                long_flag: None,
                description: "Create necessary local directory hierarchy".to_string(),
                takes_value: false,
                category: OptionCategory::Output,
                tier: OptionTier::Advanced,
            },
            OptionDefinition {
                flag: "-w".to_string(),
                long_flag: Some("--write-out".to_string()),
                description: "Use output FORMAT after completion".to_string(),
                takes_value: true,
                category: OptionCategory::Output,
                tier: OptionTier::Advanced,
            },
            
            // Command Line Options
            OptionDefinition {
                flag: "-v".to_string(),
                long_flag: Some("--verbose".to_string()),
                description: "Make the operation more talkative".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-s".to_string(),
                long_flag: Some("--silent".to_string()),
                description: "Silent mode".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-S".to_string(),
                long_flag: Some("--show-error".to_string()),
                description: "Show error even when silent".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-i".to_string(),
                long_flag: Some("--include".to_string()),
                description: "Include protocol response headers in the output".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-I".to_string(),
                long_flag: Some("--head".to_string()),
                description: "Show document info only".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-q".to_string(),
                long_flag: Some("--disable".to_string()),
                description: "Disable .curlrc".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-V".to_string(),
                long_flag: Some("--version".to_string()),
                description: "Show version number and quit".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-h".to_string(),
                long_flag: Some("--help".to_string()),
                description: "Show help text".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--trace".to_string(),
                long_flag: None,
                description: "Write a debug trace to FILE".to_string(),
                takes_value: true,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--trace-ascii".to_string(),
                long_flag: None,
                description: "Like --trace, but without hex output".to_string(),
                takes_value: true,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "--trace-time".to_string(),
                long_flag: None,
                description: "Add time stamps to trace/verbose output".to_string(),
                takes_value: false,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
            OptionDefinition {
                flag: "-K".to_string(),
                long_flag: Some("--config".to_string()),
                description: "Read config from a file".to_string(),
                takes_value: true,
                category: OptionCategory::CommandLine,
                tier: OptionTier::Basic,
            },
        ]
    }
}

impl Default for CurlOptions {
    fn default() -> Self {
        Self::new()
    }
}