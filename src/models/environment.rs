use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Environment variable struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentVariable {
    /// Unique identifier
    pub id: String,
    /// Variable key
    pub key: String,
    /// Variable value
    pub value: String,
    /// Whether the variable is a secret
    pub is_secret: bool,
}

/// Environment struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Environment {
    /// Unique identifier
    pub id: String,
    /// Environment name
    pub name: String,
    /// Environment variables
    pub variables: Vec<EnvironmentVariable>,
    /// Creation timestamp
    pub created_at: DateTime<Utc>,
    /// Last update timestamp
    pub updated_at: DateTime<Utc>,
}

impl Environment {
    /// Create a new environment
    pub fn new(name: String) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            variables: Vec::new(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    /// Add a variable
    pub fn add_variable(&mut self, key: String, value: String, is_secret: bool) -> &mut Self {
        self.variables.push(EnvironmentVariable {
            id: uuid::Uuid::new_v4().to_string(),
            key,
            value,
            is_secret,
        });
        self
    }

    /// Get a variable value by key
    pub fn get_variable(&self, key: &str) -> Option<&str> {
        self.variables
            .iter()
            .find(|v| v.key == key)
            .map(|v| v.value.as_str())
    }

    /// Update a variable value
    pub fn update_variable(&mut self, key: &str, value: String) -> bool {
        if let Some(var) = self.variables.iter_mut().find(|v| v.key == key) {
            var.value = value;
            self.updated_at = Utc::now();
            true
        } else {
            false
        }
    }

    /// Remove a variable
    pub fn remove_variable(&mut self, key: &str) -> bool {
        let initial_len = self.variables.len();
        self.variables.retain(|v| v.key != key);
        self.updated_at = Utc::now();
        self.variables.len() < initial_len
    }
}