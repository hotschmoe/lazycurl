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
        
        // Return result with enhanced error information
        let error_message = if let Some(code) = status.code() {
            if code != 0 {
                Some(format!("Command failed with exit code {}: {}", code, CommandExecutor::get_curl_error_message(code)))
            } else {
                None
            }
        } else {
            Some("Process terminated by signal".to_string())
        };

        ExecutionResult {
            command: command.to_string(),
            exit_code: status.code(),
            stdout: stdout_output,
            stderr: stderr_output,
            execution_time: start_time.elapsed(),
            error: error_message,
        }
    }

    /// Get a human-readable error message for curl exit codes
    fn get_curl_error_message(exit_code: i32) -> &'static str {
        match exit_code {
            1 => "Unsupported protocol",
            2 => "Failed to initialize",
            3 => "URL malformed",
            4 => "A feature or option that was needed to perform the desired request was not enabled",
            5 => "Couldn't resolve proxy",
            6 => "Couldn't resolve host",
            7 => "Failed to connect to host",
            8 => "FTP weird server reply",
            9 => "FTP access denied",
            10 => "FTP accept failed",
            11 => "FTP weird PASS reply",
            12 => "FTP accept timeout",
            13 => "FTP weird PASV reply",
            14 => "FTP weird 227 format",
            15 => "FTP can't get host",
            16 => "HTTP/2 framing layer error",
            17 => "FTP couldn't set binary",
            18 => "Partial file transfer",
            19 => "FTP couldn't download/access the given file",
            20 => "FTP write error",
            21 => "FTP quote error",
            22 => "HTTP page not retrieved",
            23 => "Write error",
            24 => "Upload failed",
            25 => "Failed to open/read local data",
            26 => "Read error",
            27 => "Out of memory",
            28 => "Operation timeout",
            29 => "FTP PORT failed",
            30 => "FTP couldn't use REST",
            31 => "HTTP range error",
            32 => "HTTP post error",
            33 => "SSL connect error",
            34 => "FTP bad download resume",
            35 => "FILE couldn't read file",
            36 => "LDAP cannot bind",
            37 => "LDAP search failed",
            38 => "Function not found",
            39 => "Aborted by callback",
            40 => "Bad function argument",
            41 => "Bad calling order",
            42 => "HTTP Interface operation failed",
            43 => "Bad password entered",
            44 => "Too many redirects",
            45 => "Unknown option specified",
            46 => "Malformed telnet option",
            47 => "The peer certificate cannot be authenticated",
            48 => "Unknown TELNET option specified",
            49 => "Malformed telnet option",
            51 => "The peer's SSL certificate or SSH MD5 fingerprint was not OK",
            52 => "The server didn't reply anything",
            53 => "SSL crypto engine not found",
            54 => "Cannot set SSL crypto engine as default",
            55 => "Failed sending network data",
            56 => "Failure in receiving network data",
            58 => "Problem with the local certificate",
            59 => "Couldn't use specified cipher",
            60 => "Peer certificate cannot be authenticated with known CA certificates",
            61 => "Unrecognized transfer encoding",
            62 => "Invalid LDAP URL",
            63 => "Maximum file size exceeded",
            64 => "Requested FTP SSL level failed",
            65 => "Sending the data requires a rewind that failed",
            66 => "Failed to initialise SSL Engine",
            67 => "The user name, password, or similar was not accepted and curl failed to log in",
            68 => "File not found on TFTP server",
            69 => "Permission problem on TFTP server",
            70 => "Out of disk space on TFTP server",
            71 => "Illegal TFTP operation",
            72 => "Unknown transfer ID",
            73 => "File already exists",
            74 => "No such user",
            75 => "Character conversion failed",
            76 => "Character conversion functions required",
            77 => "Problem with reading the SSL CA cert",
            78 => "The resource referenced in the URL does not exist",
            79 => "An unspecified error occurred during the SSH session",
            80 => "Failed to shut down the SSL connection",
            82 => "Could not load CRL file",
            83 => "Issuer check failed",
            84 => "The FTP PRET command failed",
            85 => "RTSP: mismatch of CSeq numbers",
            86 => "RTSP: mismatch of Session Identifiers",
            87 => "Unable to parse FTP file list",
            88 => "FTP chunk callback reported error",
            89 => "No connection available, the session will be queued",
            90 => "SSL public key does not matched pinned public key",
            91 => "Invalid SSL certificate status",
            92 => "Stream error in HTTP/2 framing layer",
            93 => "An API function was called from inside a callback",
            94 => "An authentication function returned an error",
            95 => "A problem was detected in the HTTP/3 layer",
            96 => "QUIC connection error",
            _ => "Unknown error",
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