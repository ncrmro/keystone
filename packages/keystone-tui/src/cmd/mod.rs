//! CLI command infrastructure — JSON envelope types and re-exports.

use serde::Serialize;

// Re-export template types and execution from their canonical location.
pub use crate::components::template::run::execute as run_template;
pub use crate::components::template::types::{TemplateParams, TemplateResult};

pub mod build;
pub mod doctor;
pub mod switch;
pub mod update;

/// Standard JSON output envelope for all commands.
#[derive(Debug, Serialize)]
pub struct JsonOutput<T: Serialize> {
    pub status: &'static str,
    pub data: T,
}

impl<T: Serialize> JsonOutput<T> {
    pub fn ok(data: T) -> Self {
        Self { status: "ok", data }
    }
}

/// Standard JSON error output.
#[derive(Debug, Serialize)]
pub struct JsonError {
    pub status: &'static str,
    pub error: String,
}

impl JsonError {
    pub fn new(msg: impl Into<String>) -> Self {
        Self {
            status: "error",
            error: msg.into(),
        }
    }
}
