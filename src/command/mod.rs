pub mod builder;
pub mod options;
pub mod validation;

pub use builder::CommandBuilder;
pub use options::{CurlOptions, OptionCategory, OptionDefinition, OptionTier};
pub use validation::{CommandValidator, ValidationResult};