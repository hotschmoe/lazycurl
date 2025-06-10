use std::process::{Command, Stdio};
use std::io::{BufRead, BufReader};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use which::which;

/// Execution result
#[derive(Debug, Clone)]
pub struct ExecutionResult {
    /// Command that was executed
    pub command: String,
    /// Exit code
    pub exit_code: Option<i32>,
    /// Standard output
    pub stdout: String,
    /// Standard error
    pub stderr: String,
    /// Execution time
    pub execution_time: Duration,
    /// Error message (if any)
    pub error: Option<String>,
}

/// Command executor
pub struct CommandExecutor {
    /// Path to curl executable
    curl_path: String,
}

impl CommandExecutor {
    /// Create a new command executor
    pub fn new() -> Result<Self, String> {
        // Find curl executable
        let curl_path = match which("curl") {
            Ok(path) => path.to_string_lossy().to_string(),
            Err(_) => return Err("curl executable not found in PATH".to_string()),
        };
        
        Ok(Self { curl_path })
    }
    
    /// Execute a curl command
    pub async fn execute(&self, command: &str) -> ExecutionResult {
        let start_time = Instant::now();
        
        // Split command into arguments
        let args: Vec<&str> = command.split_whitespace().collect();
        if args.is_empty() || args[0] != "curl" {
            return ExecutionResult {
                command: command.to_string(),
                exit_code: None,
                stdout: String::new(),
                stderr: String::new(),
                execution_time: start_time.elapsed(),
                error: Some("Invalid curl command".to_string()),
            };
        }
        
        // Create command
        let mut cmd = Command::new(&self.curl_path);
        cmd.args(&args[1..]);
        
        // Set up pipes for stdout and stderr
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());
        
        // Execute command
        let mut child = match cmd.spawn() {
            Ok(child) => child,
            Err(err) => {
                return ExecutionResult {
                    command: command.to_string(),
                    exit_code: None,
                    stdout: String::new(),
                    stderr: String::new(),
                    execution_time: start_time.elapsed(),
                    error: Some(format!("Failed to execute command: {}", err)),
                };
            }
        };
        
        // Set up channels for stdout and stderr
        let (stdout_tx, mut stdout_rx) = mpsc::channel(100);
        let (stderr_tx, mut stderr_rx) = mpsc::channel(100);
        
        // Read stdout
        let stdout = child.stdout.take().unwrap();
        let stdout_reader = BufReader::new(stdout);
        tokio::spawn(async move {
            for line in stdout_reader.lines() {
                if let Ok(line) = line {
                    if stdout_tx.send(line).await.is_err() {
                        break;
                    }
                }
            }
        });
        
        // Read stderr
        let stderr = child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        tokio::spawn(async move {
            for line in stderr_reader.lines() {
                if let Ok(line) = line {
                    if stderr_tx.send(line).await.is_err() {
                        break;
                    }
                }
            }
        });
        
        // Wait for command to complete
        let status = match tokio::task::spawn_blocking(move || child.wait()).await {
            Ok(Ok(status)) => status,
            Ok(Err(err)) => {
                return ExecutionResult {
                    command: command.to_string(),
                    exit_code: None,
                    stdout: String::new(),
                    stderr: String::new(),
                    execution_time: start_time.elapsed(),
                    error: Some(format!("Failed to wait for command: {}", err)),
                };
            }
            Err(err) => {
                return ExecutionResult {
                    command: command.to_string(),
                    exit_code: None,
                    stdout: String::new(),
                    stderr: String::new(),
                    execution_time: start_time.elapsed(),
                    error: Some(format!("Failed to join task: {}", err)),
                };
            }
        };
        
        // Collect stdout and stderr
        let mut stdout_output = String::new();
        while let Ok(Some(line)) = tokio::time::timeout(Duration::from_millis(100), stdout_rx.recv()).await {
            stdout_output.push_str(&line);
            stdout_output.push('\n');
        }
        
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = tokio::time::timeout(Duration::from_millis(100), stderr_rx.recv()).await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        
        // Return result
        ExecutionResult {
            command: command.to_string(),
            exit_code: status.code(),
            stdout: stdout_output,
            stderr: stderr_output,
            execution_time: start_time.elapsed(),
            error: None,
        }
    }
}

/// Mock command executor for testing
#[cfg(test)]
pub struct MockCommandExecutor;

#[cfg(test)]
impl MockCommandExecutor {
    /// Create a new mock command executor
    pub fn new() -> Self {
        Self
    }
    
    /// Execute a curl command
    pub async fn execute(&self, command: &str) -> ExecutionResult {
        // Simulate execution delay
        tokio::time::sleep(Duration::from_millis(100)).await;
        
        // Return mock result
        ExecutionResult {
            command: command.to_string(),
            exit_code: Some(0),
            stdout: "Mock stdout output".to_string(),
            stderr: String::new(),
            execution_time: Duration::from_millis(100),
            error: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_mock_executor() {
        let executor = MockCommandExecutor::new();
        let result = executor.execute("curl https://example.com").await;
        
        assert_eq!(result.command, "curl https://example.com");
        assert_eq!(result.exit_code, Some(0));
        assert_eq!(result.stdout, "Mock stdout output");
        assert!(result.stderr.is_empty());
        assert!(result.error.is_none());
    }
}