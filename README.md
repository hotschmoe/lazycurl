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

- Zig 0.15.1 (libvaxis main)
- curl installed on your system

### Zig Build

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/tvrl.git
   cd tvrl
   ```
2. Fetch third-party Zig dependencies (libvaxis main):
   ```
   zig build --fetch
   ```
3. Build and run the Zig executable:
   ```
   zig build run
   ```

## Development

For development, you can use the included helper script to run common Zig tasks:

```bash
# Run the Zig prototype
./dev.sh run

# Execute the Zig test suite
./dev.sh test

# Format Zig sources
./dev.sh fmt

# (Re)fetch dependencies such as libvaxis
./dev.sh fetch
```

### Manual Development Commands

If you prefer to run commands manually:

```bash
# Build and run the Zig prototype
zig build run

# Run tests
zig build test

# Format all Zig sources
zig fmt src
```


## Usage

TVRL provides a terminal UI for building curl commands. The interface is divided into several panels:

- **Command Builder**: Build your curl command with visual aids
- **Generated Command**: See the actual curl command in real-time
- **Templates**: Save and load frequently used commands
- **Output**: View the output of executed commands

Navigate through the application using the keyboard shortcuts below.

### Keyboard Shortcuts (Zig)

- `Ctrl+X` Quit
- `Ctrl+R` or `F5` Execute command
- `Ctrl+T` Toggle Templates panel
- `Ctrl+E` Toggle Environments panel
- `Ctrl+H` Toggle History panel
- `Tab` / `Shift+Tab` Cycle tabs
- Arrow keys Navigate fields and panels
- `Enter` Edit field / confirm selection
- `Esc` Cancel editing / close dropdown
- `F2` or `Ctrl+S` Save body edits
- `Backspace` / `Delete` Delete character or option
- `Home` / `End` Move cursor in text inputs

### Basic Workflow

1. Use the URL tab to set the request URL and method
2. Add headers in the Headers tab
3. Configure the request body in the Body tab
4. Set curl options in the Curl Options tab
5. Execute the command or copy it to clipboard
6. View the response in the Output panel

## Architecture

TVRL follows a modular architecture with clear separation between:

1. **User Interface Layer**: Built with libvaxis in Zig
2. **Command Builder Layer**: Generates curl commands based on user input
3. **Command Execution Layer**: Executes curl commands and captures output
4. **Data Persistence Layer**: Manages storage of templates and environments

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
