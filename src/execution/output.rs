use super::executor::ExecutionResult;
use std::time::Duration;

/// Output format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputFormat {
    /// Raw output
    Raw,
    /// Formatted output
    Formatted,
}

/// Response information
#[derive(Debug, Clone)]
pub struct ResponseInfo {
    /// HTTP status code
    pub status_code: Option<u16>,
    /// HTTP status message
    pub status_message: Option<String>,
    /// Response headers
    pub headers: Vec<(String, String)>,
    /// Response body
    pub body: String,
    /// Response size in bytes
    pub size: usize,
    /// Response time
    pub time: Duration,
}

/// Output parser
pub struct OutputParser;

impl OutputParser {
    /// Parse curl output
    pub fn parse(result: &ExecutionResult) -> ResponseInfo {
        // Combine stdout and stderr
        let output = format!("{}{}", result.stdout, result.stderr);
        
        // Parse status code and message
        let (status_code, status_message) = Self::parse_status(&output);
        
        // Parse headers and body
        let (headers, body) = Self::parse_headers_and_body(&output);
        
        // Calculate size
        let size = body.len();
        
        ResponseInfo {
            status_code,
            status_message,
            headers,
            body,
            size,
            time: result.execution_time,
        }
    }
    
    /// Parse HTTP status code and message
    fn parse_status(output: &str) -> (Option<u16>, Option<String>) {
        // Look for HTTP status line
        for line in output.lines() {
            if line.starts_with("HTTP/") {
                // Extract status code and message
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 {
                    if let Ok(code) = parts[1].parse::<u16>() {
                        let message = parts[2..].join(" ");
                        return (Some(code), Some(message));
                    }
                }
            }
        }
        
        (None, None)
    }
    
    /// Parse headers and body
    fn parse_headers_and_body(output: &str) -> (Vec<(String, String)>, String) {
        let mut headers = Vec::new();
        let mut body = String::new();
        let mut in_body = false;
        
        // Split output into lines
        let lines: Vec<&str> = output.lines().collect();
        
        // Find where headers end and body begins
        for (i, line) in lines.iter().enumerate() {
            if in_body {
                // Already in body, append line
                body.push_str(line);
                body.push('\n');
            } else if line.is_empty() {
                // Empty line marks end of headers
                in_body = true;
            } else if line.starts_with("HTTP/") {
                // Skip HTTP status line
                continue;
            } else {
                // Parse header
                let parts: Vec<&str> = line.splitn(2, ':').collect();
                if parts.len() == 2 {
                    let key = parts[0].trim().to_string();
                    let value = parts[1].trim().to_string();
                    headers.push((key, value));
                }
            }
        }
        
        (headers, body.trim().to_string())
    }
    
    /// Format response for display
    pub fn format_response(info: &ResponseInfo, format: OutputFormat) -> String {
        match format {
            OutputFormat::Raw => Self::format_raw(info),
            OutputFormat::Formatted => Self::format_formatted(info),
        }
    }
    
    /// Format response as raw output
    fn format_raw(info: &ResponseInfo) -> String {
        // Format status line
        let mut output = String::new();
        if let (Some(code), Some(message)) = (info.status_code, &info.status_message) {
            output.push_str(&format!("HTTP/1.1 {} {}\n", code, message));
        }
        
        // Format headers
        for (key, value) in &info.headers {
            output.push_str(&format!("{}: {}\n", key, value));
        }
        
        // Add empty line between headers and body
        output.push('\n');
        
        // Add body
        output.push_str(&info.body);
        
        output
    }
    
    /// Format response as formatted output
    fn format_formatted(info: &ResponseInfo) -> String {
        let mut output = String::new();
        
        // Format status and timing information
        if let Some(code) = info.status_code {
            let status_message = info.status_message.as_deref().unwrap_or("");
            output.push_str(&format!("Status: {} {}\n", code, status_message));
        }
        
        output.push_str(&format!("Time: {:.2}ms\n", info.time.as_millis()));
        output.push_str(&format!("Size: {}\n\n", Self::format_size(info.size)));
        
        // Format headers
        output.push_str("Headers:\n");
        for (key, value) in &info.headers {
            output.push_str(&format!("  {}: {}\n", key, value));
        }
        
        // Add empty line between headers and body
        output.push('\n');
        
        // Format body
        output.push_str("Body:\n");
        output.push_str(&info.body);
        
        output
    }
    
    /// Format size in human-readable format
    fn format_size(size: usize) -> String {
        if size < 1024 {
            format!("{} B", size)
        } else if size < 1024 * 1024 {
            format!("{:.1} KB", size as f64 / 1024.0)
        } else if size < 1024 * 1024 * 1024 {
            format!("{:.1} MB", size as f64 / (1024.0 * 1024.0))
        } else {
            format!("{:.1} GB", size as f64 / (1024.0 * 1024.0 * 1024.0))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution::executor::ExecutionResult;
    use std::time::Duration;
    
    #[test]
    fn test_parse_status() {
        let output = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html></html>";
        let (code, message) = OutputParser::parse_status(output);
        assert_eq!(code, Some(200));
        assert_eq!(message, Some("OK".to_string()));
    }
    
    #[test]
    fn test_parse_headers_and_body() {
        let output = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\n<html></html>";
        let (headers, body) = OutputParser::parse_headers_and_body(output);
        
        assert_eq!(headers.len(), 2);
        assert_eq!(headers[0].0, "Content-Type");
        assert_eq!(headers[0].1, "text/html");
        assert_eq!(headers[1].0, "Content-Length");
        assert_eq!(headers[1].1, "13");
        
        assert_eq!(body, "<html></html>");
    }
    
    #[test]
    fn test_parse_execution_result() {
        let result = ExecutionResult {
            command: "curl https://example.com".to_string(),
            exit_code: Some(0),
            stdout: "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html></html>".to_string(),
            stderr: String::new(),
            execution_time: Duration::from_millis(100),
            error: None,
        };
        
        let info = OutputParser::parse(&result);
        
        assert_eq!(info.status_code, Some(200));
        assert_eq!(info.status_message, Some("OK".to_string()));
        assert_eq!(info.headers.len(), 1);
        assert_eq!(info.body, "<html></html>");
        assert_eq!(info.size, 13);
        assert_eq!(info.time, Duration::from_millis(100));
    }
    
    #[test]
    fn test_format_size() {
        assert_eq!(OutputParser::format_size(100), "100 B");
        assert_eq!(OutputParser::format_size(1500), "1.5 KB");
        assert_eq!(OutputParser::format_size(1500000), "1.4 MB");
        assert_eq!(OutputParser::format_size(1500000000), "1.4 GB");
    }
}