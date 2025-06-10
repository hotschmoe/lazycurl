use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// HTTP method enum
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum HttpMethod {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
    TRACE,
    CONNECT,
}

impl Default for HttpMethod {
    fn default() -> Self {
        Self::GET
    }
}

impl std::fmt::Display for HttpMethod {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HttpMethod::GET => write!(f, "GET"),
            HttpMethod::POST => write!(f, "POST"),
            HttpMethod::PUT => write!(f, "PUT"),
            HttpMethod::DELETE => write!(f, "DELETE"),
            HttpMethod::PATCH => write!(f, "PATCH"),
            HttpMethod::HEAD => write!(f, "HEAD"),
            HttpMethod::OPTIONS => write!(f, "OPTIONS"),
            HttpMethod::TRACE => write!(f, "TRACE"),
            HttpMethod::CONNECT => write!(f, "CONNECT"),
        }
    }
}

/// Header struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Header {
    /// Unique identifier
    pub id: String,
    /// Header key
    pub key: String,
    /// Header value
    pub value: String,
    /// Whether the header is enabled
    pub enabled: bool,
}

/// Query parameter struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryParam {
    /// Unique identifier
    pub id: String,
    /// Parameter key
    pub key: String,
    /// Parameter value
    pub value: String,
    /// Whether the parameter is enabled
    pub enabled: bool,
}

/// Form data item struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormDataItem {
    /// Unique identifier
    pub id: String,
    /// Item key
    pub key: String,
    /// Item value
    pub value: String,
    /// Whether the item is enabled
    pub enabled: bool,
}

/// Request body enum
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RequestBody {
    /// No body
    None,
    /// Raw text body
    Raw(String),
    /// Form data body
    FormData(Vec<FormDataItem>),
    /// Binary file body
    Binary(PathBuf),
}

impl Default for RequestBody {
    fn default() -> Self {
        Self::None
    }
}

/// Curl option struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CurlOption {
    /// Unique identifier
    pub id: String,
    /// Option flag (e.g., "-v", "--location")
    pub flag: String,
    /// Option value (if applicable)
    pub value: Option<String>,
    /// Whether the option is enabled
    pub enabled: bool,
}

/// Curl command struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CurlCommand {
    /// Unique identifier
    pub id: String,
    /// Command name
    pub name: String,
    /// Command description
    pub description: Option<String>,
    /// URL
    pub url: String,
    /// HTTP method
    pub method: Option<HttpMethod>,
    /// Headers
    pub headers: Vec<Header>,
    /// Query parameters
    pub query_params: Vec<QueryParam>,
    /// Request body
    pub body: Option<RequestBody>,
    /// Curl options
    pub options: Vec<CurlOption>,
    /// Creation timestamp
    pub created_at: DateTime<Utc>,
    /// Last update timestamp
    pub updated_at: DateTime<Utc>,
}

impl Default for CurlCommand {
    fn default() -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: "New Command".to_string(),
            description: None,
            url: "https://".to_string(),
            method: Some(HttpMethod::GET),
            headers: Vec::new(),
            query_params: Vec::new(),
            body: None,
            options: Vec::new(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }
}

impl CurlCommand {
    /// Create a new curl command
    pub fn new(url: String) -> Self {
        Self {
            url,
            ..Self::default()
        }
    }

    /// Add a header
    pub fn add_header(&mut self, key: String, value: String) -> &mut Self {
        self.headers.push(Header {
            id: uuid::Uuid::new_v4().to_string(),
            key,
            value,
            enabled: true,
        });
        self
    }

    /// Add a query parameter
    pub fn add_query_param(&mut self, key: String, value: String) -> &mut Self {
        self.query_params.push(QueryParam {
            id: uuid::Uuid::new_v4().to_string(),
            key,
            value,
            enabled: true,
        });
        self
    }

    /// Add a curl option
    pub fn add_option(&mut self, flag: String, value: Option<String>) -> &mut Self {
        self.options.push(CurlOption {
            id: uuid::Uuid::new_v4().to_string(),
            flag,
            value,
            enabled: true,
        });
        self
    }

    /// Set the HTTP method
    pub fn set_method(&mut self, method: HttpMethod) -> &mut Self {
        self.method = Some(method);
        self
    }

    /// Set the request body
    pub fn set_body(&mut self, body: RequestBody) -> &mut Self {
        self.body = Some(body);
        self
    }
}