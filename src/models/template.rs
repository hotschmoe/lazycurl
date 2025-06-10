use crate::models::command::CurlCommand;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Command template struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandTemplate {
    /// Unique identifier
    pub id: String,
    /// Template name
    pub name: String,
    /// Template description
    pub description: Option<String>,
    /// The curl command
    pub command: CurlCommand,
    /// Template category
    pub category: Option<String>,
    /// Creation timestamp
    pub created_at: DateTime<Utc>,
    /// Last update timestamp
    pub updated_at: DateTime<Utc>,
}

impl CommandTemplate {
    /// Create a new command template
    pub fn new(name: String, command: CurlCommand) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            description: None,
            command,
            category: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    /// Set the template description
    pub fn set_description(&mut self, description: String) -> &mut Self {
        self.description = Some(description);
        self
    }

    /// Set the template category
    pub fn set_category(&mut self, category: String) -> &mut Self {
        self.category = Some(category);
        self
    }
}