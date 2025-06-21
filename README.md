# TVRL - Terminal Visual Curl

TVRL (Terminal Visual Curl) is a terminal-based UI application that provides a visual interface for building curl commands. Unlike Postman or Insomnia which abstract away the underlying HTTP requests, TVRL focuses on making curl itself more accessible through visual aids while preserving the power and flexibility of the curl command line tool.

## Features

- Build curl commands visually with toggleable options
- See the actual curl command in real-time as you make changes
- Execute commands directly from the UI
- Copy commands to clipboard for use elsewhere
- Save frequently used commands as templates
- Manage environment variables for different contexts
- Secure storage of sensitive information

## Installation

### Prerequisites

- Rust 1.82 or later
- curl installed on your system

### Building from Source

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/tvrl.git
   cd tvrl
   ```

2. Build the project:
   ```
   cargo build --release
   ```

3. Run the application:
   ```
   cargo run --release
   ```

## Development

For development, you can use the included development script that automatically rebuilds and restarts the application when you make changes:

```bash
./dev.sh
```

This uses `cargo-watch` to monitor file changes and automatically restart the application. The script will:
- Watch for changes in your source files
- Automatically rebuild the project when changes are detected
- Restart the application with the new changes
- Display build errors if compilation fails

To stop the development server, press `Ctrl+C`.

### Manual Development Commands

If you prefer to run commands manually:

```bash
# Install cargo-watch (if not already installed)
cargo install cargo-watch

# Run with automatic restart on file changes
cargo watch -x run

# Or run normally for a single execution
cargo run
```

## Usage

TVRL provides a terminal UI for building curl commands. The interface is divided into several panels:

- **Command Builder**: Build your curl command with visual aids
- **Generated Command**: See the actual curl command in real-time
- **Templates**: Save and load frequently used commands
- **Output**: View the output of executed commands

Navigate through the application using keyboard shortcuts. See [SHORTCUTS.md](SHORTCUTS.md) for a complete list of keyboard shortcuts.

### Basic Workflow

1. Use the URL tab to set the request URL and method
2. Add headers in the Headers tab
3. Configure the request body in the Body tab
4. Set curl options in the Curl Options tab
5. Execute the command or copy it to clipboard
6. View the response in the Output panel

## Architecture

TVRL follows a modular architecture with clear separation between:

1. **User Interface Layer**: Built with ratatui
2. **Command Builder Layer**: Generates curl commands based on user input
3. **Command Execution Layer**: Executes curl commands and captures output
4. **Data Persistence Layer**: Manages storage of templates and environments

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.